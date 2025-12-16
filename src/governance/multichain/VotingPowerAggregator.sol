// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {SnapshotInterface} from "./SnapshotInterface.sol";
import {IVotingPowerAggregator} from "./IVotingPowerAggregator.sol";

contract VotingPowerAggregator is
    Initializable,
    OwnableUpgradeable,
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
        __Ownable_init();
        xWell = xWELL(_xWell);

        _transferOwnership(_owner);
    }

    function addSnapshotSource(address source) external onlyOwner {
        if (!_snapshotSources.add(source)) {
            revert EnumerableSetError();
        }
        emit SnapshotSourceAdded(source);
    }

    function removeSnapshotSource(address source) external onlyOwner {
        if (!_snapshotSources.remove(source)) {
            revert EnumerableSetError();
        }
        emit SnapshotSourceRemoved(source);
    }

    function isSnapshotSource(address source) external view returns (bool) {
        return _snapshotSources.contains(source);
    }

    /// @notice returns the total voting power for an address at a given block number and timestamp
    /// @param account The address of the account to check
    /// @param timestamp The unix timestamp in seconds to check the balance at
    /// @param blockNumber The block number to check the balance at
    function getVotes(
        address account,
        uint256 timestamp,
        uint256 blockNumber
    ) external view returns (uint256) {
        uint256 totalVotes = 0;
        address[] memory sources = _snapshotSources.values();

        for (uint256 i = 0; i < sources.length; ) {
            totalVotes += SnapshotInterface(sources[i]).getPriorVotes(
                account,
                blockNumber
            );
            unchecked {
                i++;
            }
        }

        totalVotes += _getCustomPastVotes(account, blockNumber, timestamp);

        return totalVotes;
    }

    /// @notice returns the current voting power for an address across well, xWell, stkWell and distributor
    /// @param account The address of the account to check
    function getCurrentVotes(address account) external view returns (uint256) {
        uint256 totalVotes = 0;
        address[] memory sources = _snapshotSources.values();

        for (uint256 i = 0; i < sources.length; ) {
            totalVotes += SnapshotInterface(sources[i]).getCurrentVotes(
                account
            );
            unchecked {
                i++;
            }
        }

        totalVotes += _getCustomVotes(account);

        return totalVotes;
    }

    function _getCustomVotes(address account) private view returns (uint256) {
        return xWell.getVotes(account);
    }

    function _getCustomPastVotes(
        address account,
        uint256, // blockNumber
        uint256 timestamp
    ) private view returns (uint256) {
        return xWell.getPastVotes(account, timestamp);
    }
}
