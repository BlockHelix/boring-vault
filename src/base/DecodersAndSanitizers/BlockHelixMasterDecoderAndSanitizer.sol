// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";
import {AaveV3DecoderAndSanitizer} from "src/base/DecodersAndSanitizers/Protocols/AaveV3DecoderAndSanitizer.sol";
import {UniswapV3DecoderAndSanitizer} from "src/base/DecodersAndSanitizers/Protocols/UniswapV3DecoderAndSanitizer.sol";
import {BalancerV2DecoderAndSanitizer} from "src/base/DecodersAndSanitizers/Protocols/BalancerV2DecoderAndSanitizer.sol";

/**
 * @title BlockHelixMasterDecoderAndSanitizer
 * @notice One shared decoder-and-sanitizer for every BlockHelix vault: Aave v3 + Uniswap v3
 *         + Balancer v2 (flashloans). Deployed ONCE via CREATE3 (name `bh-master-decoder-v1`)
 *         and referenced by every vault's risk-profile manage root — the strategist supplies
 *         this address in each `manage` call.
 *
 *         The sanitizers are pure: they extract addresses from calldata, and per-vault pinning
 *         (onBehalfOf / recipient == the vault) lives in the merkle LEAF, not here. So the
 *         `boringVault` immutable is unused and a single shared instance is safe. These three
 *         sanitizers share no function names, so no collision overrides are required.
 */
contract BlockHelixMasterDecoderAndSanitizer is
    AaveV3DecoderAndSanitizer,
    UniswapV3DecoderAndSanitizer,
    BalancerV2DecoderAndSanitizer
{
    constructor(address _boringVault, address _uniswapV3NonFungiblePositionManager)
        BaseDecoderAndSanitizer(_boringVault)
        UniswapV3DecoderAndSanitizer(_uniswapV3NonFungiblePositionManager)
    {}
}
