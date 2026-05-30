// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

interface IVotingPowerAggregator {
    error EnumerableSetError();
    error InvalidSource();
    error ZeroAddress();

    event SnapshotSourceAdded(address source);
    event SnapshotSourceRemoved(address source);

    function addSnapshotSource(address source) external;
    function removeSnapshotSource(address source) external;
    function isSnapshotSource(address source) external view returns (bool);
    function getVotes(
        address account,
        uint256 timestamp
    ) external view returns (uint256);
    function getCurrentVotes(address account) external view returns (uint256);
}
