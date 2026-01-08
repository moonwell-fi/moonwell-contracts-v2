// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {SnapshotInterface} from "@protocol/governance/multichain/SnapshotInterface.sol";

/// @notice Mock implementation of SnapshotInterface for testing
/// @dev Allows setting voting power for specific accounts and timestamps
contract MockSnapshotSource is SnapshotInterface {
    /// @notice Mapping from account to current votes
    mapping(address => uint256) private currentVotes;

    /// @notice Mapping from account to timestamp to prior votes
    mapping(address => mapping(uint256 => uint256)) private priorVotes;

    /// @notice Set the current votes for an account
    /// @param account The account to set votes for
    /// @param votes The number of votes
    function setCurrentVotes(address account, uint256 votes) external {
        currentVotes[account] = votes;
    }

    /// @notice Set the prior votes for an account at a specific timestamp
    /// @param account The account to set votes for
    /// @param timestamp The unix timestamp in seconds
    /// @param votes The number of votes
    function setPriorVotes(
        address account,
        uint256 timestamp,
        uint256 votes
    ) external {
        priorVotes[account][timestamp] = votes;
    }

    /// @notice Gets the current votes balance for `account`
    /// @param account The address to get votes balance
    /// @return The number of current votes for `account`
    function getCurrentVotes(address account) external view returns (uint256) {
        return currentVotes[account];
    }

    /// @notice Determine the prior number of votes for an account as of a timestamp
    /// @param account The address of the account to check
    /// @param timestamp The unix timestamp in seconds to get the vote balance at
    /// @return The number of votes the account had as of the given timestamp
    function getPriorVotes(
        address account,
        uint256 timestamp
    ) external view returns (uint256) {
        return priorVotes[account][timestamp];
    }
}
