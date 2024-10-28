//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {IStakedWell} from "@protocol/IStakedWell.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";

contract MoonbeamTestSafetyModule is Test, PostProposalCheck {
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
        address account = 0x98952d189C6FFB802A7292180aFcb33Cc618D0a0;
        uint256 balance = well.getTotalRewardsBalance(account);

        vm.warp(block.timestamp + 1 days);

        uint256 balancePostWarp = well.getTotalRewardsBalance(account);

        assertGt(
            balancePostWarp,
            balance,
            "Rewards balance should increase over time"
        );
    }
}
