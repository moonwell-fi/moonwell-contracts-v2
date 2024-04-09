pragma solidity 0.8.19;

interface IStakedWell {
    function initialize(
        address _stakedToken,
        address _rewardToken,
        uint256 _cooldownPeriod,
        uint256 _unstakePeriod,
        address _rewardsVault,
        address _emissionManager,
        uint128 _distributionDuration,
        address _governance
    ) external;

    function stake(address to, uint256 amount) external;

    function balanceOf(address account) external view returns (uint256);

    function stakersCooldowns(address account) external view returns (uint256);

    function UNSTAKE_WINDOW() external view returns (uint256);

    function COOLDOWN_SECONDS() external view returns (uint256);

    function EMISSION_MANAGER() external view returns (address);

    function getPriorVotes(
        address account,
        uint256 blockNumber
    ) external view returns (uint256);

    function redeem(address to, uint256 amount) external;

    function mint(address to, uint256 amount) external;

    function totalSupply() external view returns (uint256);

    function claimRewards(address to, uint256 amount) external;

    function cooldown() external;

    // from IDistributionManager
    function configureAsset(
        uint128 emissionPerSecond,
        address underlyingAsset
    ) external;

    function configureAssets(
        uint128[] memory emissionPerSecond,
        uint256[] memory totalStaked,
        address[] memory underlyingAsset
    ) external;

    /// @notice update the unstake window
    /// @param unstakeWindow the new unstake window
    function setUnstakeWindow(uint256 unstakeWindow) external;

    /// @notice update the cooldown seconds
    /// @param cooldownSeconds the new cooldown seconds
    function setCoolDownSeconds(uint256 cooldownSeconds) external;
}
