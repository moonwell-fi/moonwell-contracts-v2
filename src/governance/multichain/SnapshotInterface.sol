// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

interface SnapshotInterface {
    /// @notice Gets the current votes balance for `account`
    /// @param account The address to get votes balance
    /// @return The number of current votes for `account`
    function getCurrentVotes(address account) external view returns (uint256);

    /// @notice Determine the prior number of votes for an account as of a timestamp
    /// @dev Timestamp must be in the past or else this function will revert to prevent misinformation.
    /// @param account The address of the account to check
    /// @param timestamp The unix timestamp in seconds to get the vote balance at
    /// @return The number of votes the account had as of the given timestamp
    function getPriorVotes(
        address account,
        uint256 timestamp
    ) external view returns (uint256);
}
