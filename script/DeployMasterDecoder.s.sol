// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Script, console} from "@forge-std/Script.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {BlockHelixMasterDecoderAndSanitizer} from
    "src/base/DecodersAndSanitizers/BlockHelixMasterDecoderAndSanitizer.sol";

// Deploys the ONE shared master decoder via CREATE3 (stable name `bh-master-decoder-v1`).
// Run once, with the key that owns the Deployer:
//
//   source .env && forge script script/DeployMasterDecoder.s.sol \
//     --rpc-url $BASE_RPC_URL --account bh-aws --sender $DEPLOYER --broadcast --verify
//
// Then set MASTER_DECODER_ADDRESS (box + Amplify env) to the logged address, and every
// risk-profile deploy pins it.
contract DeployMasterDecoder is Script {
    string constant NAME = "bh-master-decoder-v1";

    function run() external {
        Deployer deployer = Deployer(vm.envAddress("DEPLOYER_CONTRACT_ADDRESS"));

        // Zero-arg constructor: no constructorArgs to append.
        bytes memory creationCode = type(BlockHelixMasterDecoderAndSanitizer).creationCode;

        console.log("predicted address:", deployer.getAddress(NAME));
        vm.startBroadcast();
        address decoder = deployer.deployContract(NAME, creationCode, "", 0);
        vm.stopBroadcast();
        console.log("master decoder deployed:", decoder);
    }
}
