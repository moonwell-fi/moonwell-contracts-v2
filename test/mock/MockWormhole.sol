// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

contract MockWormhole {
    uint32 public lastNonce;
    bytes public lastPayload;
    uint8 public lastConsistencyLevel;

    /// @notice store last message for ease of use
    function publishMessage(
        uint32 nonce,
        bytes memory payload,
        uint8 consistencyLevel
    ) external payable returns (uint64 sequence) {
        lastNonce = nonce;
        lastPayload = payload;
        lastConsistencyLevel = consistencyLevel;

        return uint64(block.prevrandao);

        /// return semi random number, doesn't matter because return value is unused
    }
}
