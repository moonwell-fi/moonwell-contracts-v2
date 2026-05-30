// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {SnapshotInterface} from "./SnapshotInterface.sol";
import {IVotingPowerAggregator} from "./IVotingPowerAggregator.sol";

contract VotingPowerAggregator is
    Initializable,
    Ownable2StepUpgradeable,
    IVotingPowerAggregator
{
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice reference to the xWELL token, uses block.timestamp for voting checkpoints
    xWELL public xWell;

    /// @notice all voting sources that implement SnapshotInterface, used to aggregate voting power
    EnumerableSet.AddressSet internal _snapshotSources;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner, address _xWell) external initializer {
        __Ownable2Step_init();

        if (_xWell == address(0)) {
            revert ZeroAddress();
        }
        xWell = xWELL(_xWell);

        _transferOwnership(_owner);
    }

    /// @notice adds a snapshot source to the aggregator
    /// @param source the address of the snapshot source to add
    function addSnapshotSource(address source) external onlyOwner {
        if (source == address(xWell) || source == address(0)) {
            revert InvalidSource();
        }
        if (!_snapshotSources.add(source)) {
            revert EnumerableSetError();
        }
        emit SnapshotSourceAdded(source);
    }

    /// @notice removes a snapshot source from the aggregator
    /// @param source the address of the snapshot source to remove
    function removeSnapshotSource(address source) external onlyOwner {
        if (!_snapshotSources.remove(source)) {
            revert EnumerableSetError();
        }
        emit SnapshotSourceRemoved(source);
    }

    /// @notice checks if a snapshot source is in the aggregator
    /// @param source the address of the snapshot source to check
    function isSnapshotSource(address source) external view returns (bool) {
        return _snapshotSources.contains(source);
    }

    /// @notice total voting power for an address at a historical timestamp
    /// @dev a reverting snapshot source contributes 0 votes so it cannot deadlock governance
    function getVotes(
        address account,
        uint256 timestamp
    ) external view returns (uint256) {
        uint256 totalVotes = 0;
        address[] memory sources = _snapshotSources.values();

        for (uint256 i = 0; i < sources.length; ) {
            try
                SnapshotInterface(sources[i]).getPriorVotes(account, timestamp)
            returns (uint256 sourceVotes) {
                totalVotes += sourceVotes;
            } catch {}
            unchecked {
                i++;
            }
        }

        totalVotes += _getCustomPastVotes(account, timestamp);

        return totalVotes;
    }

    /// @notice current voting power for an address across xWell + snapshot sources
    /// @dev a reverting snapshot source contributes 0 votes so it cannot deadlock governance
    function getCurrentVotes(address account) external view returns (uint256) {
        uint256 totalVotes = 0;
        address[] memory sources = _snapshotSources.values();

        for (uint256 i = 0; i < sources.length; ) {
            try SnapshotInterface(sources[i]).getCurrentVotes(account) returns (
                uint256 sourceVotes
            ) {
                totalVotes += sourceVotes;
            } catch {}
            unchecked {
                i++;
            }
        }

        totalVotes += _getCustomVotes(account);

        return totalVotes;
    }

    /// @notice returns the custom votes for an address
    /// @param account the address of the account to check
    function _getCustomVotes(address account) private view returns (uint256) {
        return xWell.getVotes(account);
    }

    /// @notice returns the custom past votes for an address
    /// @param account the address of the account to check
    /// @param timestamp the timestamp to check the votes at
    function _getCustomPastVotes(
        address account,
        uint256 timestamp
    ) private view returns (uint256) {
        return xWell.getPastVotes(account, timestamp);
    }
}
