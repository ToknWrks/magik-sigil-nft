# magik-sigil-nft

`SigilNFT` is an ERC-721 collection, **"Illuminati Magik Sigil" (`SIGIL`)**: one token per sigil,
2300 max supply, free to mint (gas only), a fixed 10% [EIP-2981](https://eips.ethereum.org/EIPS/eip-2981)
royalty on secondary sales, and metadata the current holder can rework at any time. Minting and
reworking are authorized by [EIP-712](https://eips.ethereum.org/EIPS/eip-712) vouchers signed by a
backend `signer`.

> **Status: unaudited.** This contract is intended for a real **Base mainnet** deploy. It is a small
> surface built on standard OpenZeppelin v5 components (`ERC721URIStorage`, `ERC2981`, `Ownable`,
> `EIP712`, `ECDSA`), but it has not been independently audited. Read it yourself before relying on it.

## How it works

- **Vouchers:** the contract does not know what a sigil is or how users pay for one. An off-chain
  backend (the `signer`) decides who may mint or rework and signs a typed message saying so. The
  contract only verifies the signature and enforces the rules below.
- **Mint:** `mint(bytes32 sigilId, string tokenURI_, uint256 version, uint256 deadline, bytes signature)`.
  The voucher names the caller, `sigilId`, `tokenURI_`, `version` (at least 1) and `deadline`. It
  mints the next token ID (starting at 1) to the caller. Each `sigilId` can be minted once
  (`tokenOfSigil`), so supply is bounded by sigils, not by call count.
- **Rework:** `rework(uint256 tokenId, string tokenURI_, uint256 version, uint256 deadline, bytes signature)`.
  Only the **current holder** may call, with a voucher naming that holder. It replaces the token's URI,
  can be repeated any number of times, never consumes a supply slot, and emits ERC-4906
  `MetadataUpdate` so marketplaces refresh. A buyer on a secondary market becomes the holder and can
  rework with their own voucher; the previous holder can no longer.
- **Replay protection:** a voucher is bound to one caller (and, for rework, one token), is valid only for
  this contract and chain (EIP-712 domain), and expires at `deadline`. Each token stores the last applied
  `version`; a rework voucher must carry a strictly higher one.
- **Supply cap:** `MAX_SUPPLY = 2300`. Once 2300 tokens exist, `mint` reverts with `SoldOut()`.
  `totalSupply()` returns the number minted so far. Tokens cannot be burned.
- **Allowlist windows:** the contract has no on-chain window. The backend controls when minting is
  open by when (and to whom) it issues vouchers.
- **Royalty:** the constructor calls `_setDefaultRoyalty(treasury, 1000)` (1000 bps = 10%). It applies to
  every token and there is no setter afterward. The receiver is the `treasury` constructor argument,
  never the minter. Marketplaces that honor EIP-2981 pay 10% of each resale to that address.
- **Owner:** the deployer is `Ownable` owner. The only owner function is `setSigner(address)`, which
  rotates the voucher signer; outstanding vouchers from the old signer stop working.

## Threat model and known limitations

- **The `signer` is a trust point.** It decides what metadata is valid and when minting opens. A
  compromised signer key can mint junk into the remaining supply, but it **cannot change a token it
  does not hold**: a rework must be submitted by that token's holder. Rotate with `setSigner`.
  `owner` has no other power over tokens, royalties or supply.
- **Holders can rework freely, so metadata can change after listing.** A seller can change a token's art
  between listing and sale. Buyers should check metadata at purchase time. There is no freeze or lock.
- **Slots are first-come-first-served among holders of valid vouchers.** The contract cannot stop the
  backend from issuing vouchers for all 2300 sigils to one wallet.
- **Voucher validity is not revocable** except by expiry or by rotating the signer, so use short
  deadlines.
- **The contract cannot verify what a `tokenURI` points to**, only that the signer approved that exact
  string. Off-chain content behind the URI can change unless it is content-addressed (IPFS).
- **Royalties are only honored by marketplaces that respect EIP-2981.** It is not enforced at the
  token-transfer level.
- **Name and symbol are constructor arguments**, set in `script/DeploySigilNFT.s.sol`, and are
  immutable once deployed. Check their exact casing before broadcasting.
- **Unaudited.**

## Tests

`test/SigilNFT.t.sol` (27 tests) covers:

- mint: sets owner, URI, supply and sigil mapping; emits `Transfer` from zero; sequential IDs; reverts
  on an invalid signature, a voucher used by another caller, a tampered URI, an expired voucher,
  version 0, and a sigil that is already minted; sells out at exactly `MAX_SUPPLY`
- rework: holder updates URI and emits `MetadataUpdate`; repeatable; new owner can rework after a
  transfer; previous owner cannot; a voucher cannot be used by a different caller; non-holders,
  replays, older versions, bad signatures, expired vouchers and nonexistent tokens all revert
- signer: owner rotation invalidates old vouchers; non-owner and zero address revert
- royalty returns exactly 10% to the treasury; `supportsInterface` reports ERC-721, ERC-2981, ERC-4906
- a reentrant `onERC721Received` cannot redeem the same voucher twice

## Build, test, deploy

Requires [Foundry](https://book.getfoundry.sh/). Clone with submodules:

```bash
git clone --recurse-submodules <repo-url>
cd magik-sigil-nft
forge build
forge test
```

Dependencies (git submodules in `lib/`): `forge-std` v1.16.2 and `openzeppelin-contracts` v5.5.0.
`foundry.toml` sets `bytecode_hash = "none"`.

### Deploy (Base mainnet)

```bash
cp .env.example .env   # fill in PRIVATE_KEY (real, funded), BASE_RPC_URL, BASESCAN_API_KEY, SIGIL_TREASURY_ADDRESS, SIGIL_SIGNER_ADDRESS
set -a && source .env && set +a

# Rehearse on a fork first:
anvil --fork-url "$BASE_RPC_URL"

# Then broadcast for real:
forge script script/DeploySigilNFT.s.sol --rpc-url "$BASE_RPC_URL" --broadcast --verify -vv
```

`SIGIL_TREASURY_ADDRESS` is the royalty receiver and is fixed at deploy. `SIGIL_SIGNER_ADDRESS` is the
address whose signatures authorize mints and reworks; the deployer can rotate it later with
`setSigner`. Never commit `.env`.

## Layout

| Path | Contents |
|------|----------|
| `src/SigilNFT.sol` | The contract. |
| `test/SigilNFT.t.sol` | Foundry unit tests. |
| `script/DeploySigilNFT.s.sol` | Mainnet deploy script (name, symbol, treasury, signer). |
| `lib/` | `forge-std`, `openzeppelin-contracts` (submodules). |

## License

Source files carry `SPDX-License-Identifier: MIT`.
