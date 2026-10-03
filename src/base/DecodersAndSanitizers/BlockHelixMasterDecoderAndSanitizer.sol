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
import {PendleRouterDecoderAndSanitizer} from
    "src/base/DecodersAndSanitizers/Protocols/PendleRouterDecoderAndSanitizer.sol";
import {UnlockReceiptDecoderAndSanitizer} from
    "src/base/DecodersAndSanitizers/Protocols/UnlockReceiptDecoderAndSanitizer.sol";
import {EthenaWithdrawDecoderAndSanitizer} from
    "src/base/DecodersAndSanitizers/Protocols/EthenaWithdrawDecoderAndSanitizer.sol";
import {PendleAggregatorDecoderAndSanitizer} from
    "src/base/DecodersAndSanitizers/Protocols/PendleAggregatorDecoderAndSanitizer.sol";
import {SlipstreamDecoderAndSanitizer} from
    "src/base/DecodersAndSanitizers/Protocols/SlipstreamDecoderAndSanitizer.sol";

/**
 * @title BlockHelixMasterDecoderAndSanitizer
 * @notice One shared decoder-and-sanitizer for every BlockHelix vault: Aave v3 + Uniswap v3
 *         + Balancer v2 (flashloans) + Morpho Blue + Curve + ERC4626 + Pendle. Deployed ONCE via
 *         CREATE3 (`bh-master-decoder-v9`) and referenced by every vault's risk-profile manage
 *         root — the strategist supplies this address in each `manage` call.
 *
 *         v4 added Curve `exchange` and ERC4626 `deposit`/`redeem` for the sUSDe/USDtb loop.
 *
 *         v5 adds the Pendle router, which the PT levered loop needs: apxUSD is minted into
 *         SY via `mintSyFromToken` and swapped to PT on the Pendle AMM via `swapExactSyForPt`
 *         (plus the inverse legs and post-maturity `redeemPyToSy` for the exit path). Pendle's
 *         sanitizers already reject external-aggregator routes and limit-order fills. Verified
 *         against compiled methodIdentifiers: Pendle's selectors are disjoint from every other
 *         mixin, so no new override resolutions are needed.
 *
 *         v6 adds the UnlockReceipt escrow's `claim(uint256,address)`: apyUSD.redeem() mints an
 *         ERC-721 claim ticket (SY-apyUSD redeems ONLY to apyUSD, and apyUSD's 4626 interface
 *         fronts a 3-20 day redemption queue), so the PT exit's final hop is a claim on the
 *         escrow. The receiver is pinned in the leaf; the tokenId is deliberately free.
 *
 *         v7 adds Ethena's withdraw path: `cooldownShares`/`cooldownAssets` + `unstake`. sUSDe
 *         sets `cooldownDuration` non-zero (86400s when measured 2026-09-01), and while it is
 *         non-zero StakedUSDeV2 disables `redeem`/`withdraw` outright — they revert
 *         `OperationNotAllowed()`. So the v4 4626 `redeem` leaf, which the sUSDe/USDtb loop was
 *         built on, cannot exit that position at all: the collateral is frozen until these
 *         selectors are callable. The receiver is pinned in the leaf; the amount is free.
 *
 *         v8 adds Pendle router swaps routed through KyberSwap (`swapExactTokenForPt`,
 *         `swapExactPtForToken`). The vault's own hop-by-hop route cost 1.35% round trip on
 *         PT-apyUSD/USDC against ~0.35% through the router (2026-10-01). These two read Pendle's
 *         TWAP oracle to floor the caller's minimum out, so unlike every other mixin they are view.
 *
 *         v9 adds Aerodrome Slipstream's router `exactInputSingle` for Base pools priced in tick
 *         spacing (the B20 stock pools, VVV/WETH). Its struct differs from Uniswap's in tickSpacing
 *         and deadline, so it is an overload with its own selector; tokenIn, tokenOut and recipient
 *         are pinned exactly as the Uniswap sanitizers pin them.
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
    ERC4626DecoderAndSanitizer,
    PendleRouterDecoderAndSanitizer,
    UnlockReceiptDecoderAndSanitizer,
    EthenaWithdrawDecoderAndSanitizer,
    PendleAggregatorDecoderAndSanitizer,
    SlipstreamDecoderAndSanitizer
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
