// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

/**
 * @title CurveNgDecoderAndSanitizer
 * @notice Curve StableSwap-NG receiver overloads. Both return the receiver, so the leaf pins where
 *         the output goes: the vault, or the next NG pool in a route. `exchange_received` swaps
 *         whatever the pool holds above its stored balances (the previous hop's output, sent there
 *         by that hop's pinned receiver), which is how a route spends exactly what arrived and
 *         leaves no intermediate dust. i, j, dx and min_dy stay free, as in the 4-arg exchange.
 */
abstract contract CurveNgDecoderAndSanitizer is BaseDecoderAndSanitizer {
    function exchange(int128, int128, uint256, uint256, address receiver)
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(receiver);
    }

    function exchange_received(int128, int128, uint256, uint256, address receiver)
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(receiver);
    }
}
