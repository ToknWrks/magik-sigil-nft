# Backend integration guide

How an off-chain backend (the voucher `signer`) works with `SigilNFT`: what to host, what to sign,
and what to check first. The contract only verifies signatures; everything else here is the
backend's job.

## 1. Host the metadata

`tokenURI` is a string the contract stores and returns as-is. Marketplaces fetch it and expect
standard ERC-721 metadata JSON:

```json
{
  "name": "Sigil #1",
  "description": "An Illuminati.Earth Magik Sigil.",
  "image": "ipfs://<image-CID>",
  "attributes": [{ "trait_type": "Element", "value": "Fire" }]
}
```

Use `ipfs://<metadata-CID>` as the `tokenURI`. Pin both the image and the JSON with a pinning
service (Pinata, Filebase, Storacha, or similar) and keep them pinned: unpinned content can
disappear. Content-addressed URIs mean every rework produces a new CID, which becomes the new
`tokenURI`. Plain `https://` URIs also work, but whoever controls the host can change or remove
what the token shows without any transaction.

## 2. Typed data

Vouchers are EIP-712 typed data. Domain:

| Field | Value |
|-------|-------|
| `name` | `"SigilNFT"` |
| `version` | `"1"` |
| `chainId` | `8453` (Base mainnet) |
| `verifyingContract` | the deployed `SigilNFT` address |

Types:

```
Mint(address minter, bytes32 sigilId, string tokenURI, uint256 version, uint256 deadline)
Rework(address holder, uint256 tokenId, string tokenURI, uint256 version, uint256 deadline)
```

`sigilId` is any 32-byte identifier the backend chooses for a sigil, for example
`keccak256(toUtf8Bytes(sigilDatabaseId))`. Pick one scheme and never change it: each `sigilId` can
be minted once.

## 3. Signing (viem example)

```ts
import { privateKeyToAccount } from "viem/accounts";

const signer = privateKeyToAccount(process.env.SIGIL_SIGNER_KEY as `0x${string}`);

const domain = {
  name: "SigilNFT",
  version: "1",
  chainId: 8453,
  verifyingContract: SIGIL_NFT_ADDRESS,
} as const;

// Voucher for the first mint of a sigil.
const mintSignature = await signer.signTypedData({
  domain,
  types: {
    Mint: [
      { name: "minter", type: "address" },
      { name: "sigilId", type: "bytes32" },
      { name: "tokenURI", type: "string" },
      { name: "version", type: "uint256" },
      { name: "deadline", type: "uint256" },
    ],
  },
  primaryType: "Mint",
  message: { minter, sigilId, tokenURI, version: 1n, deadline },
});

// Voucher for a later rework by the current holder.
const reworkSignature = await signer.signTypedData({
  domain,
  types: {
    Rework: [
      { name: "holder", type: "address" },
      { name: "tokenId", type: "uint256" },
      { name: "tokenURI", type: "string" },
      { name: "version", type: "uint256" },
      { name: "deadline", type: "uint256" },
    ],
  },
  primaryType: "Rework",
  message: { holder, tokenId, tokenURI, version: nextVersion, deadline },
});
```

Return `{ tokenURI, version, deadline, signature }` to the user's wallet, which then calls
`mint(sigilId, tokenURI, version, deadline, signature)` or
`rework(tokenId, tokenURI, version, deadline, signature)`. The user pays the gas.

## 4. What the backend must check before signing

The contract trusts the signature completely, so these checks are the real access control.

**Mint**
- The requesting wallet is the one the user authenticated with, and it is the `minter` you sign.
- The user owns the sigil and has paid whatever your app charges for it.
- `sigilId` has no token yet (`tokenOfSigil(sigilId) == 0`), or the transaction will revert.
- Minting is open for this user. Withholding vouchers is how you run an allowlist window.
- The collection is not sold out (`totalSupply() < MAX_SUPPLY`).

**Rework**
- Read the holder on-chain: `ownerOf(tokenId)` must equal the requesting wallet. Do not rely on your
  own database once a sigil has been minted, because the token can be traded on a marketplace. A
  buyer who connects their wallet should be able to rework; the previous holder should not.
- The user has paid whatever your app charges for reworking.
- Use `version` strictly greater than `tokenVersion(tokenId)`. Reading it on-chain avoids collisions
  if a user requests two reworks before the first lands.
- Pin the new image and JSON first, and sign the resulting `ipfs://` URI.

**Both**
- Use a short `deadline` (minutes to an hour). Vouchers cannot be revoked except by expiry or by
  rotating the signer with `setSigner`.
- Sign exactly the bytes you pinned. The voucher is bound to the exact `tokenURI` string.

## 5. Refreshing marketplaces

`rework` emits ERC-4906 `MetadataUpdate(tokenId)`, which marketplaces that support it use to
re-fetch the token. Refresh timing varies by marketplace, and users can usually force a refresh from
the token page. Supporting a lag of minutes in your UI is reasonable.

## 6. Key handling

- The signer key can authorize minting into the remaining supply. Keep it in a secrets manager or
  KMS, separate from the deployer key, and never in client code.
- Rotate with `setSigner(newAddress)` from the owner account if it leaks. Outstanding vouchers from
  the old key stop working immediately.
- A leaked signer key cannot change tokens it does not hold, because a rework must be submitted by
  the token's current holder.
