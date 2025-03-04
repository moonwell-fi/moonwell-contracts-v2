pragma solidity 0.5.17;

import "../../crv-rewards/MultiRewards.sol";

// Simple mock ERC20 token compatible with Solidity 0.5.17
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) public {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) public {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 value) public returns (bool) {
        require(
            balanceOf[msg.sender] >= value,
            "ERC20: transfer amount exceeds balance"
        );
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) public returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public returns (bool) {
        require(
            balanceOf[from] >= value,
            "ERC20: transfer amount exceeds balance"
        );
        require(
            allowance[from][msg.sender] >= value,
            "ERC20: transfer amount exceeds allowance"
        );
        balanceOf[from] -= value;
        balanceOf[to] += value;
        allowance[from][msg.sender] -= value;
        emit Transfer(from, to, value);
        return true;
    }
}

// Simple testing contract that doesn't rely on forge-std
contract MultiRewardsTest {
    // Contracts
    MultiRewards public multiRewards;
    MockERC20 public stakingToken;
    MockERC20 public rewardTokenA;
    MockERC20 public rewardTokenB;

    // Addresses
    address public owner;
    address public user;
    address public rewardDistributorA;
    address public rewardDistributorB;

    // Constants
    uint256 public constant INITIAL_STAKE_AMOUNT = 100 ether;
    uint256 public constant REWARD_AMOUNT = 1000 ether;
    uint256 public constant REWARDS_DURATION = 7 days;

    // Events for logging test results
    event LogAssertEq(bool passed, string message);
    event LogAssertGt(bool passed, string message);
    event LogAssertLt(bool passed, string message);
    event LogAssertTrue(bool passed, string message);
    event LogAssertFalse(bool passed, string message);

    address public vm = address(uint160(uint256(keccak256("hevm cheat code"))));

    constructor() public {
        // Set up addresses
        owner = address(this);
        user = address(0x1);
        rewardDistributorA = address(0x2);
        rewardDistributorB = address(0x3);

        // Deploy mock tokens
        stakingToken = new MockERC20("Staking Token", "STK", 18);
        rewardTokenA = new MockERC20("Reward Token A", "RWDA", 18);
        rewardTokenB = new MockERC20("Reward Token B", "RWDB", 18);

        // Deploy MultiRewards contract
        multiRewards = new MultiRewards(owner, address(stakingToken));

        // Add first reward token
        multiRewards.addReward(
            address(rewardTokenA),
            rewardDistributorA,
            REWARDS_DURATION
        );

        // Mint tokens to user and reward distributors
        stakingToken.mint(user, INITIAL_STAKE_AMOUNT);
        rewardTokenA.mint(rewardDistributorA, REWARD_AMOUNT);
        rewardTokenB.mint(rewardDistributorB, REWARD_AMOUNT);

        // Approve spending of reward tokens by the MultiRewards contract
        _prank(rewardDistributorA);
        rewardTokenA.approve(address(multiRewards), REWARD_AMOUNT);

        _prank(rewardDistributorB);
        rewardTokenB.approve(address(multiRewards), REWARD_AMOUNT);
    }

    // Simple testing utilities since forge-std minimum solidity version is 0.6.20 and MultiRewards is 0.5.17
    function _prank(address sender) internal {
        // This is a no-op in a real contract, but in a test framework it would change the msg.sender
        // For our purposes, we'll just document that this is where we would change the sender
        (bool success, ) = vm.call(
            abi.encodeWithSignature("prank(address)", sender)
        );
        require(success, "call to prank failed");
    }

    function _warp(uint256 timestamp) internal {
        // This is a no-op in a real contract, but in a test framework it would change the block.timestamp
        // For our purposes, we'll just document that this is where we would change the timestamp
        (bool success, ) = vm.call(
            abi.encodeWithSignature("warp(uint256)", timestamp)
        );
        require(success, "call to warp failed");
    }

    function _assertEq(uint256 a, uint256 b, string memory message) internal {
        emit LogAssertEq(a == b, message);
        require(a == b, message);
    }

    function _assertEq(address a, address b, string memory message) internal {
        emit LogAssertEq(a == b, message);
        require(a == b, message);
    }

    function _assertApproxEq(
        uint256 a,
        uint256 b,
        uint256 tolerance,
        string memory message
    ) internal {
        bool withinTolerance = (a >= b ? a - b : b - a) <= tolerance;
        require(withinTolerance, message);
    }

    // Test function
    function testStakeAndClaimNewRewardStream() public {
        // 1. User stakes tokens
        _prank(user);
        stakingToken.approve(address(multiRewards), INITIAL_STAKE_AMOUNT);

        // Check initial state
        _assertEq(
            multiRewards.totalSupply(),
            0,
            "Initial total supply should be 0"
        );
        _assertEq(
            multiRewards.balanceOf(user),
            0,
            "Initial user balance should be 0"
        );
        _assertEq(
            stakingToken.balanceOf(user),
            INITIAL_STAKE_AMOUNT,
            "User should have initial tokens"
        );

        // Perform stake
        _prank(user);
        multiRewards.stake(INITIAL_STAKE_AMOUNT);

        // Check state after staking
        _assertEq(
            multiRewards.totalSupply(),
            INITIAL_STAKE_AMOUNT,
            "Total supply should equal staked amount"
        );
        _assertEq(
            multiRewards.balanceOf(user),
            INITIAL_STAKE_AMOUNT,
            "User balance should equal staked amount"
        );
        _assertEq(
            stakingToken.balanceOf(user),
            0,
            "User should have 0 tokens after staking"
        );
        _assertEq(
            stakingToken.balanceOf(address(multiRewards)),
            INITIAL_STAKE_AMOUNT,
            "Contract should have staked tokens"
        );

        // 2. Notify reward amount for first reward token
        _prank(rewardDistributorA);
        multiRewards.notifyRewardAmount(address(rewardTokenA), REWARD_AMOUNT);

        // Check reward state after notification
        (
            address rewardsDistributorA,
            uint256 rewardsDurationA,
            uint256 periodFinishA,
            uint256 rewardRateA,
            uint256 lastUpdateTimeA,

        ) = multiRewards.rewardData(address(rewardTokenA));

        _assertEq(
            rewardsDistributorA,
            rewardDistributorA,
            "Rewards distributor should be set correctly"
        );
        _assertEq(
            rewardsDurationA,
            REWARDS_DURATION,
            "Rewards duration should be set correctly"
        );
        _assertEq(
            periodFinishA,
            block.timestamp + REWARDS_DURATION,
            "Period finish should be set correctly"
        );
        _assertEq(
            rewardRateA,
            REWARD_AMOUNT / REWARDS_DURATION,
            "Reward rate should be set correctly"
        );
        _assertEq(
            lastUpdateTimeA,
            block.timestamp,
            "Last update time should be set correctly"
        );

        // 3. Add a new reward token AFTER user has staked
        multiRewards.addReward(
            address(rewardTokenB),
            rewardDistributorB,
            REWARDS_DURATION
        );

        // Check reward token was added correctly
        (
            address rewardsDistributorB,
            uint256 rewardsDurationB,
            ,
            ,
            ,

        ) = multiRewards.rewardData(address(rewardTokenB));
        _assertEq(
            rewardsDistributorB,
            rewardDistributorB,
            "New rewards distributor should be set correctly"
        );
        _assertEq(
            rewardsDurationB,
            REWARDS_DURATION,
            "New rewards duration should be set correctly"
        );

        // 4. Notify reward amount for the new reward token
        _prank(rewardDistributorB);
        multiRewards.notifyRewardAmount(address(rewardTokenB), REWARD_AMOUNT);

        // Check reward state after notification
        (
            ,
            ,
            uint256 periodFinishB,
            uint256 rewardRateB,
            uint256 lastUpdateTimeB,

        ) = multiRewards.rewardData(address(rewardTokenB));

        _assertEq(
            periodFinishB,
            block.timestamp + REWARDS_DURATION,
            "Period finish should be set correctly for token B"
        );
        _assertEq(
            rewardRateB,
            REWARD_AMOUNT / REWARDS_DURATION,
            "Reward rate should be set correctly for token B"
        );
        _assertEq(
            lastUpdateTimeB,
            block.timestamp,
            "Last update time should be set correctly for token B"
        );

        // 5. Fast forward time to accrue rewards (half the duration)
        _warp(block.timestamp + REWARDS_DURATION / 2);

        // 6. Check earned rewards
        uint256 earnedA = multiRewards.earned(user, address(rewardTokenA));
        uint256 earnedB = multiRewards.earned(user, address(rewardTokenB));

        // Should have earned approximately half the rewards (slight precision loss is expected)
        uint256 expectedRewardA = REWARD_AMOUNT / 2;
        uint256 expectedRewardB = REWARD_AMOUNT / 2;
        uint256 tolerance = REWARD_AMOUNT / 10000; // 0.01% tolerance

        _assertApproxEq(
            earnedA,
            expectedRewardA,
            tolerance,
            "Should have earned ~half of reward A"
        );
        _assertApproxEq(
            earnedB,
            expectedRewardB,
            tolerance,
            "Should have earned ~half of reward B"
        );

        // 7. User claims rewards
        uint256 userRewardBalanceA_Before = rewardTokenA.balanceOf(user);
        uint256 userRewardBalanceB_Before = rewardTokenB.balanceOf(user);

        _prank(user);
        multiRewards.getReward();

        // 8. Check state after claiming rewards
        uint256 userRewardBalanceA_After = rewardTokenA.balanceOf(user);
        uint256 userRewardBalanceB_After = rewardTokenB.balanceOf(user);

        // Verify user received rewards
        _assertEq(
            userRewardBalanceA_After - userRewardBalanceA_Before,
            earnedA,
            "User should have received earned rewards for token A"
        );
        _assertEq(
            userRewardBalanceB_After - userRewardBalanceB_Before,
            earnedB,
            "User should have received earned rewards for token B"
        );

        // Verify rewards state was updated
        _assertEq(
            multiRewards.rewards(user, address(rewardTokenA)),
            0,
            "User rewards for token A should be reset to 0"
        );
        _assertEq(
            multiRewards.rewards(user, address(rewardTokenB)),
            0,
            "User rewards for token B should be reset to 0"
        );

        // 9. Fast forward to the end of the reward period
        _warp(block.timestamp + REWARDS_DURATION / 2);

        // 10. User claims remaining rewards
        userRewardBalanceA_Before = rewardTokenA.balanceOf(user);
        userRewardBalanceB_Before = rewardTokenB.balanceOf(user);

        _prank(user);
        multiRewards.getReward();

        userRewardBalanceA_After = rewardTokenA.balanceOf(user);
        userRewardBalanceB_After = rewardTokenB.balanceOf(user);

        // Verify user received remaining rewards
        uint256 remainingRewardsA = userRewardBalanceA_After -
            userRewardBalanceA_Before;
        uint256 remainingRewardsB = userRewardBalanceB_After -
            userRewardBalanceB_Before;

        // Should have received the remaining ~half of rewards
        _assertApproxEq(
            remainingRewardsA,
            expectedRewardA,
            tolerance,
            "Should have received remaining rewards for token A"
        );
        _assertApproxEq(
            remainingRewardsB,
            expectedRewardB,
            tolerance,
            "Should have received remaining rewards for token B"
        );

        // 11. Verify total rewards received
        uint256 totalRewardsA = userRewardBalanceA_After;
        uint256 totalRewardsB = userRewardBalanceB_After;

        // Should have received approximately all rewards
        _assertApproxEq(
            totalRewardsA,
            REWARD_AMOUNT,
            tolerance,
            "Should have received ~all rewards for token A"
        );
        _assertApproxEq(
            totalRewardsB,
            REWARD_AMOUNT,
            tolerance,
            "Should have received ~all rewards for token B"
        );
    }
}
