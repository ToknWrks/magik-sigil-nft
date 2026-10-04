// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {SigilNFT} from "../src/SigilNFT.sol";

/// @notice Deploys the SigilNFT collection ("Illuminati.Earth Magik Sigil" / "SIGILNFT"), 2300 max supply,
/// 10% EIP-2981 royalty to SIGIL_TREASURY_ADDRESS, mint/rework vouchers signed by
/// SIGIL_SIGNER_ADDRESS (rotatable later by the deployer via setSigner). One-time, real mainnet
/// deploy -- rehearse on an Anvil fork of Base mainnet first.
///
/// Usage: set SIGIL_TREASURY_ADDRESS and SIGIL_SIGNER_ADDRESS in .env, then:
///   forge script script/DeploySigilNFT.s.sol --rpc-url "$BASE_RPC_URL" --broadcast --verify -vv
contract DeploySigilNFTScript is Script {
    string constant NAME = "Illuminati.Earth Magik Sigil";
    string constant SYMBOL = "SIGILNFT"; // not "SIGIL": that ticker is reserved for the Illuminati Magik token

    function run() external returns (SigilNFT nft) {
        address treasury = vm.envAddress("SIGIL_TREASURY_ADDRESS");
        address signer = vm.envAddress("SIGIL_SIGNER_ADDRESS");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        nft = new SigilNFT(NAME, SYMBOL, treasury, signer);
        vm.stopBroadcast();

        console2.log("SigilNFT:", address(nft));
        console2.log("Treasury (royalty receiver):", treasury);
        console2.log("Voucher signer:", signer);
    }
}
