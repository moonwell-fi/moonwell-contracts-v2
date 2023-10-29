// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {TestProposals} from "@proposals/TestProposals.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";

contract IRModelWethUpgradeLiveSystemBaseTest is PostProposalCheck, Configs {
    Comptroller comptroller;
    MErc20 mUSDbC;
    MErc20 mWeth;
    MErc20 mcbEth;

    function setUp() public override {
        super.setUp();

        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        mUSDbC = MErc20(addresses.getAddress("MOONWELL_USDBC"));
        mWeth = MErc20(addresses.getAddress("MOONWELL_WETH"));
        mcbEth = MErc20(addresses.getAddress("MOONWELL_cbETH"));
    }

    function testInterestAccruedUpdatesAccrualTime() public {
        testAccrueInterest();
        assertEq(mWeth.accrualBlockTimestamp(), block.timestamp);
    }

    function testAccrueInterest() public {
        assertEq(mWeth.accrueInterest(), 0);
    }

    function testSupplyingWethAfterIRModelUpgradeSucceeds() public {
        uint256 mintAmount = 100e18;
        address underlying = address(mWeth.underlying());

        deal(underlying, address(this), mintAmount);

        IERC20(underlying).approve(address(mWeth), mintAmount);

        assertEq(mWeth.mint(mintAmount), 0);
    }

    function testBorrowSucceeds() public {
        testSupplyingWethAfterIRModelUpgradeSucceeds();
        uint256 borrowAmount = 74e18;

        address[] memory mToken = new address[](1);
        mToken[0] = address(mWeth);

        comptroller.enterMarkets(mToken);

        assertEq(mWeth.borrow(borrowAmount), 0);
    }

    fallback() external payable {}
}
