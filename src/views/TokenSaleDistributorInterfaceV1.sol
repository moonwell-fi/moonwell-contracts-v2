// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

interface TokenSaleDistributorInterfaceV1 {
    function getPriorVotes(address account, uint256 blockNumber) external view returns (uint256);

    function totalAllocated(address recipient) external view returns (uint256);

    function totalClaimed(address recipient) external view returns (uint256);

    function delegates(address recipient) external view returns (address);

    function delegate(address delegatee) external;

    function admin() external view returns (address);

    function setAllocations(
        address[] memory recipients,
        bool[] memory isLinear,
        uint256[] memory epochs,
        uint256[] memory vestingDurations,
        uint256[] memory cliffs,
        uint256[] memory cliffPercentages,
        uint256[] memory amounts
    ) external;
}
