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

    function getPriorVotes(
        address account,
        uint256 blockNumber
    ) external view returns (uint256);

    function redeem(address to, uint256 amount) external;

    function mint(address to, uint256 amount) external;

    function totalSupply() external view returns (uint256);

    function claimRewards(address to, uint256 amount) external;

    // from IDistributionManager
    function configureAsset(
        uint128 emissionPerSecond,
        address underlyingAsset
    ) external;
}
