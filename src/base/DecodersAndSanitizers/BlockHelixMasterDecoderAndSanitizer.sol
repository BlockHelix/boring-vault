// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";
import {AaveV3DecoderAndSanitizer} from "src/base/DecodersAndSanitizers/Protocols/AaveV3DecoderAndSanitizer.sol";
import {UniswapV3Router02DecoderAndSanitizer} from "src/base/DecodersAndSanitizers/Protocols/UniswapV3Router02DecoderAndSanitizer.sol";
import {BalancerV2DecoderAndSanitizer} from "src/base/DecodersAndSanitizers/Protocols/BalancerV2DecoderAndSanitizer.sol";
import {MorphoBlueDecoderAndSanitizer} from
    "src/base/DecodersAndSanitizers/Protocols/MorphoBlueDecoderAndSanitizer.sol";
import {CurveDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/Protocols/CurveDecoderAndSanitizer.sol";
import {ERC4626DecoderAndSanitizer} from "src/base/DecodersAndSanitizers/Protocols/ERC4626DecoderAndSanitizer.sol";

/**
 * @title BlockHelixMasterDecoderAndSanitizer
 * @notice One shared decoder-and-sanitizer for every BlockHelix vault: Aave v3 + Uniswap v3
 *         + Balancer v2 (flashloans) + Morpho Blue + Curve + ERC4626. Deployed ONCE via CREATE3
 *         (`bh-master-decoder-v4`) and referenced by every vault's risk-profile manage root —
 *         the strategist supplies this address in each `manage` call.
 *
 *         v4 adds Curve `exchange` and ERC4626 `deposit`/`redeem`, which the sUSDe/USDtb levered
 *         loop needs: USDtb routes through Curve (no Uniswap v3 pool for it at any fee tier) and
 *         sUSDe is minted from USDe at NAV via a 4626 deposit rather than swapped.
 *
 *         Vault-agnostic singleton: the sanitizers are pure (per-vault pinning lives in the
 *         merkle LEAF, not here), so the `boringVault` immutable is unused and fixed to
 *         address(0). No external constructor args.
 */
contract BlockHelixMasterDecoderAndSanitizer is
    AaveV3DecoderAndSanitizer,
    UniswapV3Router02DecoderAndSanitizer,
    BalancerV2DecoderAndSanitizer,
    MorphoBlueDecoderAndSanitizer,
    CurveDecoderAndSanitizer,
    ERC4626DecoderAndSanitizer
{
    // All pure; per-vault pinning lives in the merkle leaf, so the boringVault immutable is
    // address(0). Names overlap across mixins (supply/withdraw/borrow/repay) but the signatures
    // differ, so those are overloads with distinct selectors. The three below genuinely collide
    // and are resolved exactly as Veda's own EtherFiLiquidUsd decoder resolves them.
    constructor() BaseDecoderAndSanitizer(address(0)) {}

    /**
     * @notice BalancerV2, Curve and ERC4626 all specify `deposit(uint256,address)`; every case
     *         pins the receiver, so one implementation serves all three.
     */
    function deposit(uint256, address receiver)
        external
        pure
        override(BalancerV2DecoderAndSanitizer, CurveDecoderAndSanitizer, ERC4626DecoderAndSanitizer)
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(receiver);
    }

    /**
     * @notice BalancerV2 and Curve both specify `withdraw(uint256)`; neither carries an address,
     *         so there is nothing to sanitize in either case.
     */
    function withdraw(uint256)
        external
        pure
        override(BalancerV2DecoderAndSanitizer, CurveDecoderAndSanitizer)
        returns (bytes memory addressesFound)
    {
        return addressesFound;
    }
}
