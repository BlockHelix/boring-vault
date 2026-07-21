// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

/**
 * @title UniswapV3Router02DecoderAndSanitizer
 * @notice Swap sanitizers for Uniswap SwapRouter02 (the router deployed on Base and most L2s).
 *         SwapRouter02 dropped the `deadline` field the original SwapRouter carried, so its
 *         exactInput/exactInputSingle have distinct signatures/selectors (0xb858183f / 0x04e45aaf)
 *         and cannot reuse UniswapV3DecoderAndSanitizer. Swap-only: LP functions are not leafed.
 */
abstract contract UniswapV3Router02DecoderAndSanitizer is BaseDecoderAndSanitizer {
    error UniswapV3Router02DecoderAndSanitizer__BadPathFormat();

    // Walk params.path in 23-byte (20-byte token + 3-byte fee) chunks, returning every token in
    // order followed by the recipient. The fee is never inspected, so one leaf per directional
    // pair authorises that swap across every fee tier.
    function exactInput(DecoderCustomTypes.UniswapV3Router02ExactInputParams calldata params)
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        uint256 chunkSize = 23;
        uint256 pathLength = params.path.length;
        if (pathLength % chunkSize != 20) revert UniswapV3Router02DecoderAndSanitizer__BadPathFormat();
        uint256 pathAddressLength = 1 + (pathLength / chunkSize);
        uint256 pathIndex;
        for (uint256 i; i < pathAddressLength; ++i) {
            addressesFound = abi.encodePacked(addressesFound, params.path[pathIndex:pathIndex + 20]);
            pathIndex += chunkSize;
        }
        addressesFound = abi.encodePacked(addressesFound, params.recipient);
    }

    // tokenIn, tokenOut and recipient are explicit fields; pin all three. The fee is not
    // sanitised, so any tier of the pinned pair is allowed.
    function exactInputSingle(DecoderCustomTypes.UniswapV3Router02ExactInputSingleParams calldata params)
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(params.tokenIn, params.tokenOut, params.recipient);
    }
}
