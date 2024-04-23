// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

library AddressUtils {
    /// @dev utility function to convert an address to bytes32
    function toBytes(address addr) private pure returns (bytes32) {
        return bytes32(bytes20(addr)) >> 96;
    }
}
