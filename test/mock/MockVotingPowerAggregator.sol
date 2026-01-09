pragma solidity 0.8.19;

import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {VotingPowerAggregator} from "@protocol/governance/multichain/VotingPowerAggregator.sol";

/// @notice Mock VotingPowerAggregator for testing purposes
/// @dev Inherits from VotingPowerAggregator but can be extended with additional test helpers if needed
contract MockVotingPowerAggregator is VotingPowerAggregator {
    using EnumerableSet for EnumerableSet.AddressSet;
    /// @notice Helper function to check if a source is in the snapshot sources set
    /// @param source The address to check
    /// @return True if the source is in the set
    function hasSnapshotSource(address source) external view returns (bool) {
        return _snapshotSources.contains(source);
    }

    /// @notice Helper function to get all snapshot sources
    /// @return Array of all snapshot source addresses
    function getAllSnapshotSources() external view returns (address[] memory) {
        return _snapshotSources.values();
    }

    /// @notice Helper function to get the number of snapshot sources
    /// @return The count of snapshot sources
    function getSnapshotSourceCount() external view returns (uint256) {
        return _snapshotSources.length();
    }
}
