// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

interface IWormholeTrustedSender {
    /// ------------- VIEW ONLY API -------------

    /// @notice returns whether or not the address is in the trusted senders list for a given chain
    /// @param chainId The wormhole chain id to check
    /// @param addr The address to check
    function isTrustedSender(uint16 chainId, bytes32 addr) external view returns (bool);

    /// @notice returns whether or not the address is in the trusted senders list for a given chain
    /// @param chainId The wormhole chain id to check
    /// @param addr The address to check
    function isTrustedSender(uint16 chainId, address addr) external view returns (bool);

    /// @notice returns the list of trusted senders for a given chain
    /// @param chainId The wormhole chain id to check
    /// @return The list of trusted senders
    function allTrustedSenders(uint16 chainId) external view returns (bytes32[] memory);

    /// @notice Wormhole addresses are denominated in 32 byte chunks. Converting the address to a bytes20
    /// then to a bytes32 *left* aligns it, so we right shift to get the proper data
    /// @param addr The address to convert
    /// @return The address as a bytes32
    function addressToBytes(address addr) external pure returns (bytes32);
}
