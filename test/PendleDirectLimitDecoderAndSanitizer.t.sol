// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test} from "@forge-std/Test.sol";
import {stdJson} from "@forge-std/StdJson.sol";
import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";
import {PendleAggregatorDecoderAndSanitizer} from
    "src/base/DecodersAndSanitizers/Protocols/PendleAggregatorDecoderAndSanitizer.sol";

contract DirectHarness is PendleAggregatorDecoderAndSanitizer {
    constructor() BaseDecoderAndSanitizer(address(0)) {}
}

/// v11: PT-USD3's SY redeems straight to USDC, and Pendle's best exit fills part of the sale from its
/// limit router. The 30 Oct oBTC exit of 7,630 PT quoted 7,488.13 USDC this way.
contract PendleDirectLimitDecoderAndSanitizerTest is Test {
    using stdJson for string;

    address constant OBTC = 0xC209f6B2843Be8a7439eDCFA29986B2e5763cc2e;
    address constant MARKET = 0x4A5067C3fF1abb7449244025B0e37fEAF77D8E3e;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USD3 = 0x056B269Eb1f75477a8666ae8C7fE01b64dD55eCc;
    address constant LIMIT_ROUTER = 0x000000000000c9B3E2C3Ec88B1B4c0cD853f4321;
    address constant ATTACKER = address(0xBAD);

    DirectHarness decoder;
    string fixture;

    function setUp() external {
        fixture = vm.readFile(string.concat(vm.projectRoot(), "/test/resources/pendle-usd3-direct-routes.json"));
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), fixture.readUint(".block"));
        decoder = new DirectHarness();
    }

    function _call(bytes memory data) internal view returns (bool ok, bytes memory found) {
        (bool success, bytes memory ret) = address(decoder).staticcall(data);
        if (!success) return (false, ret);
        return (true, abi.decode(ret, (bytes)));
    }

    function _direct(address redeemSy) internal pure returns (DecoderCustomTypes.TokenOutput memory o) {
        o.tokenOut = USDC;
        o.tokenRedeemSy = redeemSy;
    }

    function _none() internal pure returns (DecoderCustomTypes.LimitOrderData memory l) {}

    function _limit(address router) internal pure returns (DecoderCustomTypes.LimitOrderData memory l) {
        l.limitRouter = router;
        l.flashFills = new DecoderCustomTypes.FillOrderParams[](1);
    }

    function testRealSdkUsd3ExitWithALimitFillDecodes() external {
        (bool ok, bytes memory found) = _call(fixture.readBytes(".exit"));
        assertTrue(ok, "the SDK's best PT-USD3 exit must decode");
        assertEq(found, abi.encodePacked(OBTC, MARKET, USDC, USDC, address(0), address(0), address(0), address(0)));
    }

    function testDirectExitWhoseSyRedeemsToAnotherTokenReverts() external {
        vm.expectRevert(PendleAggregatorDecoderAndSanitizer.PendleAggregatorDecoderAndSanitizer__BadRoute.selector);
        decoder.swapExactPtForToken(OBTC, MARKET, 1_000e6, _direct(USD3), _none());
    }

    function testDirectExitCarryingCalldataReverts() external {
        DecoderCustomTypes.TokenOutput memory o = _direct(USDC);
        o.swapData.extCalldata = hex"e21fd0e9";
        vm.expectRevert(PendleAggregatorDecoderAndSanitizer.PendleAggregatorDecoderAndSanitizer__BadRoute.selector);
        decoder.swapExactPtForToken(OBTC, MARKET, 1_000e6, o, _none());
    }

    function testDirectExitWithARouterOrPendleSwapReverts() external {
        DecoderCustomTypes.TokenOutput memory o = _direct(USDC);
        o.swapData.extRouter = ATTACKER;
        vm.expectRevert(PendleAggregatorDecoderAndSanitizer.PendleAggregatorDecoderAndSanitizer__BadRoute.selector);
        decoder.swapExactPtForToken(OBTC, MARKET, 1_000e6, o, _none());
        o = _direct(USDC);
        o.pendleSwap = ATTACKER;
        vm.expectRevert(PendleAggregatorDecoderAndSanitizer.PendleAggregatorDecoderAndSanitizer__BadRoute.selector);
        decoder.swapExactPtForToken(OBTC, MARKET, 1_000e6, o, _none());
    }

    function testDirectExitStillFlooredOnTheTwap() external {
        vm.expectRevert(PendleAggregatorDecoderAndSanitizer.PendleAggregatorDecoderAndSanitizer__MinOutBelowTwap.selector);
        decoder.swapExactPtForToken(OBTC, MARKET, 1_000e6, _direct(USDC), _limit(LIMIT_ROUTER));
    }

    function testFillsThroughAnyOtherLimitRouterRevert() external {
        DecoderCustomTypes.TokenOutput memory o = _direct(USDC);
        o.minTokenOut = 990e6;
        vm.expectRevert(
            PendleAggregatorDecoderAndSanitizer.PendleAggregatorDecoderAndSanitizer__LimitOrdersNotPermitted.selector
        );
        decoder.swapExactPtForToken(OBTC, MARKET, 1_000e6, o, _limit(ATTACKER));
        DecoderCustomTypes.LimitOrderData memory l = _limit(address(0));
        vm.expectRevert(
            PendleAggregatorDecoderAndSanitizer.PendleAggregatorDecoderAndSanitizer__LimitOrdersNotPermitted.selector
        );
        decoder.swapExactPtForToken(OBTC, MARKET, 1_000e6, o, l);
    }

    function testDirectEntryMintsSyFromTheTokenItself() external {
        DecoderCustomTypes.TokenInput memory i;
        i.tokenIn = USDC;
        i.netTokenIn = 1_000e6;
        i.tokenMintSy = USDC;
        DecoderCustomTypes.ApproxParams memory a = DecoderCustomTypes.ApproxParams(0, type(uint256).max, 0, 30, 1e12);
        bytes memory found = decoder.swapExactTokenForPt(OBTC, MARKET, 1_000e6, a, i, _limit(LIMIT_ROUTER));
        assertEq(found, abi.encodePacked(OBTC, MARKET, USDC, USDC, address(0), address(0), address(0), address(0)));
    }
}
