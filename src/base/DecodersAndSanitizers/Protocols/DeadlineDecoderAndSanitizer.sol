// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

/**
 * @title DeadlineDecoderAndSanitizer
 * @notice Uniswap SwapRouter02 `multicall(uint256 deadline, bytes[] data)` as a pure deadline check:
 *         the router's checkDeadline modifier reverts "Transaction too old" past `deadline`, so a leg
 *         with EMPTY data fails a stale manage bundle and does nothing else. Any data is refused
 *         here, because a router multicall can carry swaps whose recipients this sanitizer would
 *         not see. Nothing to pin, so the leaf is (decoder, router, selector).
 */
abstract contract DeadlineDecoderAndSanitizer is BaseDecoderAndSanitizer {
    error DeadlineDecoderAndSanitizer__DataNotEmpty();

    function multicall(uint256, bytes[] calldata data) external pure virtual returns (bytes memory addressesFound) {
        if (data.length != 0) revert DeadlineDecoderAndSanitizer__DataNotEmpty();
        return addressesFound;
    }
}
