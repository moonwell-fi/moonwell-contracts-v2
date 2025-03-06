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
    address public user2;
    address public rewardDistributorA;
    address public rewardDistributorB;

    // Constants
    uint256 public constant INITIAL_STAKE_AMOUNT = 100 ether;
    uint256 public constant REWARD_AMOUNT = 1000 ether;
    uint256 public constant REWARDS_DURATION = 7 days;

    // Events for logging test results
    event LogAssertEq(bool passed, string message);
    event LogAssertEqUint(uint256 a, uint256 b, string message);
    event LogAssertGt(bool passed, string message);
    event LogAssertLt(bool passed, string message);
    event LogAssertTrue(bool passed, string message);
    event LogAssertFalse(bool passed, string message);

    address public vm = address(uint160(uint256(keccak256("hevm cheat code"))));

    constructor() public {
        // Set up addresses
        owner = address(this);
        user = address(0x1);
        user2 = address(0x2);
        rewardDistributorA = address(0x3);
        rewardDistributorB = address(0x4);

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
        prank(rewardDistributorA);
        rewardTokenA.approve(address(multiRewards), REWARD_AMOUNT);

        prank(rewardDistributorB);
        rewardTokenB.approve(address(multiRewards), REWARD_AMOUNT);
    }

    // ------------------------------------------------------------------------------------------------------
    // ------------------------------------------------------------------------------------------------------
    // Simple testing utilities since forge-std minimum solidity version is 0.6.20 and MultiRewards is 0.5.17
    // ------------------------------------------------------------------------------------------------------
    // ------------------------------------------------------------------------------------------------------

    function prank(address sender) internal {
        (bool success, ) = vm.call(
            abi.encodeWithSignature("prank(address)", sender)
        );
        require(success, "call to prank failed");
    }

    function warp(uint256 timestamp) internal {
        (bool success, ) = vm.call(
            abi.encodeWithSignature("warp(uint256)", timestamp)
        );
        require(success, "call to warp failed");
    }

    function assertEq(uint256 a, uint256 b, string memory message) internal {
        emit LogAssertEqUint(a, b, message);
        require(a == b, message);
    }

    function assertEq(address a, address b, string memory message) internal {
        emit LogAssertEq(a == b, message);
        require(a == b, message);
    }

    function assertApproxEq(
        uint256 a,
        uint256 b,
        uint256 tolerance,
        string memory message
    ) internal pure {
        bool withinTolerance = (a >= b ? a - b : b - a) <= tolerance;
        require(withinTolerance, message);
    }

    // Test function
    function testStakeAndClaimNewRewardStream() public {
        // 1. User stakes tokens
        prank(user);
        stakingToken.approve(address(multiRewards), INITIAL_STAKE_AMOUNT);

        // Check initial state
        assertEq(
            multiRewards.totalSupply(),
            0,
            "Initial total supply should be 0"
        );
        assertEq(
            multiRewards.balanceOf(user),
            0,
            "Initial user balance should be 0"
        );
        assertEq(
            stakingToken.balanceOf(user),
            INITIAL_STAKE_AMOUNT,
            "User should have initial tokens"
        );

        // Perform stake
        prank(user);
        multiRewards.stake(INITIAL_STAKE_AMOUNT);

        // Check state after staking
        assertEq(
            multiRewards.totalSupply(),
            INITIAL_STAKE_AMOUNT,
            "Total supply should equal staked amount"
        );
        assertEq(
            multiRewards.balanceOf(user),
            INITIAL_STAKE_AMOUNT,
            "User balance should equal staked amount"
        );
        assertEq(
            stakingToken.balanceOf(user),
            0,
            "User should have 0 tokens after staking"
        );
        assertEq(
            stakingToken.balanceOf(address(multiRewards)),
            INITIAL_STAKE_AMOUNT,
            "Contract should have staked tokens"
        );

        // 2. Notify reward amount for first reward token
        prank(rewardDistributorA);
        multiRewards.notifyRewardAmount(address(rewardTokenA), REWARD_AMOUNT);

        assertEq(
            rewardTokenA.balanceOf(address(multiRewards)),
            REWARD_AMOUNT,
            "reward token balance multi rewards incorrect token a"
        );
        // Check reward state after notification
        (
            address rewardsDistributorA,
            uint256 rewardsDurationA,
            uint256 periodFinishA,
            uint256 rewardRateA,
            uint256 lastUpdateTimeA,

        ) = multiRewards.rewardData(address(rewardTokenA));

        assertEq(
            rewardsDistributorA,
            rewardDistributorA,
            "Rewards distributor should be set correctly"
        );
        assertEq(
            rewardsDurationA,
            REWARDS_DURATION,
            "Rewards duration should be set correctly"
        );
        assertEq(
            periodFinishA,
            block.timestamp + REWARDS_DURATION,
            "Period finish should be set correctly"
        );
        assertEq(
            rewardRateA,
            REWARD_AMOUNT / REWARDS_DURATION,
            "Reward rate should be set correctly"
        );
        assertEq(
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
        assertEq(
            rewardsDistributorB,
            rewardDistributorB,
            "New rewards distributor should be set correctly"
        );
        assertEq(
            rewardsDurationB,
            REWARDS_DURATION,
            "New rewards duration should be set correctly"
        );

        // 4. Notify reward amount for the new reward token
        prank(rewardDistributorB);
        multiRewards.notifyRewardAmount(address(rewardTokenB), REWARD_AMOUNT);

        assertEq(
            rewardTokenB.balanceOf(address(multiRewards)),
            REWARD_AMOUNT,
            "reward token balance multi rewards incorrect token b"
        );

        // Check reward state after notification
        (
            ,
            ,
            uint256 periodFinishB,
            uint256 rewardRateB,
            uint256 lastUpdateTimeB,

        ) = multiRewards.rewardData(address(rewardTokenB));

        assertEq(
            periodFinishB,
            block.timestamp + REWARDS_DURATION,
            "Period finish should be set correctly for token B"
        );
        assertEq(
            rewardRateB,
            REWARD_AMOUNT / REWARDS_DURATION,
            "Reward rate should be set correctly for token B"
        );
        assertEq(
            lastUpdateTimeB,
            block.timestamp,
            "Last update time should be set correctly for token B"
        );

        // 5. Fast forward time to accrue rewards (half the duration)
        warp(block.timestamp + REWARDS_DURATION / 2);

        // 6. Check earned rewards
        uint256 earnedA = multiRewards.earned(user, address(rewardTokenA));
        uint256 earnedB = multiRewards.earned(user, address(rewardTokenB));

        // Should have earned approximately half the rewards (slight precision loss is expected)
        uint256 expectedRewardA = REWARD_AMOUNT / 2;
        uint256 expectedRewardB = REWARD_AMOUNT / 2;
        uint256 tolerance = REWARD_AMOUNT / 10000; // 0.01% tolerance

        assertApproxEq(
            earnedA,
            expectedRewardA,
            tolerance,
            "Should have earned ~half of reward A"
        );
        assertApproxEq(
            earnedB,
            expectedRewardB,
            tolerance,
            "Should have earned ~half of reward B"
        );

        // 7. User claims rewards
        uint256 userRewardBalanceA_Before = rewardTokenA.balanceOf(user);
        uint256 userRewardBalanceB_Before = rewardTokenB.balanceOf(user);

        prank(user);
        multiRewards.getReward();

        // 8. Check state after claiming rewards
        uint256 userRewardBalanceA_After = rewardTokenA.balanceOf(user);
        uint256 userRewardBalanceB_After = rewardTokenB.balanceOf(user);

        // Verify user received rewards
        assertEq(
            userRewardBalanceA_After - userRewardBalanceA_Before,
            earnedA,
            "User should have received earned rewards for token A"
        );
        assertEq(
            userRewardBalanceB_After - userRewardBalanceB_Before,
            earnedB,
            "User should have received earned rewards for token B"
        );

        // Verify rewards state was updated
        assertEq(
            multiRewards.rewards(user, address(rewardTokenA)),
            0,
            "User rewards for token A should be reset to 0"
        );
        assertEq(
            multiRewards.rewards(user, address(rewardTokenB)),
            0,
            "User rewards for token B should be reset to 0"
        );

        // 9. Fast forward to the end of the reward period
        warp(block.timestamp + REWARDS_DURATION / 2);

        // 10. User claims remaining rewards
        userRewardBalanceA_Before = rewardTokenA.balanceOf(user);
        userRewardBalanceB_Before = rewardTokenB.balanceOf(user);

        prank(user);
        multiRewards.getReward();

        userRewardBalanceA_After = rewardTokenA.balanceOf(user);
        userRewardBalanceB_After = rewardTokenB.balanceOf(user);

        // Verify user received remaining rewards
        uint256 remainingRewardsA = userRewardBalanceA_After -
            userRewardBalanceA_Before;
        uint256 remainingRewardsB = userRewardBalanceB_After -
            userRewardBalanceB_Before;

        // Should have received the remaining ~half of rewards
        assertApproxEq(
            remainingRewardsA,
            expectedRewardA,
            tolerance,
            "Should have received remaining rewards for token A"
        );
        assertApproxEq(
            remainingRewardsB,
            expectedRewardB,
            tolerance,
            "Should have received remaining rewards for token B"
        );

        // 11. Verify total rewards received
        uint256 totalRewardsA = userRewardBalanceA_After;
        uint256 totalRewardsB = userRewardBalanceB_After;

        // Should have received approximately all rewards
        assertApproxEq(
            totalRewardsA,
            REWARD_AMOUNT,
            tolerance,
            "Should have received ~all rewards for token A"
        );
        assertApproxEq(
            totalRewardsB,
            REWARD_AMOUNT,
            tolerance,
            "Should have received ~all rewards for token B"
        );
    }

    // Define structs to group related variables and reduce stack usage
    struct UserStakeInfo {
        uint256 stakeAmount;
        uint256 expectedReward;
    }

    struct RewardBalances {
        uint256 tokenA_Before;
        uint256 tokenA_After;
        uint256 tokenB_Before;
        uint256 tokenB_After;
    }

    struct RewardAmounts {
        uint256 earnedA;
        uint256 earnedB;
        uint256 receivedA;
        uint256 receivedB;
        uint256 remainingA;
        uint256 remainingB;
        uint256 totalA;
        uint256 totalB;
    }

    // Test function with two users staking
    function testMultipleUsersStakeAndClaimNewRewardStream() public {
        // Constants for this test
        uint256 tolerance = REWARD_AMOUNT / 10000; // 0.01% tolerance

        // Use memory structs to group related variables
        UserStakeInfo memory user1Info = UserStakeInfo({
            stakeAmount: 75 ether,
            expectedReward: 0 // Will set this later
        });

        UserStakeInfo memory user2Info = UserStakeInfo({
            stakeAmount: 25 ether,
            expectedReward: 0 // Will set this later
        });

        // Setup phase - stake tokens
        {
            uint256 totalStakeAmount = user1Info.stakeAmount +
                user2Info.stakeAmount;

            // Mint tokens to users
            stakingToken.mint(user, user1Info.stakeAmount);
            stakingToken.mint(user2, user2Info.stakeAmount);

            // Check initial state
            assertEq(
                multiRewards.totalSupply(),
                0,
                "Initial total supply should be 0"
            );
            assertEq(
                multiRewards.balanceOf(user),
                0,
                "Initial user1 balance should be 0"
            );
            assertEq(
                multiRewards.balanceOf(user2),
                0,
                "Initial user2 balance should be 0"
            );
            assertEq(
                stakingToken.balanceOf(user),
                user1Info.stakeAmount + INITIAL_STAKE_AMOUNT,
                "User1 should have initial tokens"
            );
            assertEq(
                stakingToken.balanceOf(user2),
                user2Info.stakeAmount,
                "User2 should have initial tokens"
            );

            // 1. First user stakes tokens
            prank(user);
            stakingToken.approve(address(multiRewards), user1Info.stakeAmount);
            prank(user);
            multiRewards.stake(user1Info.stakeAmount);

            // Check state after first user staking
            assertEq(
                multiRewards.totalSupply(),
                user1Info.stakeAmount,
                "Total supply should equal user1 staked amount"
            );
            assertEq(
                multiRewards.balanceOf(user),
                user1Info.stakeAmount,
                "User1 balance should equal staked amount"
            );
            assertEq(
                stakingToken.balanceOf(user),
                INITIAL_STAKE_AMOUNT,
                "User1 should have INITIAL_STAKE_AMOUNT after staking"
            );
            assertEq(
                stakingToken.balanceOf(address(multiRewards)),
                user1Info.stakeAmount,
                "Contract should have user1 staked tokens"
            );

            // 2. Second user stakes tokens
            prank(user2);
            stakingToken.approve(address(multiRewards), user2Info.stakeAmount);
            prank(user2);
            multiRewards.stake(user2Info.stakeAmount);

            // Check state after second user staking
            assertEq(
                multiRewards.totalSupply(),
                totalStakeAmount,
                "Total supply should equal total staked amount"
            );
            assertEq(
                multiRewards.balanceOf(user2),
                user2Info.stakeAmount,
                "User2 balance should equal staked amount"
            );
            assertEq(
                stakingToken.balanceOf(user2),
                0,
                "User2 should have 0 tokens after staking"
            );
            assertEq(
                stakingToken.balanceOf(address(multiRewards)),
                totalStakeAmount,
                "Contract should have total staked tokens"
            );
        }

        // 3. Notify reward amount for first reward token
        prank(rewardDistributorA);
        multiRewards.notifyRewardAmount(address(rewardTokenA), REWARD_AMOUNT);

        // Check reward state after notification
        {
            address rewardsDistributorA;
            uint256 rewardsDurationA;
            uint256 periodFinishA;
            uint256 rewardRateA;
            uint256 lastUpdateTimeA;

            (
                rewardsDistributorA,
                rewardsDurationA,
                periodFinishA,
                rewardRateA,
                lastUpdateTimeA,

            ) = multiRewards.rewardData(address(rewardTokenA));

            assertEq(
                rewardsDistributorA,
                rewardDistributorA,
                "Rewards distributor should be set correctly"
            );
            assertEq(
                rewardsDurationA,
                REWARDS_DURATION,
                "Rewards duration should be set correctly"
            );
            assertEq(
                periodFinishA,
                block.timestamp + REWARDS_DURATION,
                "Period finish should be set correctly"
            );
            assertEq(
                rewardRateA,
                REWARD_AMOUNT / REWARDS_DURATION,
                "Reward rate should be set correctly"
            );
            assertEq(
                lastUpdateTimeA,
                block.timestamp,
                "Last update time should be set correctly"
            );
        }

        // 4. Add a new reward token AFTER users have staked
        multiRewards.addReward(
            address(rewardTokenB),
            rewardDistributorB,
            REWARDS_DURATION
        );

        // Check reward token was added correctly
        {
            address rewardsDistributorB;
            uint256 rewardsDurationB;

            (rewardsDistributorB, rewardsDurationB, , , , ) = multiRewards
                .rewardData(address(rewardTokenB));

            assertEq(
                rewardsDistributorB,
                rewardDistributorB,
                "New rewards distributor should be set correctly"
            );
            assertEq(
                rewardsDurationB,
                REWARDS_DURATION,
                "New rewards duration should be set correctly"
            );
        }

        // 5. Notify reward amount for the new reward token
        prank(rewardDistributorB);
        multiRewards.notifyRewardAmount(address(rewardTokenB), REWARD_AMOUNT);

        // Check reward state after notification
        {
            uint256 periodFinishB;
            uint256 rewardRateB;
            uint256 lastUpdateTimeB;

            (, , periodFinishB, rewardRateB, lastUpdateTimeB, ) = multiRewards
                .rewardData(address(rewardTokenB));

            assertEq(
                periodFinishB,
                block.timestamp + REWARDS_DURATION,
                "Period finish should be set correctly for token B"
            );
            assertEq(
                rewardRateB,
                REWARD_AMOUNT / REWARDS_DURATION,
                "Reward rate should be set correctly for token B"
            );
            assertEq(
                lastUpdateTimeB,
                block.timestamp,
                "Last update time should be set correctly for token B"
            );
        }

        // 6. Fast forward time to accrue rewards (half the duration)
        warp(block.timestamp + REWARDS_DURATION / 2);

        // 7. Check earned rewards for both users
        RewardAmounts memory user1Rewards;
        RewardAmounts memory user2Rewards;

        user1Rewards.earnedA = multiRewards.earned(user, address(rewardTokenA));
        user1Rewards.earnedB = multiRewards.earned(user, address(rewardTokenB));
        user2Rewards.earnedA = multiRewards.earned(
            user2,
            address(rewardTokenA)
        );
        user2Rewards.earnedB = multiRewards.earned(
            user2,
            address(rewardTokenB)
        );

        // Calculate expected rewards based on stake proportions
        // User1 has 75% of the stake, User2 has 25%
        user1Info.expectedReward = ((REWARD_AMOUNT / 2) * 75) / 100;
        user2Info.expectedReward = ((REWARD_AMOUNT / 2) * 25) / 100;

        // Verify earned rewards are proportional to stake
        assertApproxEq(
            user1Rewards.earnedA,
            user1Info.expectedReward,
            tolerance,
            "User1 should have earned ~75% of half reward A"
        );
        assertApproxEq(
            user1Rewards.earnedB,
            user1Info.expectedReward,
            tolerance,
            "User1 should have earned ~75% of half reward B"
        );
        assertApproxEq(
            user2Rewards.earnedA,
            user2Info.expectedReward,
            tolerance,
            "User2 should have earned ~25% of half reward A"
        );
        assertApproxEq(
            user2Rewards.earnedB,
            user2Info.expectedReward,
            tolerance,
            "User2 should have earned ~25% of half reward B"
        );

        // 8. Users claim rewards
        {
            // User1 claims
            RewardBalances memory user1Balances;
            user1Balances.tokenA_Before = rewardTokenA.balanceOf(user);
            user1Balances.tokenB_Before = rewardTokenB.balanceOf(user);

            prank(user);
            multiRewards.getReward();

            user1Balances.tokenA_After = rewardTokenA.balanceOf(user);
            user1Balances.tokenB_After = rewardTokenB.balanceOf(user);

            // User2 claims
            RewardBalances memory user2Balances;
            user2Balances.tokenA_Before = rewardTokenA.balanceOf(user2);
            user2Balances.tokenB_Before = rewardTokenB.balanceOf(user2);

            prank(user2);
            multiRewards.getReward();

            user2Balances.tokenA_After = rewardTokenA.balanceOf(user2);
            user2Balances.tokenB_After = rewardTokenB.balanceOf(user2);

            // 9. Verify users received correct rewards
            user1Rewards.receivedA =
                user1Balances.tokenA_After -
                user1Balances.tokenA_Before;
            user1Rewards.receivedB =
                user1Balances.tokenB_After -
                user1Balances.tokenB_Before;
            user2Rewards.receivedA =
                user2Balances.tokenA_After -
                user2Balances.tokenA_Before;
            user2Rewards.receivedB =
                user2Balances.tokenB_After -
                user2Balances.tokenB_Before;

            assertEq(
                user1Rewards.receivedA,
                user1Rewards.earnedA,
                "User1 should have received earned rewards for token A"
            );
            assertEq(
                user1Rewards.receivedB,
                user1Rewards.earnedB,
                "User1 should have received earned rewards for token B"
            );
            assertEq(
                user2Rewards.receivedA,
                user2Rewards.earnedA,
                "User2 should have received earned rewards for token A"
            );
            assertEq(
                user2Rewards.receivedB,
                user2Rewards.earnedB,
                "User2 should have received earned rewards for token B"
            );

            // Verify rewards state was updated
            assertEq(
                multiRewards.rewards(user, address(rewardTokenA)),
                0,
                "User1 rewards for token A should be reset to 0"
            );
            assertEq(
                multiRewards.rewards(user, address(rewardTokenB)),
                0,
                "User1 rewards for token B should be reset to 0"
            );
            assertEq(
                multiRewards.rewards(user2, address(rewardTokenA)),
                0,
                "User2 rewards for token A should be reset to 0"
            );
            assertEq(
                multiRewards.rewards(user2, address(rewardTokenB)),
                0,
                "User2 rewards for token B should be reset to 0"
            );
        }

        // 10. Fast forward to the end of the reward period
        warp(block.timestamp + REWARDS_DURATION / 2);

        // 11. Users claim remaining rewards
        {
            // User1 claims
            RewardBalances memory user1Balances;
            user1Balances.tokenA_Before = rewardTokenA.balanceOf(user);
            user1Balances.tokenB_Before = rewardTokenB.balanceOf(user);

            prank(user);
            multiRewards.getReward();

            user1Balances.tokenA_After = rewardTokenA.balanceOf(user);
            user1Balances.tokenB_After = rewardTokenB.balanceOf(user);

            // User2 claims
            RewardBalances memory user2Balances;
            user2Balances.tokenA_Before = rewardTokenA.balanceOf(user2);
            user2Balances.tokenB_Before = rewardTokenB.balanceOf(user2);

            prank(user2);
            multiRewards.getReward();

            user2Balances.tokenA_After = rewardTokenA.balanceOf(user2);
            user2Balances.tokenB_After = rewardTokenB.balanceOf(user2);

            // 12. Verify users received remaining rewards
            user1Rewards.remainingA =
                user1Balances.tokenA_After -
                user1Balances.tokenA_Before;
            user1Rewards.remainingB =
                user1Balances.tokenB_After -
                user1Balances.tokenB_Before;
            user2Rewards.remainingA =
                user2Balances.tokenA_After -
                user2Balances.tokenA_Before;
            user2Rewards.remainingB =
                user2Balances.tokenB_After -
                user2Balances.tokenB_Before;

            assertApproxEq(
                user1Rewards.remainingA,
                user1Info.expectedReward,
                tolerance,
                "User1 should have received remaining rewards for token A"
            );
            assertApproxEq(
                user1Rewards.remainingB,
                user1Info.expectedReward,
                tolerance,
                "User1 should have received remaining rewards for token B"
            );
            assertApproxEq(
                user2Rewards.remainingA,
                user2Info.expectedReward,
                tolerance,
                "User2 should have received remaining rewards for token A"
            );
            assertApproxEq(
                user2Rewards.remainingB,
                user2Info.expectedReward,
                tolerance,
                "User2 should have received remaining rewards for token B"
            );

            // Store total rewards for verification
            user1Rewards.totalA = user1Balances.tokenA_After;
            user1Rewards.totalB = user1Balances.tokenB_After;
            user2Rewards.totalA = user2Balances.tokenA_After;
            user2Rewards.totalB = user2Balances.tokenB_After;
        }

        // 13. Verify total rewards received by both users
        {
            // User1 should have received ~75% of total rewards
            uint256 expectedUser1TotalA = (REWARD_AMOUNT * 75) / 100;
            uint256 expectedUser1TotalB = (REWARD_AMOUNT * 75) / 100;

            // User2 should have received ~25% of total rewards
            uint256 expectedUser2TotalA = (REWARD_AMOUNT * 25) / 100;
            uint256 expectedUser2TotalB = (REWARD_AMOUNT * 25) / 100;

            assertApproxEq(
                user1Rewards.totalA,
                expectedUser1TotalA,
                tolerance,
                "User1 should have received ~75% of total rewards for token A"
            );
            assertApproxEq(
                user1Rewards.totalB,
                expectedUser1TotalB,
                tolerance,
                "User1 should have received ~75% of total rewards for token B"
            );
            assertApproxEq(
                user2Rewards.totalA,
                expectedUser2TotalA,
                tolerance,
                "User2 should have received ~25% of total rewards for token A"
            );
            assertApproxEq(
                user2Rewards.totalB,
                expectedUser2TotalB,
                tolerance,
                "User2 should have received ~25% of total rewards for token B"
            );
        }

        // 14. Verify that the sum of rewards equals the total rewards
        {
            uint256 totalRewardsDistributedA = user1Rewards.totalA +
                user2Rewards.totalA;
            uint256 totalRewardsDistributedB = user1Rewards.totalB +
                user2Rewards.totalB;

            assertApproxEq(
                totalRewardsDistributedA,
                REWARD_AMOUNT,
                tolerance,
                "Total distributed rewards for token A should equal REWARD_AMOUNT"
            );
            assertApproxEq(
                totalRewardsDistributedB,
                REWARD_AMOUNT,
                tolerance,
                "Total distributed rewards for token B should equal REWARD_AMOUNT"
            );
        }
    }

    // Test function to verify recoverERC20 works for reward tokens
    function testRecoverRewardToken() public {
        // 1. Setup - Add reward token and notify reward amount
        prank(rewardDistributorA);
        multiRewards.notifyRewardAmount(address(rewardTokenA), REWARD_AMOUNT);

        // Verify reward token balance in the contract
        assertEq(
            rewardTokenA.balanceOf(address(multiRewards)),
            REWARD_AMOUNT,
            "Contract should have the reward token amount"
        );

        // 2. Attempt to recover half of the reward tokens
        uint256 amountToRecover = REWARD_AMOUNT / 2;
        uint256 ownerBalanceBefore = rewardTokenA.balanceOf(owner);

        // Call recoverERC20 as the owner
        multiRewards.recoverERC20(address(rewardTokenA), amountToRecover);

        // 3. Verify tokens were successfully transferred to the owner
        uint256 ownerBalanceAfter = rewardTokenA.balanceOf(owner);
        assertEq(
            ownerBalanceAfter - ownerBalanceBefore,
            amountToRecover,
            "Owner should have received the recovered tokens"
        );

        // 4. Verify remaining balance in the contract
        assertEq(
            rewardTokenA.balanceOf(address(multiRewards)),
            REWARD_AMOUNT - amountToRecover,
            "Contract should have the remaining reward tokens"
        );
    }
}
