pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import "@test/helper/BaseTest.t.sol";

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
}

contract StakedWellUnitTest is BaseTest {
    IStakedWell stakedWell;
    uint256 cooldown;
    uint256 unstakePeriod;
    uint256 amount;
    function setUp() public override {
        super.setUp();
        address stakedWellAddress = deployCode("StakedWell.sol:StakedWell");
        stakedWell = IStakedWell(stakedWellAddress);

        cooldown = 1 days;
        unstakePeriod = 3 days;

        stakedWell.initialize(
            address(xwellProxy),
            address(xwellProxy),
            cooldown,
            unstakePeriod,
            address(this),
            address(this),
            1,
            address(0)
        );

        amount = xwellProxy.MAX_SUPPLY();
        vm.prank(address(xerc20Lockbox));
        xwellProxy.mint(address(this), amount);
    }

    function testStake() public {
        xwellProxy.approve(address(stakedWell), amount);

        // stake
        stakedWell.stake(address(this), amount);
        assertEq(
            stakedWell.balanceOf(address(this)),
            amount,
            "Wrong staked amount"
        );
    }

    function testGetPriorVotes() public {
        testStake();

        uint256 blockTimestamp = block.timestamp;

        vm.warp(block.timestamp + 1);
        assertEq(
            stakedWell.getPriorVotes(address(this), blockTimestamp),
            amount,
            "Wrong prior votes"
        );
    }

    function testRedeem() public {
        testStake();

        vm.warp(block.timestamp + cooldown + 1);
        stakedWell.redeem(address(this), amount);
        assertEq(stakedWell.balanceOf(address(this)), 0, "Wrong staked amount");
    }

    function testRedeemBeforeCooldown() public {
        testStake();

        vm.warp(block.timestamp + cooldown - 1);
        vm.expectRevert("INSUFFICIENT_COOLDOWN");
        stakedWell.redeem(address(this), amount);
    }

    function testRedeemAfterUnstakePeriod() public {
        testStake();

        vm.warp(block.timestamp + cooldown + unstakePeriod + 1);
        vm.expectRevert("UNSTAKE_WINDOW_FINISHED");
        stakedWell.redeem(address(this), amount);
    }
}
