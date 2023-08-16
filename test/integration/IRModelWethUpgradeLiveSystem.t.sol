// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {mipb01} from "@test/proposals/mips/mip-b01/mip-b01.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@test/proposals/Configs.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {TestProposals2 as TestProposals} from "@test/proposals/TestProposals2.sol";

contract IRModelWethUpgradeLiveSystemBaseTest is Test, Configs {
    Comptroller comptroller;
    TestProposals proposals;
    Addresses addresses;
    MErc20 mUsdc;
    MErc20 mWeth;
    MErc20 mcbEth;

    function setUp() public {
        mipb01 mip = new mipb01();
        address[] memory mips = new address[](1);
        mips[0] = address(mip);

        proposals = new TestProposals(mips);
        proposals.setUp();
        addresses = proposals.addresses();
        proposals.testProposals(
            false,
            false,
            false,
            true,
            true,
            true,
            false,
            true
        ); /// only setup after deploy, build, and run, do not validate
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        mUsdc = MErc20(addresses.getAddress("MOONWELL_USDC"));
        mWeth = MErc20(addresses.getAddress("MOONWELL_WETH"));
        mcbEth = MErc20(addresses.getAddress("MOONWELL_cbETH"));
    }

    function testInterestAccruedInProposal() public {
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
}
