// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

library BytesUtils {
    // @dev Utility function to slice bytes array
    function slice(
        bytes memory data,
        uint start,
        uint length
    ) private pure returns (bytes memory) {
        bytes memory part = new bytes(length);
        for (uint i = 0; i < length; i++) {
            part[i] = data[i + start];
        }
        return part;
    }
}
