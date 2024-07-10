// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

interface SafetyModuleInterfaceV1 {
    struct AssetData {
        uint128 emissionPerSecond;
        uint128 lastUpdateTimestamp;
        uint256 index;
    }

    function getPriorVotes(address account, uint256 blockNumber) external view returns (uint256);

    function stakersCooldowns(address recipient) external view returns (uint256);

    function stakerRewardsToClaim(address recipient) external view returns (uint256);

    function getUserAssetData(address user, address asset) external view returns (uint256);

    function balanceOf(address user) external view returns (uint256);

    function getTotalRewardsBalance(address staker) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function STAKED_TOKEN() external view returns (address);

    function REWARD_TOKEN() external view returns (address);

    function COOLDOWN_SECONDS() external view returns (uint256);

    function DISTRIBUTION_END() external view returns (uint256);

    function UNSTAKE_WINDOW() external view returns (uint256);

    function assets(address) external view returns (AssetData memory);
}
