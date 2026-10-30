// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

/**
 * @title SlipstreamDecoderAndSanitizer
 * @notice Aerodrome Slipstream SwapRouter exactInputSingle. Pins tokenIn, tokenOut and recipient,
 *         like the Uniswap sanitizers. tickSpacing is not sanitised, so a leaf authorises the pinned
 *         pair across every Slipstream pool of that pair; amounts and the minimum out are free.
 */
abstract contract SlipstreamDecoderAndSanitizer is BaseDecoderAndSanitizer {
    function exactInputSingle(DecoderCustomTypes.SlipstreamExactInputSingleParams calldata params)
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(params.tokenIn, params.tokenOut, params.recipient);
    }
}
