pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import "@test/helper/BaseTest.t.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

contract StakedWellUnitTest is BaseTest, MultichainGovernorDeploy {
    IStakedWell stakedWell;
    uint256 cooldown;
    uint256 unstakePeriod;
    uint256 amount;
    address user;
    // mint amount for vault
    uint256 mintAmount;

    function setUp() public override {
        super.setUp();

        user = address(1);

        address proxyAdmin = address(new ProxyAdmin());

        cooldown = 1 days;
        unstakePeriod = 3 weeks;

        (address stkWellProxy, ) = deployStakedWell(
            address(xwellProxy),
            address(xwellProxy),
            cooldown,
            unstakePeriod,
            address(this), // rewardsVault
            address(this), // emissionManager
            1 days, // distributionDuration
            address(0), // governance
            proxyAdmin // proxyAdmin
        );

        stakedWell = IStakedWell(stkWellProxy);

        // configure asset
        IStakedWell(stkWellProxy).configureAsset(1e18, stkWellProxy);

        amount = 1_000_000_000 * 1e18;

        vm.prank(address(xerc20Lockbox));
        xwellProxy.mint(user, amount);
        vm.prank(user);
        xwellProxy.approve(stkWellProxy, amount);

        mintAmount = cooldown * 1e18;

        vm.prank(address(xerc20Lockbox));

        // vault must have token to distribute on rewards
        xwellProxy.mint(address(this), mintAmount);

        // approve stkWell to spend vault tokens
        xwellProxy.approve(stkWellProxy, mintAmount);
    }

    function testStake() public {
        vm.prank(user);
        stakedWell.stake(user, amount);
        assertEq(stakedWell.balanceOf(user), amount, "Wrong staked amount");
    }

    function testGetPriorVotes() public {
        testStake();

        uint256 blockTimestamp = block.timestamp;

        vm.warp(block.timestamp + 1);
        assertEq(
            stakedWell.getPriorVotes(user, blockTimestamp),
            amount,
            "Wrong prior votes"
        );
    }

    function testRedeem() public {
        testStake();

        vm.warp(block.timestamp + cooldown + 1);
        vm.prank(user);
        stakedWell.redeem(user, amount);
        assertEq(stakedWell.balanceOf(user), 0, "Wrong staked amount");
    }

    function testRedeemBeforeCooldown() public {
        testStake();

        vm.warp(block.timestamp + cooldown - 1);
        vm.expectRevert("INSUFFICIENT_COOLDOWN");

        vm.prank(user);
        stakedWell.redeem(user, amount);
    }

    function testRedeemAfterUnstakePeriod() public {
        testStake();

        vm.warp(block.timestamp + cooldown + unstakePeriod + 1);
        vm.expectRevert("UNSTAKE_WINDOW_FINISHED");
        vm.prank(user);
        stakedWell.redeem(user, amount);
    }

    function testClaimRewards() public {
        testStake();

        vm.warp(block.timestamp + cooldown + 1);

        // user balance before
        uint256 userBalanceBefore = xwellProxy.balanceOf(user);
        uint256 vaultBalanceBefore = xwellProxy.balanceOf(address(this));

        uint256 expectedRewardAmount = cooldown * 1e18;
        vm.prank(user);

        stakedWell.claimRewards(user, type(uint256).max);

        uint256 userBalanceAfter = xwellProxy.balanceOf(user);
        uint256 vaultBalanceAfter = xwellProxy.balanceOf(address(this));

        assertTrue(
            userBalanceBefore + expectedRewardAmount == userBalanceAfter,
            "User balance should increase"
        );
        assertTrue(
            vaultBalanceBefore - expectedRewardAmount == vaultBalanceAfter,
            "Vault balance should decrease"
        );
    }
}
