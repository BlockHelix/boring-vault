// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test} from "@forge-std/Test.sol";
import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";
import {
    PendleAggregatorDecoderAndSanitizer,
    IPendlePtTwapOracle
} from "src/base/DecodersAndSanitizers/Protocols/PendleAggregatorDecoderAndSanitizer.sol";

contract Harness is PendleAggregatorDecoderAndSanitizer {
    constructor() BaseDecoderAndSanitizer(address(0)) {}
}

/// Routes are shaped exactly like Pendle's SDK output for PT-apyUSD-5NOV2026, decoded 2026-10-01.
contract PendleAggregatorDecoderAndSanitizerTest is Test {
    address constant VAULT = 0x1e23a0cADD6E61310Dd1d6938ca02Af2835e4659;
    address constant MARKET = 0xC5f938A8ef5F3BF9E72F5aA094baF5E03f4727D3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant APYUSD = 0x38EEb52F0771140d10c4E9A9a72349A329Fe8a6A;
    address constant PENDLE_ROUTER = 0x888888888889758F76e7103c6CbF23ABbF58F946;
    address constant PENDLE_SWAP = 0xd4F480965D2347d421F1bEC7F545682E5Ec2151D;
    address constant KYBER_ROUTER = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5;
    address constant KYBER_EXECUTOR = 0x8F10B468b06c6FD214B65F87778827F7D113f996;
    address constant ATTACKER = address(0xBAD);
    IPendlePtTwapOracle constant ORACLE = IPendlePtTwapOracle(0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2);

    Harness decoder;
    uint256 rate;

    function setUp() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        decoder = new Harness();
        rate = ORACLE.getPtToAssetRate(MARKET, 900);
    }

    // ------------------------------------------------------------------ builders

    function _kyber(address src, address dst, address[] memory srcReceivers, address[] memory feeReceivers, address dstReceiver, address approveTarget)
        internal
        pure
        returns (bytes memory)
    {
        uint256[] memory amounts = new uint256[](srcReceivers.length);
        PendleAggregatorDecoderAndSanitizer.KyberSwapDescription memory d = PendleAggregatorDecoderAndSanitizer
            .KyberSwapDescription(src, dst, srcReceivers, amounts, feeReceivers, new uint256[](feeReceivers.length), dstReceiver, 0, 0, 512, "");
        return abi.encodeWithSelector(
            bytes4(0xe21fd0e9),
            PendleAggregatorDecoderAndSanitizer.KyberSwapExecutionParams(KYBER_EXECUTOR, approveTarget, hex"00", d, "")
        );
    }

    function _one(address a) internal pure returns (address[] memory r) {
        r = new address[](1);
        r[0] = a;
    }

    function _input(bytes memory ext) internal pure returns (DecoderCustomTypes.TokenInput memory) {
        return DecoderCustomTypes.TokenInput(
            USDC, 1_000e6, APYUSD, PENDLE_SWAP, DecoderCustomTypes.SwapData(DecoderCustomTypes.SwapType.KYBERSWAP, KYBER_ROUTER, ext, true)
        );
    }

    function _output(bytes memory ext, uint256 minOut) internal pure returns (DecoderCustomTypes.TokenOutput memory) {
        return DecoderCustomTypes.TokenOutput(
            USDC, minOut, APYUSD, PENDLE_SWAP, DecoderCustomTypes.SwapData(DecoderCustomTypes.SwapType.KYBERSWAP, KYBER_ROUTER, ext, true)
        );
    }

    function _noLimit() internal pure returns (DecoderCustomTypes.LimitOrderData memory l) {}

    function _approx() internal pure returns (DecoderCustomTypes.ApproxParams memory) {
        return DecoderCustomTypes.ApproxParams(0, type(uint256).max, 0, 30, 1e12);
    }

    function _goodEntry() internal pure returns (bytes memory) {
        return _kyber(USDC, APYUSD, _one(KYBER_EXECUTOR), new address[](0), PENDLE_ROUTER, address(0));
    }

    function _fairPtFor1000Usdc() internal view returns (uint256) {
        return 1_000e18 * 1e18 / rate;
    }

    // ------------------------------------------------------------------ entry

    function testEntryReturnsEveryAddressTheLeafPins() external {
        bytes memory found = decoder.swapExactTokenForPt(
            VAULT, MARKET, _fairPtFor1000Usdc() * 99 / 100, _approx(), _input(_goodEntry()), _noLimit()
        );
        assertEq(
            found,
            abi.encodePacked(VAULT, MARKET, USDC, APYUSD, PENDLE_SWAP, KYBER_ROUTER, KYBER_EXECUTOR, PENDLE_ROUTER)
        );
    }

    function testEntryZeroMinimumReverts() external {
        vm.expectRevert(PendleAggregatorDecoderAndSanitizer.PendleAggregatorDecoderAndSanitizer__MinOutBelowTwap.selector);
        decoder.swapExactTokenForPt(VAULT, MARKET, 0, _approx(), _input(_goodEntry()), _noLimit());
    }

    function testEntryMinimumJustOutsideTheBandReverts() external {
        vm.expectRevert(PendleAggregatorDecoderAndSanitizer.PendleAggregatorDecoderAndSanitizer__MinOutBelowTwap.selector);
        decoder.swapExactTokenForPt(
            VAULT, MARKET, _fairPtFor1000Usdc() * 9_499 / 10_000, _approx(), _input(_goodEntry()), _noLimit()
        );
    }

    function testEntryInputSentToAttackerReverts() external {
        address[] memory receivers = new address[](2);
        receivers[0] = KYBER_EXECUTOR;
        receivers[1] = ATTACKER;
        bytes memory ext = _kyber(USDC, APYUSD, receivers, new address[](0), PENDLE_ROUTER, address(0));
        vm.expectRevert(PendleAggregatorDecoderAndSanitizer.PendleAggregatorDecoderAndSanitizer__BadRoute.selector);
        decoder.swapExactTokenForPt(VAULT, MARKET, _fairPtFor1000Usdc(), _approx(), _input(ext), _noLimit());
    }

    function testEntryFeeReceiverReverts() external {
        bytes memory ext = _kyber(USDC, APYUSD, _one(KYBER_EXECUTOR), _one(ATTACKER), PENDLE_ROUTER, address(0));
        vm.expectRevert(PendleAggregatorDecoderAndSanitizer.PendleAggregatorDecoderAndSanitizer__BadRoute.selector);
        decoder.swapExactTokenForPt(VAULT, MARKET, _fairPtFor1000Usdc(), _approx(), _input(ext), _noLimit());
    }

    function testEntryApproveTargetReverts() external {
        bytes memory ext = _kyber(USDC, APYUSD, _one(KYBER_EXECUTOR), new address[](0), PENDLE_ROUTER, ATTACKER);
        vm.expectRevert(PendleAggregatorDecoderAndSanitizer.PendleAggregatorDecoderAndSanitizer__BadRoute.selector);
        decoder.swapExactTokenForPt(VAULT, MARKET, _fairPtFor1000Usdc(), _approx(), _input(ext), _noLimit());
    }

    function testEntryTokenMismatchReverts() external {
        bytes memory ext = _kyber(USDC, ATTACKER, _one(KYBER_EXECUTOR), new address[](0), PENDLE_ROUTER, address(0));
        vm.expectRevert(PendleAggregatorDecoderAndSanitizer.PendleAggregatorDecoderAndSanitizer__BadRoute.selector);
        decoder.swapExactTokenForPt(VAULT, MARKET, _fairPtFor1000Usdc(), _approx(), _input(ext), _noLimit());
    }

    /// A redirected output is not rejected here: it changes the returned addresses, so the leaf
    /// (pinned to Pendle's router as the receiver) no longer matches and the manager refuses it.
    function testEntryRedirectedOutputChangesThePinnedAddresses() external {
        bytes memory ext = _kyber(USDC, APYUSD, _one(KYBER_EXECUTOR), new address[](0), ATTACKER, address(0));
        bytes memory found =
            decoder.swapExactTokenForPt(VAULT, MARKET, _fairPtFor1000Usdc(), _approx(), _input(ext), _noLimit());
        assertTrue(
            keccak256(found)
                != keccak256(abi.encodePacked(VAULT, MARKET, USDC, APYUSD, PENDLE_SWAP, KYBER_ROUTER, KYBER_EXECUTOR, PENDLE_ROUTER))
        );
    }

    function testEntryWrongSelectorReverts() external {
        bytes memory ext = _goodEntry();
        ext[0] = 0x00;
        vm.expectRevert(PendleAggregatorDecoderAndSanitizer.PendleAggregatorDecoderAndSanitizer__BadRoute.selector);
        decoder.swapExactTokenForPt(VAULT, MARKET, _fairPtFor1000Usdc(), _approx(), _input(ext), _noLimit());
    }

    function testEntryLimitOrderReverts() external {
        DecoderCustomTypes.LimitOrderData memory l;
        l.limitRouter = ATTACKER;
        vm.expectRevert(
            PendleAggregatorDecoderAndSanitizer.PendleAggregatorDecoderAndSanitizer__LimitOrdersNotPermitted.selector
        );
        decoder.swapExactTokenForPt(VAULT, MARKET, _fairPtFor1000Usdc(), _approx(), _input(_goodEntry()), l);
    }

    // ------------------------------------------------------------------ exit

    function _goodExit() internal pure returns (bytes memory) {
        return _kyber(APYUSD, USDC, _one(KYBER_EXECUTOR), new address[](0), PENDLE_ROUTER, address(0));
    }

    function _fairUsdcFor1000Pt() internal view returns (uint256) {
        return 1_000e18 * rate / 1e18 / 1e12;
    }

    /// The SDK's own exit for 1,000 PT quoted 955.72 USDC minimum, 3.1% under TWAP. It must pass.
    function testExitAtTheMeasuredRealCostPasses() external {
        bytes memory found = decoder.swapExactPtForToken(
            VAULT, MARKET, 1_000e18, _output(_goodExit(), _fairUsdcFor1000Pt() * 9_690 / 10_000), _noLimit()
        );
        assertEq(
            found,
            abi.encodePacked(VAULT, MARKET, USDC, APYUSD, PENDLE_SWAP, KYBER_ROUTER, KYBER_EXECUTOR, PENDLE_ROUTER)
        );
    }

    function testExitZeroMinimumReverts() external {
        vm.expectRevert(PendleAggregatorDecoderAndSanitizer.PendleAggregatorDecoderAndSanitizer__MinOutBelowTwap.selector);
        decoder.swapExactPtForToken(VAULT, MARKET, 1_000e18, _output(_goodExit(), 0), _noLimit());
    }

    function testExitInputSentToAttackerReverts() external {
        bytes memory ext = _kyber(APYUSD, USDC, _one(ATTACKER), new address[](0), PENDLE_ROUTER, address(0));
        vm.expectRevert(PendleAggregatorDecoderAndSanitizer.PendleAggregatorDecoderAndSanitizer__BadRoute.selector);
        decoder.swapExactPtForToken(VAULT, MARKET, 1_000e18, _output(ext, _fairUsdcFor1000Pt()), _noLimit());
    }

    function testExitRequiresKyberSwapType() external {
        DecoderCustomTypes.TokenOutput memory o = _output(_goodExit(), _fairUsdcFor1000Pt());
        o.swapData.swapType = DecoderCustomTypes.SwapType.ONE_INCH;
        vm.expectRevert(PendleAggregatorDecoderAndSanitizer.PendleAggregatorDecoderAndSanitizer__BadRoute.selector);
        decoder.swapExactPtForToken(VAULT, MARKET, 1_000e18, o, _noLimit());
    }

    // ------------------------------------------------------------------ real SDK bytes

    function _fixture() internal view returns (string memory) {
        return vm.readFile(string.concat(vm.projectRoot(), "/test/resources/pendle-kyber-routes.json"));
    }

    /// The synthesized routes above only prove the checks; this proves Pendle's actual bytes decode
    /// through them and pin the addresses the leaf will carry.
    function testRealSdkEntryDecodes() external {
        string memory j = _fixture();
        DecoderCustomTypes.TokenInput memory input = DecoderCustomTypes.TokenInput(
            USDC,
            vm.parseJsonUint(j, ".entry.netTokenIn"),
            vm.parseJsonAddress(j, ".entry.tokenMintSy"),
            vm.parseJsonAddress(j, ".entry.pendleSwap"),
            DecoderCustomTypes.SwapData(
                DecoderCustomTypes.SwapType.KYBERSWAP,
                vm.parseJsonAddress(j, ".entry.extRouter"),
                vm.parseJsonBytes(j, ".entry.extCalldata"),
                true
            )
        );
        bytes memory found =
            decoder.swapExactTokenForPt(VAULT, MARKET, vm.parseJsonUint(j, ".entry.minPtOut"), _approx(), input, _noLimit());
        assertEq(
            found,
            abi.encodePacked(VAULT, MARKET, USDC, APYUSD, PENDLE_SWAP, KYBER_ROUTER, KYBER_EXECUTOR, PENDLE_ROUTER)
        );
    }

    function testRealSdkExitDecodes() external {
        string memory j = _fixture();
        DecoderCustomTypes.TokenOutput memory output = DecoderCustomTypes.TokenOutput(
            USDC,
            vm.parseJsonUint(j, ".exit.minTokenOut"),
            vm.parseJsonAddress(j, ".exit.tokenRedeemSy"),
            vm.parseJsonAddress(j, ".exit.pendleSwap"),
            DecoderCustomTypes.SwapData(
                DecoderCustomTypes.SwapType.KYBERSWAP,
                vm.parseJsonAddress(j, ".exit.extRouter"),
                vm.parseJsonBytes(j, ".exit.extCalldata"),
                true
            )
        );
        bytes memory found =
            decoder.swapExactPtForToken(VAULT, MARKET, vm.parseJsonUint(j, ".exit.exactPtIn"), output, _noLimit());
        assertEq(
            found,
            abi.encodePacked(VAULT, MARKET, USDC, APYUSD, PENDLE_SWAP, KYBER_ROUTER, KYBER_EXECUTOR, PENDLE_ROUTER)
        );
    }
}
