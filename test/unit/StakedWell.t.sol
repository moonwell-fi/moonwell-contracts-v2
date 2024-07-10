pragma solidity 0.8.19;

import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import "@forge-std/Test.sol";
import "@test/helper/BaseTest.t.sol";

import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {MultichainGovernorDeploy} from "@protocol/governance/multichain/MultichainGovernorDeploy.sol";

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

        (address stkWellProxy,) = deployStakedWell(
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
        uint256 userBalanceBefore = xwellProxy.balanceOf(user);
        uint256 userStkWellBalanceBefore = stakedWell.balanceOf(user);
        uint256 stkWellSupplyBefore = stakedWell.totalSupply();

        vm.prank(user);
        stakedWell.stake(user, amount);
        assertEq(stakedWell.balanceOf(user), amount, "Wrong staked amount");

        uint256 userBalanceAfter = xwellProxy.balanceOf(user);
        uint256 userStkWellBalanceAfter = stakedWell.balanceOf(user);
        uint256 stkWellSupplyAfter = stakedWell.totalSupply();

        assertEq(userBalanceBefore - amount, userBalanceAfter, "Wrong user balance");
        assertEq(userStkWellBalanceBefore + amount, userStkWellBalanceAfter, "Wrong user staked balance");
        assertEq(stkWellSupplyBefore + amount, stkWellSupplyAfter, "Wrong total supply");
    }

    function testConfigureAssetsIncorrectArityFails() public {
        uint128[] memory emissionPerSecond = new uint128[](1);
        uint256[] memory totalStaked = new uint256[](2);
        address[] memory underlyingAsset = new address[](1);

        vm.prank(address(stakedWell.EMISSION_MANAGER()));
        vm.expectRevert("PARAM_LENGTHS");
        stakedWell.configureAssets(emissionPerSecond, totalStaked, underlyingAsset);
    }

    function testConfigureAssetsNonManagerFails() public {
        uint128[] memory emissionPerSecond = new uint128[](1);
        uint256[] memory totalStaked = new uint256[](1);
        address[] memory underlyingAsset = new address[](1);

        vm.prank(address(1));
        vm.expectRevert("ONLY_EMISSION_MANAGER");
        stakedWell.configureAssets(emissionPerSecond, totalStaked, underlyingAsset);
    }

    function testGetPriorVotes() public {
        testStake();

        uint256 blockTimestamp = block.timestamp;

        vm.warp(block.timestamp + 1);
        assertEq(stakedWell.getPriorVotes(user, blockTimestamp), amount, "Wrong prior votes");
    }

    function testRedeem() public {
        testStake();

        uint256 userBalanceBefore = xwellProxy.balanceOf(user);
        uint256 stkWellSupplyBefore = stakedWell.totalSupply();

        vm.warp(block.timestamp + cooldown + 1);
        vm.prank(user);
        stakedWell.redeem(user, amount);

        assertEq(stakedWell.balanceOf(user), 0, "Wrong staked amount");
        assertEq(xwellProxy.balanceOf(user), userBalanceBefore + amount, "Wrong user balance");
        assertEq(stkWellSupplyBefore - amount, stakedWell.totalSupply(), "Wrong total supply");
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

        assertTrue(userBalanceBefore + expectedRewardAmount == userBalanceAfter, "User balance should increase");
        assertTrue(vaultBalanceBefore - expectedRewardAmount == vaultBalanceAfter, "Vault balance should decrease");
    }

    function testSetCoolDownSeconds() public {
        uint256 newCooldown = 0;

        vm.prank(address(stakedWell.EMISSION_MANAGER()));
        stakedWell.setCoolDownSeconds(newCooldown);

        assertEq(stakedWell.COOLDOWN_SECONDS(), newCooldown, "Wrong cooldown");
    }

    function testSetUnstakeWindow() public {
        uint256 newUnstakeWindow = 0;

        vm.prank(address(stakedWell.EMISSION_MANAGER()));
        stakedWell.setUnstakeWindow(newUnstakeWindow);

        assertEq(stakedWell.UNSTAKE_WINDOW(), newUnstakeWindow, "Wrong cooldown");
    }

    function testSetCoolDownSeconds(uint256 newCooldown) public {
        vm.prank(address(stakedWell.EMISSION_MANAGER()));
        stakedWell.setCoolDownSeconds(newCooldown);

        assertEq(stakedWell.COOLDOWN_SECONDS(), newCooldown, "Wrong cooldown");
    }

    function testSetUnstakeWindow(uint256 newUnstakeWindow) public {
        vm.prank(address(stakedWell.EMISSION_MANAGER()));
        stakedWell.setUnstakeWindow(newUnstakeWindow);

        assertEq(stakedWell.UNSTAKE_WINDOW(), newUnstakeWindow, "Wrong cooldown");
    }

    function testStakeSetCooldownToZeroUnstakeImmediately() public {
        testStake();
        testSetCoolDownSeconds();
        testSetUnstakeWindow(1000 days);

        uint256 startingUserxWellBalance = xwellProxy.balanceOf(user);

        vm.startPrank(user);

        stakedWell.cooldown();

        /// start the cooldown

        vm.warp(block.timestamp + 1);

        /// fast forward 1 second to get around gt INSUFFICIENT_COOLDOWN check

        stakedWell.redeem(user, amount);

        /// withdraw

        vm.stopPrank();

        assertEq(xwellProxy.balanceOf(user), startingUserxWellBalance + amount, "User should have received xWell");
    }

    function testSetCoolDownSecondsNonEmissionsManagerFails() public {
        vm.expectRevert("Only emissions manager can call this function");
        vm.prank(address(111));
        stakedWell.setCoolDownSeconds(0);
    }

    function testSetUnstakeWindowNonEmissionsManagerFails() public {
        vm.expectRevert("Only emissions manager can call this function");
        vm.prank(address(111));
        stakedWell.setUnstakeWindow(0);
    }
}
