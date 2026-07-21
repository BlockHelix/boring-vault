// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";
import {AaveV3DecoderAndSanitizer} from "src/base/DecodersAndSanitizers/Protocols/AaveV3DecoderAndSanitizer.sol";
import {UniswapV3Router02DecoderAndSanitizer} from "src/base/DecodersAndSanitizers/Protocols/UniswapV3Router02DecoderAndSanitizer.sol";
import {BalancerV2DecoderAndSanitizer} from "src/base/DecodersAndSanitizers/Protocols/BalancerV2DecoderAndSanitizer.sol";

/**
 * @title BlockHelixMasterDecoderAndSanitizer
 * @notice One shared decoder-and-sanitizer for every BlockHelix vault: Aave v3 + Uniswap v3
 *         + Balancer v2 (flashloans). Deployed ONCE via CREATE3 (name `bh-master-decoder-v1`)
 *         and referenced by every vault's risk-profile manage root — the strategist supplies
 *         this address in each `manage` call.
 *
 *         Vault-agnostic singleton: the sanitizers are pure (per-vault pinning lives in the
 *         merkle LEAF, not here), so the `boringVault` immutable is unused and fixed to
 *         address(0). No external constructor args. These three sanitizers share no function
 *         names, so no collision overrides are required.
 */
contract BlockHelixMasterDecoderAndSanitizer is
    AaveV3DecoderAndSanitizer,
    UniswapV3Router02DecoderAndSanitizer,
    BalancerV2DecoderAndSanitizer
{
    // Swap-only Uniswap sanitizer (SwapRouter02) + Aave v3 + Balancer v2 flashloans. All pure;
    // per-vault pinning lives in the merkle leaf, so the boringVault immutable is address(0).
    constructor() BaseDecoderAndSanitizer(address(0)) {}
}
