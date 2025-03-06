// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

interface IMultiRewards {
    struct Reward {
        address rewardsDistributor;
        uint256 rewardsDuration;
        uint256 periodFinish;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
    }

    // Events
    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(
        address indexed user,
        address indexed rewardsToken,
        uint256 reward
    );
    event RewardsDurationUpdated(address token, uint256 newDuration);
    event Recovered(address token, uint256 amount);
    event OwnerNominated(address newOwner);
    event OwnerChanged(address oldOwner, address newOwner);
    event PauseChanged(bool isPaused);

    // View functions
    function owner() external view returns (address);
    function nominatedOwner() external view returns (address);
    function stakingToken() external view returns (address);
    function rewardData(
        address
    )
        external
        view
        returns (
            address rewardsDistributor,
            uint256 rewardsDuration,
            uint256 periodFinish,
            uint256 rewardRate,
            uint256 lastUpdateTime,
            uint256 rewardPerTokenStored
        );
    function rewardTokens(uint256) external view returns (address);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function lastTimeRewardApplicable(
        address _rewardsToken
    ) external view returns (uint256);
    function rewardPerToken(
        address _rewardsToken
    ) external view returns (uint256);
    function earned(
        address account,
        address _rewardsToken
    ) external view returns (uint256);
    function getRewardForDuration(
        address _rewardsToken
    ) external view returns (uint256);

    // Mutative functions
    function nominateNewOwner(address _owner) external;
    function acceptOwnership() external;
    function setPaused(bool _paused) external;
    function addReward(
        address _rewardsToken,
        address _rewardsDistributor,
        uint256 _rewardsDuration
    ) external;
    function setRewardsDistributor(
        address _rewardsToken,
        address _rewardsDistributor
    ) external;
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward() external;
    function exit() external;
    function notifyRewardAmount(address _rewardsToken, uint256 reward) external;
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external;
    function setRewardsDuration(
        address _rewardsToken,
        uint256 _rewardsDuration
    ) external;
}
