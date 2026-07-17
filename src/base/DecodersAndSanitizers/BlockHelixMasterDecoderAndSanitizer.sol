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
 *         Vault-agnostic singleton: the sanitizers are pure (per-vault pinning lives in the
 *         merkle LEAF, not here), so the `boringVault` immutable is unused and fixed to
 *         address(0). No external constructor args. These three sanitizers share no function
 *         names, so no collision overrides are required.
 */
contract BlockHelixMasterDecoderAndSanitizer is
    AaveV3DecoderAndSanitizer,
    UniswapV3DecoderAndSanitizer,
    BalancerV2DecoderAndSanitizer
{
    // Base Uniswap V3 NonFungiblePositionManager — read only by LP functions (which we don't
    // leaf); the swap sanitizer (exactInput) never touches it.
    address internal constant UNIV3_NFPM = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;

    constructor() BaseDecoderAndSanitizer(address(0)) UniswapV3DecoderAndSanitizer(UNIV3_NFPM) {}
}
