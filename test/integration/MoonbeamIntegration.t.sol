//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {IStakedWell} from "@protocol/IStakedWell.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";

contract MoonbeamSafetyModulePostProposalTest is Test, PostProposalCheck {
    IStakedWell well;

    function setUp() public override {
        super.setUp();

        well = IStakedWell(addresses.getAddress("STK_GOVTOKEN_PROXY"));
    }

    function testSetCooldownSecondsNonManagerFails() public {
        vm.expectRevert("Only emissions manager can call this function");
        well.setCoolDownSeconds(1);
    }

    function testSetUnstakeWindowNonManagerFails() public {
        vm.expectRevert("Only emissions manager can call this function");
        well.setUnstakeWindow(1);
    }

    function testRewardsBalanceIncreasing() public {
        uint256 stakeAmount = 100_000_000e18;
        address wellToken = well.STAKED_TOKEN();

        deal(wellToken, address(this), stakeAmount);

        IERC20(well.STAKED_TOKEN()).approve(address(well), stakeAmount);
        well.stake(address(this), stakeAmount);

        uint256 balance = well.getTotalRewardsBalance(address(this));

        vm.warp(block.timestamp + 1 days);

        uint256 balancePostWarp = well.getTotalRewardsBalance(address(this));

        assertGt(
            balancePostWarp,
            balance,
            "Rewards balance should increase over time"
        );
    }
}
