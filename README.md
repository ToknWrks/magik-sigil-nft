# magik-sigil-nft

`SigilNFT` is an ERC-721 collection, **"Illuminati Magik Sigil" (`SIGIL`)**: 2300 max supply,
permissionless free mint (gas only), and a fixed 10% [EIP-2981](https://eips.ethereum.org/EIPS/eip-2981)
royalty on secondary sales. Each token carries its own metadata URI.

> **Status: unaudited.** This contract is intended for a real **Base mainnet** deploy. It is a small
> surface built on standard OpenZeppelin v5 components (`ERC721URIStorage`, `ERC2981`, `Ownable`),
> but it has not been independently audited. Read it yourself before relying on it.

## How it works

- **Mint:** `mint(string tokenURI_)` is `external`, callable by anyone, not `payable`. It mints the
  next token ID (starting at 1) to the caller and stores `tokenURI_`. There is no price, allowlist or
  per-wallet limit.
- **Supply cap:** `MAX_SUPPLY = 2300`, enforced on-chain. Once 2300 tokens exist, `mint` reverts with
  `SoldOut()`. `totalSupply()` returns the number minted so far.
- **Royalty:** the constructor calls `_setDefaultRoyalty(treasury, 1000)` (1000 bps = 10%). It applies to
  every token and there is no setter afterward. The receiver is the `treasury` constructor argument,
  never the minter. Marketplaces that honor EIP-2981 pay 10% of each resale to that address.
- **Metadata:** per-token URIs via `ERC721URIStorage`, set once at mint. There is no function to
  change a token's URI afterward, so metadata is immutable at the contract level.
- **Ownership:** `Ownable` is inherited with the deployer as owner, but the contract has no
  owner-only functions of its own.

## Design decisions

- **Permissionless mint on purpose.** Gating `mint` would defeat "anyone mints their own token".
- **Per-token URIs, not a shared base URI**, because each token is meant to represent a specific
  piece of user-generated content rather than interchangeable art.
- **Deliberately minimal:** no pause, no price, no allowlist, no per-wallet cap, no royalty setter.

## Threat model and known limitations

- **The contract cannot verify what a `tokenURI` points to.** Anyone calling `mint` directly can use
  one of the 2300 slots with arbitrary metadata. This is an accepted tradeoff of a permissionless mint
  with custom per-token metadata. Any binding between a URI and "legitimate" content has to be
  enforced off-chain (for example by the front-end that hands out URIs, or by marketplace
  curation), not by this contract.
- **Slots are first-come-first-served.** Anyone, including bots, can mint all 2300 tokens.
- **Immutable metadata.** If the content a URI refers to changes later, the token's on-chain URI
  does not. Applications must handle that themselves.
- **Royalties are only honored by marketplaces that respect EIP-2981.** It is not enforced at the
  token-transfer level.
- **Name and symbol are constructor arguments**, set in `script/DeploySigilNFT.s.sol`, and are
  immutable once deployed. Check their exact casing before broadcasting.
- **Unaudited.**

## Tests

`test/SigilNFT.t.sol` (7 tests) covers:

- mint increments `totalSupply` and sets the exact `tokenURI` for `msg.sender`
- mint emits `Transfer(address(0), minter, tokenId)`
- a non-owner caller can mint
- distinct callers get sequential, distinct token IDs
- minting exactly `MAX_SUPPLY` tokens succeeds, the next mint reverts with `SoldOut`
- `royaltyInfo()` returns exactly 10% to the constructor's treasury
- `supportsInterface` reports `IERC721` and `IERC2981`

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
cp .env.example .env   # fill in PRIVATE_KEY (real, funded), BASE_RPC_URL, BASESCAN_API_KEY, SIGIL_TREASURY_ADDRESS
set -a && source .env && set +a

# Rehearse on a fork first:
anvil --fork-url "$BASE_RPC_URL"

# Then broadcast for real:
forge script script/DeploySigilNFT.s.sol --rpc-url "$BASE_RPC_URL" --broadcast --verify -vv
```

`SIGIL_TREASURY_ADDRESS` is the royalty receiver. It is fixed at deploy. Never commit `.env`.

## Layout

| Path | Contents |
|------|----------|
| `src/SigilNFT.sol` | The contract. |
| `test/SigilNFT.t.sol` | Foundry unit tests. |
| `script/DeploySigilNFT.s.sol` | Mainnet deploy script (name, symbol, treasury). |
| `lib/` | `forge-std`, `openzeppelin-contracts` (submodules). |

## License

Source files carry `SPDX-License-Identifier: MIT`.
