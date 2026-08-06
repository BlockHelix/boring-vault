// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

/// @notice Redemption-queue escrows (Apyx UnlockReceipt and lookalikes): apyUSD.redeem() escrows
///         the underlying and mints an ERC-721 claim ticket; claim(tokenId, receiver) pays it out
///         after the 3-20 day fee curve. The tokenId is unconstrained on purpose — claiming any
///         receipt the vault happens to own is safe; the RECEIVER is what must be pinned, since a
///         claim to a foreign address is an exfiltration with a merkle proof.
abstract contract UnlockReceiptDecoderAndSanitizer is BaseDecoderAndSanitizer {
    //============================== UNLOCK RECEIPT ===============================

    function claim(uint256, address receiver) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(receiver);
    }
}
