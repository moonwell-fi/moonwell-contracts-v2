// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

library Bytes {
    // @dev Utility function to slice bytes array
    function slice(bytes memory data, uint256 start, uint256 length)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory part = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            part[i] = data[i + start];
        }
        return part;
    }
}
