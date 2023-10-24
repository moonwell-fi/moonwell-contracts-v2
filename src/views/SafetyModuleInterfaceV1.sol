// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

interface SafetyModuleInterfaceV1 {
    function getPriorVotes(
        address account,
        uint blockNumber
    ) external view returns (uint);

    function stakersCooldowns(
        address recipient
    ) external view returns (uint256);

    function stakerRewardsToClaim(
        address recipient
    ) external view returns (uint256);

    function getUserAssetData(
        address user,
        address asset
    ) external view returns (uint256);

    function balanceOf(address user) external view returns (uint256);

    function getTotalRewardsBalance(
        address staker
    ) external view returns (uint);

    function STAKED_TOKEN() external view returns (address);

    function REWARD_TOKEN() external view returns (address);

    function COOLDOWN_SECONDS() external view returns (uint);

    function UNSTAKE_WINDOW() external view returns (uint);
}
