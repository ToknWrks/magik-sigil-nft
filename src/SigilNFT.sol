// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Permissionless mint for the Illuminati Magik Sigil collection: anyone can turn a
/// tokenURI into a token, capped at 2300 ever, no mint price (gas only). Every secondary sale on
/// a marketplace that honors EIP-2981 (OpenSea does) pays a fixed 10% royalty to `treasury` --
/// this address is set once at deploy and is NOT the minter; minters never receive royalties on
/// their own or anyone else's resales.
///
/// The contract does not verify what a `tokenURI` passed to `mint` points at. Any binding between
/// a token and an off-chain asset must be enforced by the minting front end (for example, by only
/// issuing metadata URLs for assets the caller owns), not by this contract. Anyone calling `mint`
/// directly can mint arbitrary metadata pointing anywhere; this is an accepted, documented
/// tradeoff of a permissionless mint, not a bug.
///
/// WARNING: unaudited. Intended for a real Base mainnet deploy, so give it a careful manual
/// read-through (it is a small, standard-OpenZeppelin-based surface) before broadcasting.
contract SigilNFT is ERC721, ERC721URIStorage, ERC2981, Ownable {
    uint256 public constant MAX_SUPPLY = 2300;

    uint256 private _nextTokenId = 1;

    error SoldOut();

    constructor(string memory name_, string memory symbol_, address treasury)
        ERC721(name_, symbol_)
        Ownable(msg.sender)
    {
        _setDefaultRoyalty(treasury, 1000); // 1000 bps = 10%
    }

    /// @notice Mint the next token to the caller with the given metadata URI. Permissionless --
    /// no payment, no allowlist. Reverts once `totalSupply() == MAX_SUPPLY`.
    function mint(string calldata tokenURI_) external returns (uint256 tokenId) {
        if (_nextTokenId > MAX_SUPPLY) revert SoldOut();
        tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, tokenURI_);
    }

    function totalSupply() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
