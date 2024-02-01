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
    function setUp() public override {
        super.setUp();

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

        amount = xwellProxy.MAX_SUPPLY();
        vm.prank(address(xerc20Lockbox));
        xwellProxy.mint(address(this), amount);
        xwellProxy.approve(address(stakedWell), amount);
    }

    function testStake() public {
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
