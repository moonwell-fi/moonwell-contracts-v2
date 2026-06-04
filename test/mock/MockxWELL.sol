// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

/// @notice Mock implementation of xWELL for testing VotingPowerAggregator
/// @dev Simplified mock that only implements voting-related functions
contract MockxWELL {
    /// @notice Mapping from account to current votes
    mapping(address => uint256) private votes;

    /// @notice Mapping from account to timestamp to past votes
    mapping(address => mapping(uint256 => uint256)) private pastVotes;

    /// @notice Set the current votes for an account
    /// @param account The account to set votes for
    /// @param amount The number of votes
    function setVotes(address account, uint256 amount) external {
        votes[account] = amount;
    }

    /// @notice Set the past votes for an account at a specific timestamp
    /// @param account The account to set votes for
    /// @param timestamp The timestamp
    /// @param amount The number of votes
    function setPastVotes(
        address account,
        uint256 timestamp,
        uint256 amount
    ) external {
        pastVotes[account][timestamp] = amount;
    }

    /// @notice Get the current votes for an account
    /// @param account The account to get votes for
    /// @return The number of votes
    function getVotes(address account) external view returns (uint256) {
        return votes[account];
    }

    /// @notice Get the past votes for an account at a specific timestamp
    /// @param account The account to get votes for
    /// @param timestamp The timestamp
    /// @return The number of votes
    function getPastVotes(
        address account,
        uint256 timestamp
    ) external view returns (uint256) {
        return pastVotes[account][timestamp];
    }
}
