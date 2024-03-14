pragma solidity 0.8.19;

interface IStakedWellUplift {
    function EMISSION_MANAGER() external view returns (address);

    function STAKED_TOKEN() external view returns (address);

    function REWARD_TOKEN() external view returns (address);

    function REWARDS_VAULT() external view returns (address);

    function UNSTAKE_WINDOW() external view returns (uint256);

    function COOLDOWN_SECONDS() external view returns (uint256);

    function DISTRIBUTION_END() external view returns (uint256);

    function _governance() external view returns (address);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function stake(address, uint256) external;

    function stakerRewardsToClaim(address) external view returns (uint256);

    function claimRewards(address, uint256) external;

    function getTotalRewardsBalance(address) external view returns (uint256);

    function assets(address) external view returns (uint128, uint128, uint256);

    function configureAsset(
        uint128 emissionsPerSecond,
        address underlyingAsset
    ) external;
}
