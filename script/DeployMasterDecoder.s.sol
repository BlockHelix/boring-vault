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
    // Uniswap V3 NonFungiblePositionManager on Base. Unused by the swap sanitizer (exactInput),
    // but the UniswapV3 sanitizer constructor requires it. boringVault is unused -> address(0).
    address constant BASE_UNIV3_NFPM = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    string constant NAME = "bh-master-decoder-v1";

    function run() external {
        Deployer deployer = Deployer(vm.envAddress("DEPLOYER_CONTRACT_ADDRESS"));

        bytes memory creationCode = type(BlockHelixMasterDecoderAndSanitizer).creationCode;
        bytes memory args = abi.encode(address(0), BASE_UNIV3_NFPM);

        console.log("predicted address:", deployer.getAddress(NAME));
        vm.startBroadcast();
        address decoder = deployer.deployContract(NAME, creationCode, args, 0);
        vm.stopBroadcast();
        console.log("master decoder deployed:", decoder);
    }
}
