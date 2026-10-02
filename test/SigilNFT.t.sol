// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {SigilNFT} from "../src/SigilNFT.sol";

contract SigilNFTTest is Test {
    SigilNFT nft;

    address treasury = makeAddr("treasury");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        nft = new SigilNFT("Illuminati Magik Sigil", "SIGIL", treasury);
    }

    function test_mint_incrementsSupplyAndSetsTokenURI() public {
        vm.prank(alice);
        uint256 tokenId = nft.mint("ipfs://sigil-1");

        assertEq(tokenId, 1);
        assertEq(nft.totalSupply(), 1);
        assertEq(nft.ownerOf(tokenId), alice);
        assertEq(nft.tokenURI(tokenId), "ipfs://sigil-1");
    }

    function test_mint_emitsTransferFromZeroAddress() public {
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(address(0), alice, 1);
        nft.mint("ipfs://sigil-1");
    }

    function test_mint_isPermissionless_anyCallerCanMint() public {
        vm.prank(bob); // not the contract owner
        uint256 tokenId = nft.mint("ipfs://sigil-bob");
        assertEq(nft.ownerOf(tokenId), bob);
    }

    function test_mint_distinctCallersGetDistinctIncrementingIds() public {
        vm.prank(alice);
        uint256 first = nft.mint("ipfs://sigil-1");
        vm.prank(bob);
        uint256 second = nft.mint("ipfs://sigil-2");

        assertEq(first, 1);
        assertEq(second, 2);
        assertEq(nft.totalSupply(), 2);
    }

    function test_mint_revertsOnceSoldOut() public {
        uint256 maxSupply = nft.MAX_SUPPLY();
        for (uint256 i = 0; i < maxSupply; i++) {
            vm.prank(alice);
            nft.mint("ipfs://sigil");
        }
        assertEq(nft.totalSupply(), maxSupply);

        vm.prank(alice);
        vm.expectRevert(SigilNFT.SoldOut.selector);
        nft.mint("ipfs://one-too-many");
    }

    function test_royaltyInfo_returns10PercentToTreasury() public view {
        (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(1, 1_000e18);
        assertEq(receiver, treasury);
        assertEq(royaltyAmount, 100e18); // 10% of 1_000e18
    }

    function test_supportsInterface_erc721AndErc2981() public view {
        assertTrue(nft.supportsInterface(type(IERC721).interfaceId));
        assertTrue(nft.supportsInterface(type(IERC2981).interfaceId));
    }
}
