// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

interface IPendlePtTwapOracle {
    function getPtToAssetRate(address market, uint32 duration) external view returns (uint256);
}

interface IPendleMarketTokens {
    function readTokens() external view returns (address sy, address pt, address yt);
}

interface IDecimals {
    function decimals() external view returns (uint8);
}

/**
 * Pendle router swaps whose token leg runs through KyberSwap.
 *
 * Returned for the leaf to pin: receiver, market, both token ends, pendleSwap, the Kyber router,
 * the Kyber executor and the Kyber output receiver. Checked here, because a leaf cannot see into
 * the aggregator calldata: the token ends agree across both layers, no fee receivers, only the
 * executor receives input, no approval target, no limit orders, and the caller's minimum out is
 * within MAX_BELOW_TWAP_BPS of Pendle's TWAP. Without the floor, a strategist could route the
 * input anywhere with a zero minimum.
 *
 * Assumes the SY asset and the swapped token are both USD stablecoins; the market is pinned by
 * the leaf, so that is a policy choice, not an input.
 */
abstract contract PendleAggregatorDecoderAndSanitizer is BaseDecoderAndSanitizer {
    error PendleAggregatorDecoderAndSanitizer__BadRoute();
    error PendleAggregatorDecoderAndSanitizer__MinOutBelowTwap();
    error PendleAggregatorDecoderAndSanitizer__LimitOrdersNotPermitted();

    IPendlePtTwapOracle internal constant PT_TWAP_ORACLE =
        IPendlePtTwapOracle(0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2);
    uint32 internal constant TWAP_DURATION = 900;
    // A legitimate 1,000 PT-apyUSD exit quoted 2.6% under TWAP (apyUSD sells below NAV), 2026-10-01.
    uint256 internal constant MAX_BELOW_TWAP_BPS = 500;
    bytes4 internal constant KYBER_SWAP_SELECTOR = 0xe21fd0e9;

    struct KyberSwapDescription {
        address srcToken;
        address dstToken;
        address[] srcReceivers;
        uint256[] srcAmounts;
        address[] feeReceivers;
        uint256[] feeAmounts;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
        bytes permit;
    }

    struct KyberSwapExecutionParams {
        address callTarget;
        address approveTarget;
        bytes targetData;
        KyberSwapDescription desc;
        bytes clientData;
    }

    function swapExactTokenForPt(
        address receiver,
        address market,
        uint256 minPtOut,
        DecoderCustomTypes.ApproxParams calldata,
        DecoderCustomTypes.TokenInput calldata input,
        DecoderCustomTypes.LimitOrderData calldata limit
    ) external view virtual returns (bytes memory addressesFound) {
        _rejectLimitOrders(limit);
        (address executor, address dstReceiver) = _checkKyber(input.swapData, input.tokenIn, input.tokenMintSy);

        uint8 ptDecimals = _ptDecimals(market);
        uint256 inAsPt = _rescale(input.netTokenIn, IDecimals(input.tokenIn).decimals(), ptDecimals);
        uint256 fairPtOut = inAsPt * 1e18 / PT_TWAP_ORACLE.getPtToAssetRate(market, TWAP_DURATION);
        if (minPtOut * 10_000 < fairPtOut * (10_000 - MAX_BELOW_TWAP_BPS)) {
            revert PendleAggregatorDecoderAndSanitizer__MinOutBelowTwap();
        }

        addressesFound = abi.encodePacked(
            receiver,
            market,
            input.tokenIn,
            input.tokenMintSy,
            input.pendleSwap,
            input.swapData.extRouter,
            executor,
            dstReceiver
        );
    }

    function swapExactPtForToken(
        address receiver,
        address market,
        uint256 exactPtIn,
        DecoderCustomTypes.TokenOutput calldata output,
        DecoderCustomTypes.LimitOrderData calldata limit
    ) external view virtual returns (bytes memory addressesFound) {
        _rejectLimitOrders(limit);
        (address executor, address dstReceiver) =
            _checkKyber(output.swapData, output.tokenRedeemSy, output.tokenOut);

        uint256 assetOut = exactPtIn * PT_TWAP_ORACLE.getPtToAssetRate(market, TWAP_DURATION) / 1e18;
        uint256 fairOut = _rescale(assetOut, _ptDecimals(market), IDecimals(output.tokenOut).decimals());
        if (output.minTokenOut * 10_000 < fairOut * (10_000 - MAX_BELOW_TWAP_BPS)) {
            revert PendleAggregatorDecoderAndSanitizer__MinOutBelowTwap();
        }

        addressesFound = abi.encodePacked(
            receiver,
            market,
            output.tokenOut,
            output.tokenRedeemSy,
            output.pendleSwap,
            output.swapData.extRouter,
            executor,
            dstReceiver
        );
    }

    function _checkKyber(DecoderCustomTypes.SwapData calldata swapData, address srcToken, address dstToken)
        internal
        pure
        returns (address executor, address dstReceiver)
    {
        bytes calldata ext = swapData.extCalldata;
        if (
            swapData.swapType != DecoderCustomTypes.SwapType.KYBERSWAP || ext.length < 4
                || bytes4(ext[:4]) != KYBER_SWAP_SELECTOR
        ) revert PendleAggregatorDecoderAndSanitizer__BadRoute();

        KyberSwapExecutionParams memory p = abi.decode(ext[4:], (KyberSwapExecutionParams));
        KyberSwapDescription memory d = p.desc;
        if (
            d.srcToken != srcToken || d.dstToken != dstToken || d.feeReceivers.length != 0
                || p.approveTarget != address(0) || d.srcReceivers.length == 0
        ) revert PendleAggregatorDecoderAndSanitizer__BadRoute();
        for (uint256 i; i < d.srcReceivers.length; ++i) {
            if (d.srcReceivers[i] != p.callTarget) revert PendleAggregatorDecoderAndSanitizer__BadRoute();
        }
        return (p.callTarget, d.dstReceiver);
    }

    function _rejectLimitOrders(DecoderCustomTypes.LimitOrderData calldata limit) internal pure {
        if (limit.limitRouter != address(0) || limit.normalFills.length > 0 || limit.flashFills.length > 0) {
            revert PendleAggregatorDecoderAndSanitizer__LimitOrdersNotPermitted();
        }
    }

    function _ptDecimals(address market) internal view returns (uint8) {
        (, address pt,) = IPendleMarketTokens(market).readTokens();
        return IDecimals(pt).decimals();
    }

    function _rescale(uint256 amount, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) return amount;
        if (fromDecimals < toDecimals) return amount * 10 ** (toDecimals - fromDecimals);
        return amount / 10 ** (fromDecimals - toDecimals);
    }
}
