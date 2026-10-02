// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @notice Illuminati Magik Sigil collection: one token per sigil, capped at 2300 ever, free to
/// mint (gas only). Every secondary sale on a marketplace that honors EIP-2981 (OpenSea does) pays
/// a fixed 10% royalty to `treasury` -- this address is set once at deploy and is NOT the minter.
///
/// Minting and reworking are gated by vouchers: EIP-712 messages signed by `signer` (the
/// collection's backend). The contract itself does not know what a sigil is or how it is paid for;
/// the backend decides when to issue a voucher. What the contract enforces:
///  - a voucher is bound to one caller, so it cannot be redeemed by anyone else;
///  - each `sigilId` maps to at most one token, so supply is bounded by sigils, not by call count;
///  - the current holder of a token may rework its metadata any number of times, with a fresh
///    voucher each time, including a holder who bought the token on a marketplace;
///  - voucher versions only increase per token, so an old voucher cannot be replayed;
///  - vouchers expire at `deadline`.
///
/// Trust assumptions: whoever controls `signer` decides which URIs are valid and when minting
/// opens (it can issue no vouchers, which acts as an allowlist window, or vouchers only to chosen
/// addresses). A compromised signer can mint junk into the remaining supply, but cannot touch
/// tokens it does not hold: a rework needs the holder to submit the transaction. `owner` can
/// rotate `signer`; it has no other power. Because holders can rework freely, a seller can change
/// a token's art between listing and sale; buyers should check metadata at purchase time.
///
/// WARNING: unaudited. Intended for a real Base mainnet deploy, so give it a careful manual
/// read-through (it is a small, standard-OpenZeppelin-based surface) before broadcasting.
contract SigilNFT is ERC721, ERC721URIStorage, ERC2981, Ownable, EIP712 {
    uint256 public constant MAX_SUPPLY = 2300;

    bytes32 public constant MINT_TYPEHASH =
        keccak256("Mint(address minter,bytes32 sigilId,string tokenURI,uint256 version,uint256 deadline)");
    bytes32 public constant REWORK_TYPEHASH =
        keccak256("Rework(address holder,uint256 tokenId,string tokenURI,uint256 version,uint256 deadline)");

    uint256 private _nextTokenId = 1;

    /// @notice Address whose signatures authorize mints and reworks.
    address public signer;

    /// @notice Token minted for a sigil, or 0 if that sigil has not been minted.
    mapping(bytes32 sigilId => uint256 tokenId) public tokenOfSigil;

    /// @notice Version of the voucher last applied to a token. A new voucher must be higher.
    mapping(uint256 tokenId => uint256 version) public tokenVersion;

    error SoldOut();
    error ZeroAddress();
    error VoucherExpired();
    error InvalidSigner();
    error SigilAlreadyMinted();
    error StaleVersion();
    error NotTokenHolder();

    event SignerUpdated(address indexed signer);
    event SigilMinted(bytes32 indexed sigilId, uint256 indexed tokenId, address indexed minter);

    constructor(string memory name_, string memory symbol_, address treasury, address signer_)
        ERC721(name_, symbol_)
        Ownable(msg.sender)
        EIP712("SigilNFT", "1")
    {
        if (signer_ == address(0)) revert ZeroAddress();
        signer = signer_;
        _setDefaultRoyalty(treasury, 1000); // 1000 bps = 10%
        emit SignerUpdated(signer_);
    }

    /// @notice Mint the token for `sigilId` to the caller. Requires a voucher from `signer` naming
    /// this caller, `sigilId`, `tokenURI_` and `version` (must be at least 1). Reverts once
    /// `totalSupply() == MAX_SUPPLY` or if the sigil already has a token.
    function mint(bytes32 sigilId, string calldata tokenURI_, uint256 version, uint256 deadline, bytes calldata signature)
        external
        returns (uint256 tokenId)
    {
        if (block.timestamp > deadline) revert VoucherExpired();
        if (version == 0) revert StaleVersion();
        if (tokenOfSigil[sigilId] != 0) revert SigilAlreadyMinted();
        if (_nextTokenId > MAX_SUPPLY) revert SoldOut();

        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(MINT_TYPEHASH, msg.sender, sigilId, keccak256(bytes(tokenURI_)), version, deadline))
        );
        if (ECDSA.recover(digest, signature) != signer) revert InvalidSigner();

        tokenId = _nextTokenId++;
        // State is written before _safeMint, which calls back into the receiver.
        tokenOfSigil[sigilId] = tokenId;
        tokenVersion[tokenId] = version;
        _setTokenURI(tokenId, tokenURI_);
        emit SigilMinted(sigilId, tokenId, msg.sender);
        _safeMint(msg.sender, tokenId);
    }

    /// @notice Replace the metadata URI of `tokenId`. Only the current holder may call, with a
    /// voucher from `signer` naming that holder, `tokenURI_` and a `version` higher than the last
    /// applied one. Emits ERC-4906 `MetadataUpdate` so marketplaces refresh.
    function rework(
        uint256 tokenId,
        string calldata tokenURI_,
        uint256 version,
        uint256 deadline,
        bytes calldata signature
    ) external {
        if (block.timestamp > deadline) revert VoucherExpired();
        if (_ownerOf(tokenId) != msg.sender) revert NotTokenHolder();
        if (version <= tokenVersion[tokenId]) revert StaleVersion();

        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(REWORK_TYPEHASH, msg.sender, tokenId, keccak256(bytes(tokenURI_)), version, deadline))
        );
        if (ECDSA.recover(digest, signature) != signer) revert InvalidSigner();

        tokenVersion[tokenId] = version;
        _setTokenURI(tokenId, tokenURI_);
    }

    /// @notice Rotate the voucher signer. Outstanding vouchers from the old signer stop working.
    function setSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert ZeroAddress();
        signer = newSigner;
        emit SignerUpdated(newSigner);
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
