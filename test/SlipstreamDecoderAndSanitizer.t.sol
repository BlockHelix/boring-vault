// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test} from "@forge-std/Test.sol";
import {BlockHelixMasterDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/BlockHelixMasterDecoderAndSanitizer.sol";
import {DecoderCustomTypes} from "src/interfaces/DecoderCustomTypes.sol";

contract SlipstreamDecoderAndSanitizerTest is Test {
    BlockHelixMasterDecoderAndSanitizer decoder;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant NVDAC = 0xb20000000000000000000078ee7ce2fE4908108C;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant VVV = 0xacfE6019Ed1A7Dc6f7B508C02d1b04ec88cC21bf;
    address constant RECIPIENT = 0xe0C78ab697C6F58FA881816e8FdAd696cfD6801b;

    function setUp() public {
        decoder = new BlockHelixMasterDecoderAndSanitizer();
    }

    /// Calldata of a real Slipstream router swap on Base (tx 0x5b4766eb...1644, 2026-10-02).
    function test_decodesARealRouterSwap() public {
        bytes memory real = hex"a026383e000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda02913000000000000000000000000b20000000000000000000078ee7ce2fe4908108c000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000e0c78ab697c6f58fa881816e8fdad696cfd6801b000000000000000000000000000000000000000000000000000000006abfdadd000000000000000000000000000000000000000000000000000000000000271000000000000000000000000000000000000000000000000000000000000010540000000000000000000000000000000000000000000000000000000000000000";
        (bool ok, bytes memory ret) = address(decoder).staticcall(real);
        assertTrue(ok);
        assertEq(abi.decode(ret, (bytes)), abi.encodePacked(USDC, NVDAC, RECIPIENT));
    }

    function test_pinsTokenInTokenOutAndRecipient() public {
        DecoderCustomTypes.SlipstreamExactInputSingleParams memory p = DecoderCustomTypes.SlipstreamExactInputSingleParams({
            tokenIn: WETH, tokenOut: VVV, tickSpacing: 100, recipient: address(0xBEEF),
            deadline: 1, amountIn: 1e15, amountOutMinimum: 7, sqrtPriceLimitX96: 0
        });
        assertEq(decoder.exactInputSingle(p), abi.encodePacked(WETH, VVV, address(0xBEEF)));
    }

    /// The Uniswap Router02 overload must be unaffected by the new one.
    function test_uniswapRouter02StillDecodes() public {
        DecoderCustomTypes.UniswapV3Router02ExactInputSingleParams memory p = DecoderCustomTypes.UniswapV3Router02ExactInputSingleParams({
            tokenIn: USDC, tokenOut: WETH, fee: 500, recipient: address(0xBEEF), amountIn: 1, amountOutMinimum: 0, sqrtPriceLimitX96: 0
        });
        assertEq(decoder.exactInputSingle(p), abi.encodePacked(USDC, WETH, address(0xBEEF)));
    }

    function test_selectorMatchesTheRouter() public {
        assertEq(
            bytes4(keccak256("exactInputSingle((address,address,int24,address,uint256,uint256,uint256,uint160))")),
            bytes4(0xa026383e)
        );
    }
}
