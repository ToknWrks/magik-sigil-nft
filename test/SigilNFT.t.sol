// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {SigilNFT} from "../src/SigilNFT.sol";

contract SigilNFTTest is Test {
    SigilNFT nft;

    address treasury = makeAddr("treasury");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address signerAddr;
    uint256 signerKey;

    bytes32 constant SIGIL_A = keccak256("sigil-a");
    bytes32 constant SIGIL_B = keccak256("sigil-b");
    uint256 constant DEADLINE = 1 days;

    function setUp() public {
        (signerAddr, signerKey) = makeAddrAndKey("signer");
        nft = new SigilNFT("Illuminati Magik Sigil", "SIGIL", treasury, signerAddr);
    }

    // ---------------------------------------------------------------- helpers

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("SigilNFT"),
                keccak256("1"),
                block.chainid,
                address(nft)
            )
        );
    }

    function _sign(uint256 key, bytes32 structHash) internal view returns (bytes memory) {
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _mintSig(uint256 key, address minter, bytes32 sigilId, string memory uri, uint256 version, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        return _sign(
            key,
            keccak256(abi.encode(nft.MINT_TYPEHASH(), minter, sigilId, keccak256(bytes(uri)), version, deadline))
        );
    }

    function _reworkSig(
        uint256 key,
        address holder,
        uint256 tokenId,
        string memory uri,
        uint256 version,
        uint256 deadline
    ) internal view returns (bytes memory) {
        return _sign(
            key,
            keccak256(abi.encode(nft.REWORK_TYPEHASH(), holder, tokenId, keccak256(bytes(uri)), version, deadline))
        );
    }

    function _mint(address who, bytes32 sigilId, string memory uri) internal returns (uint256) {
        bytes memory sig = _mintSig(signerKey, who, sigilId, uri, 1, DEADLINE);
        vm.prank(who);
        return nft.mint(sigilId, uri, 1, DEADLINE, sig);
    }

    function _rework(address who, uint256 tokenId, string memory uri, uint256 version) internal {
        bytes memory sig = _reworkSig(signerKey, who, tokenId, uri, version, DEADLINE);
        vm.prank(who);
        nft.rework(tokenId, uri, version, DEADLINE, sig);
    }

    // ------------------------------------------------------------------- mint

    function test_mint_setsOwnerUriSupplyAndSigilMapping() public {
        uint256 tokenId = _mint(alice, SIGIL_A, "ipfs://sigil-a");

        assertEq(tokenId, 1);
        assertEq(nft.totalSupply(), 1);
        assertEq(nft.ownerOf(tokenId), alice);
        assertEq(nft.tokenURI(tokenId), "ipfs://sigil-a");
        assertEq(nft.tokenOfSigil(SIGIL_A), 1);
        assertEq(nft.tokenVersion(1), 1);
    }

    function test_mint_emitsTransferFromZeroAddress() public {
        bytes memory sig = _mintSig(signerKey, alice, SIGIL_A, "ipfs://sigil-a", 1, DEADLINE);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(address(0), alice, 1);
        nft.mint(SIGIL_A, "ipfs://sigil-a", 1, DEADLINE, sig);
    }

    function test_mint_distinctSigilsGetIncrementingIds() public {
        assertEq(_mint(alice, SIGIL_A, "ipfs://a"), 1);
        assertEq(_mint(bob, SIGIL_B, "ipfs://b"), 2);
        assertEq(nft.totalSupply(), 2);
    }

    function test_mint_revertsWithoutValidSignature() public {
        (, uint256 otherKey) = makeAddrAndKey("not-the-signer");
        bytes memory sig = _mintSig(otherKey, alice, SIGIL_A, "ipfs://a", 1, DEADLINE);
        vm.prank(alice);
        vm.expectRevert(SigilNFT.InvalidSigner.selector);
        nft.mint(SIGIL_A, "ipfs://a", 1, DEADLINE, sig);
    }

    function test_mint_voucherBoundToCaller() public {
        bytes memory sig = _mintSig(signerKey, alice, SIGIL_A, "ipfs://a", 1, DEADLINE);
        vm.prank(bob); // bob replays alice's voucher
        vm.expectRevert(SigilNFT.InvalidSigner.selector);
        nft.mint(SIGIL_A, "ipfs://a", 1, DEADLINE, sig);
    }

    function test_mint_voucherBoundToUri() public {
        bytes memory sig = _mintSig(signerKey, alice, SIGIL_A, "ipfs://a", 1, DEADLINE);
        vm.prank(alice);
        vm.expectRevert(SigilNFT.InvalidSigner.selector);
        nft.mint(SIGIL_A, "ipfs://tampered", 1, DEADLINE, sig);
    }

    function test_mint_revertsWhenExpired() public {
        bytes memory sig = _mintSig(signerKey, alice, SIGIL_A, "ipfs://a", 1, DEADLINE);
        vm.warp(DEADLINE + 1);
        vm.prank(alice);
        vm.expectRevert(SigilNFT.VoucherExpired.selector);
        nft.mint(SIGIL_A, "ipfs://a", 1, DEADLINE, sig);
    }

    function test_mint_sameSigilCannotMintTwice() public {
        _mint(alice, SIGIL_A, "ipfs://a");
        bytes memory sig = _mintSig(signerKey, alice, SIGIL_A, "ipfs://a2", 1, DEADLINE);
        vm.prank(alice);
        vm.expectRevert(SigilNFT.SigilAlreadyMinted.selector);
        nft.mint(SIGIL_A, "ipfs://a2", 1, DEADLINE, sig);
    }

    function test_mint_revertsOnVersionZero() public {
        bytes memory sig = _mintSig(signerKey, alice, SIGIL_A, "ipfs://a", 0, DEADLINE);
        vm.prank(alice);
        vm.expectRevert(SigilNFT.StaleVersion.selector);
        nft.mint(SIGIL_A, "ipfs://a", 0, DEADLINE, sig);
    }

    function test_mint_revertsOnceSoldOut() public {
        uint256 maxSupply = nft.MAX_SUPPLY();
        for (uint256 i = 0; i < maxSupply; i++) {
            _mint(alice, bytes32(i + 1000), "ipfs://sigil");
        }
        assertEq(nft.totalSupply(), maxSupply);

        bytes memory sig = _mintSig(signerKey, alice, SIGIL_A, "ipfs://one-too-many", 1, DEADLINE);
        vm.prank(alice);
        vm.expectRevert(SigilNFT.SoldOut.selector);
        nft.mint(SIGIL_A, "ipfs://one-too-many", 1, DEADLINE, sig);
    }

    // ----------------------------------------------------------------- rework

    function test_rework_holderUpdatesUriAndEmitsMetadataUpdate() public {
        uint256 tokenId = _mint(alice, SIGIL_A, "ipfs://v1");

        bytes memory sig = _reworkSig(signerKey, alice, tokenId, "ipfs://v2", 2, DEADLINE);
        vm.prank(alice);
        vm.expectEmit(false, false, false, true);
        emit IERC4906.MetadataUpdate(tokenId);
        nft.rework(tokenId, "ipfs://v2", 2, DEADLINE, sig);

        assertEq(nft.tokenURI(tokenId), "ipfs://v2");
        assertEq(nft.tokenVersion(tokenId), 2);
        assertEq(nft.totalSupply(), 1); // rework never consumes a supply slot
    }

    function test_rework_canBeRepeatedFreely() public {
        uint256 tokenId = _mint(alice, SIGIL_A, "ipfs://v1");
        for (uint256 v = 2; v < 12; v++) {
            _rework(alice, tokenId, string.concat("ipfs://v", vm.toString(v)), v);
        }
        assertEq(nft.tokenURI(tokenId), "ipfs://v11");
    }

    function test_rework_newOwnerAfterTransferCanRework() public {
        uint256 tokenId = _mint(alice, SIGIL_A, "ipfs://v1");
        vm.prank(alice);
        nft.transferFrom(alice, bob, tokenId);

        _rework(bob, tokenId, "ipfs://bob-v2", 2);
        assertEq(nft.tokenURI(tokenId), "ipfs://bob-v2");
    }

    function test_rework_previousOwnerCannotReworkAfterTransfer() public {
        uint256 tokenId = _mint(alice, SIGIL_A, "ipfs://v1");
        bytes memory sig = _reworkSig(signerKey, alice, tokenId, "ipfs://v2", 2, DEADLINE);
        vm.prank(alice);
        nft.transferFrom(alice, bob, tokenId);

        vm.prank(alice); // alice still holds a valid voucher
        vm.expectRevert(SigilNFT.NotTokenHolder.selector);
        nft.rework(tokenId, "ipfs://v2", 2, DEADLINE, sig);
    }

    function test_rework_voucherCannotBeUsedByNewOwner() public {
        uint256 tokenId = _mint(alice, SIGIL_A, "ipfs://v1");
        bytes memory sig = _reworkSig(signerKey, alice, tokenId, "ipfs://v2", 2, DEADLINE);
        vm.prank(alice);
        nft.transferFrom(alice, bob, tokenId);

        vm.prank(bob); // voucher names alice, not bob
        vm.expectRevert(SigilNFT.InvalidSigner.selector);
        nft.rework(tokenId, "ipfs://v2", 2, DEADLINE, sig);
    }

    function test_rework_revertsForNonHolder() public {
        uint256 tokenId = _mint(alice, SIGIL_A, "ipfs://v1");
        bytes memory sig = _reworkSig(signerKey, bob, tokenId, "ipfs://evil", 2, DEADLINE);
        vm.prank(bob);
        vm.expectRevert(SigilNFT.NotTokenHolder.selector);
        nft.rework(tokenId, "ipfs://evil", 2, DEADLINE, sig);
    }

    function test_rework_revertsOnReplayedOrOlderVersion() public {
        uint256 tokenId = _mint(alice, SIGIL_A, "ipfs://v1");
        bytes memory sig2 = _reworkSig(signerKey, alice, tokenId, "ipfs://v2", 2, DEADLINE);
        vm.startPrank(alice);
        nft.rework(tokenId, "ipfs://v2", 2, DEADLINE, sig2);

        vm.expectRevert(SigilNFT.StaleVersion.selector); // replay
        nft.rework(tokenId, "ipfs://v2", 2, DEADLINE, sig2);
        vm.stopPrank();

        bytes memory sigOld = _reworkSig(signerKey, alice, tokenId, "ipfs://old", 1, DEADLINE);
        vm.prank(alice);
        vm.expectRevert(SigilNFT.StaleVersion.selector); // older than applied
        nft.rework(tokenId, "ipfs://old", 1, DEADLINE, sigOld);
    }

    function test_rework_revertsWithoutValidSignature() public {
        uint256 tokenId = _mint(alice, SIGIL_A, "ipfs://v1");
        (, uint256 otherKey) = makeAddrAndKey("not-the-signer");
        bytes memory sig = _reworkSig(otherKey, alice, tokenId, "ipfs://v2", 2, DEADLINE);
        vm.prank(alice);
        vm.expectRevert(SigilNFT.InvalidSigner.selector);
        nft.rework(tokenId, "ipfs://v2", 2, DEADLINE, sig);
    }

    function test_rework_revertsWhenExpired() public {
        uint256 tokenId = _mint(alice, SIGIL_A, "ipfs://v1");
        bytes memory sig = _reworkSig(signerKey, alice, tokenId, "ipfs://v2", 2, DEADLINE);
        vm.warp(DEADLINE + 1);
        vm.prank(alice);
        vm.expectRevert(SigilNFT.VoucherExpired.selector);
        nft.rework(tokenId, "ipfs://v2", 2, DEADLINE, sig);
    }

    function test_rework_revertsForNonexistentToken() public {
        bytes memory sig = _reworkSig(signerKey, alice, 99, "ipfs://x", 2, DEADLINE);
        vm.prank(alice);
        vm.expectRevert(SigilNFT.NotTokenHolder.selector);
        nft.rework(99, "ipfs://x", 2, DEADLINE, sig);
    }

    // ----------------------------------------------------------------- signer

    function test_setSigner_ownerCanRotateAndOldVouchersStop() public {
        (address newSigner, uint256 newKey) = makeAddrAndKey("new-signer");
        bytes memory oldSig = _mintSig(signerKey, alice, SIGIL_A, "ipfs://a", 1, DEADLINE);

        nft.setSigner(newSigner);
        assertEq(nft.signer(), newSigner);

        vm.prank(alice);
        vm.expectRevert(SigilNFT.InvalidSigner.selector);
        nft.mint(SIGIL_A, "ipfs://a", 1, DEADLINE, oldSig);

        bytes memory newSig = _mintSig(newKey, alice, SIGIL_A, "ipfs://a", 1, DEADLINE);
        vm.prank(alice);
        nft.mint(SIGIL_A, "ipfs://a", 1, DEADLINE, newSig);
        assertEq(nft.ownerOf(1), alice);
    }

    function test_setSigner_revertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        nft.setSigner(alice);
    }

    function test_setSigner_revertsOnZeroAddress() public {
        vm.expectRevert(SigilNFT.ZeroAddress.selector);
        nft.setSigner(address(0));
    }

    function test_constructor_revertsOnZeroSigner() public {
        vm.expectRevert(SigilNFT.ZeroAddress.selector);
        new SigilNFT("n", "s", treasury, address(0));
    }

    // ------------------------------------------------------------ royalty etc.

    function test_royaltyInfo_returns10PercentToTreasury() public view {
        (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(1, 1_000e18);
        assertEq(receiver, treasury);
        assertEq(royaltyAmount, 100e18); // 10% of 1_000e18
    }

    function test_supportsInterface_erc721Erc2981Erc4906() public view {
        assertTrue(nft.supportsInterface(type(IERC721).interfaceId));
        assertTrue(nft.supportsInterface(type(IERC2981).interfaceId));
        assertTrue(nft.supportsInterface(bytes4(0x49064906))); // ERC-4906
    }

    // --------------------------------------------------------------- reentrancy

    function test_mint_reentrantReceiverCannotMintSameSigilTwice() public {
        ReentrantMinter attacker = new ReentrantMinter(nft);
        bytes memory sig = _mintSig(signerKey, address(attacker), SIGIL_A, "ipfs://a", 1, DEADLINE);
        attacker.arm(SIGIL_A, "ipfs://a", 1, DEADLINE, sig);

        vm.prank(address(attacker));
        nft.mint(SIGIL_A, "ipfs://a", 1, DEADLINE, sig);

        assertEq(nft.totalSupply(), 1);
        assertTrue(attacker.reenterReverted());
    }
}

/// @dev On receiving its token, tries to redeem the same voucher again.
contract ReentrantMinter is IERC721Receiver {
    SigilNFT immutable nft;
    bytes32 sigilId;
    string uri;
    uint256 version;
    uint256 deadline;
    bytes signature;
    bool public reenterReverted;

    constructor(SigilNFT nft_) {
        nft = nft_;
    }

    function arm(bytes32 sigilId_, string memory uri_, uint256 version_, uint256 deadline_, bytes memory sig) external {
        sigilId = sigilId_;
        uri = uri_;
        version = version_;
        deadline = deadline_;
        signature = sig;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        try nft.mint(sigilId, uri, version, deadline, signature) {
            reenterReverted = false;
        } catch {
            reenterReverted = true;
        }
        return IERC721Receiver.onERC721Received.selector;
    }
}
