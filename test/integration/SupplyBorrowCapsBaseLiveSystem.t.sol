// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@test/proposals/Configs.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {mip00 as mip} from "@test/proposals/mips/mip00.sol";
import {TestProposals} from "@test/proposals/TestProposals.sol";

contract SupplyBorrowCapsLiveSystemBaseTest is Test, Configs {
    Comptroller comptroller;
    TestProposals proposals;
    Addresses addresses;
    MErc20 mUsdc;
    MErc20 mWeth;
    MErc20 mcbEth;

    /// @notice max mint amount for usdc market
    uint256 public constant maxMintAmountUsdc = 40_000_000e6;

    /// @notice max mint amount for weth market
    uint256 public constant maxMintAmountWeth = 10_500e18;

    /// @notice max mint amt for cbEth market
    uint256 public constant maxMintAmountcbEth = 5_000e18;

    function setUp() public {
        address[] memory mips = new address[](1);
        mips[0] = address(new mip());

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
            false
        ); /// only setup after deploy, build, and run, do not validate
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        mUsdc = MErc20(addresses.getAddress("MOONWELL_USDC"));
        mWeth = MErc20(addresses.getAddress("MOONWELL_WETH"));
        mcbEth = MErc20(addresses.getAddress("MOONWELL_cbETH"));
    }

    function testSupplyCapsSetCorrectly() public {
        assertEq(comptroller.supplyCaps(address(mUsdc)), maxMintAmountUsdc);
        assertEq(comptroller.supplyCaps(address(mWeth)), maxMintAmountWeth);
        assertEq(comptroller.supplyCaps(address(mcbEth)), maxMintAmountcbEth);
    }

    function testBorrowCapsSetCorrectly() public {
        assertEq(comptroller.borrowCaps(address(mUsdc)), 32_000_000e6);
        assertEq(comptroller.borrowCaps(address(mWeth)), 6_300e18);
        assertEq(comptroller.borrowCaps(address(mcbEth)), 1_500e18);
    }

    function testSupplyingOverSupplyCapFailsUsdc() public {
        address underlying = address(mUsdc.underlying());
        deal(underlying, address(this), 50_000_000e6);

        IERC20(underlying).approve(address(mUsdc), 50_000_000e6);
        vm.expectRevert("market supply cap reached");
        mUsdc.mint(50_000_000e6);
    }

    function testSupplyingOverSupplyCapFailsWeth() public {
        uint256 mintAmount = 11_000e18;
        address underlying = address(mWeth.underlying());
        deal(underlying, address(this), mintAmount);

        IERC20(underlying).approve(address(mWeth), mintAmount);
        vm.expectRevert("market supply cap reached");
        mWeth.mint(mintAmount);
    }

    function testSupplyingOverSupplyCapFailscbEth() public {
        uint256 mintAmount = 11_000e18;
        address underlying = address(mcbEth.underlying());
        deal(underlying, address(this), mintAmount);

        IERC20(underlying).approve(address(mcbEth), mintAmount);
        vm.expectRevert("market supply cap reached");
        mcbEth.mint(mintAmount);
    }

    function testBorrowingOverBorrowCapFailscbEth() public {
        uint256 mintAmount = 4_900e18;
        uint256 borrowAmount = 2_000e18;
        address underlying = address(mcbEth.underlying());

        deal(underlying, address(this), mintAmount);

        IERC20(underlying).approve(address(mcbEth), mintAmount);
        mcbEth.mint(mintAmount);

        address[] memory mToken = new address[](1);
        mToken[0] = address(mcbEth);

        comptroller.enterMarkets(mToken);

        vm.expectRevert("market borrow cap reached");
        mcbEth.borrow(borrowAmount);
    }

    function testBorrowingOverBorrowCapFailsWeth() public {
        uint256 mintAmount = 10_000e18;
        uint256 borrowAmount = 6_500e18;
        address underlying = address(mWeth.underlying());

        deal(underlying, address(this), mintAmount);

        IERC20(underlying).approve(address(mWeth), mintAmount);
        mWeth.mint(mintAmount);

        address[] memory mToken = new address[](1);
        mToken[0] = address(mWeth);

        comptroller.enterMarkets(mToken);

        vm.expectRevert("market borrow cap reached");
        mWeth.borrow(borrowAmount);
    }

    function testBorrowingOverBorrowCapFailsUsdc() public {
        uint256 mintAmount = 39_000_000e6;
        uint256 borrowAmount = 33_000_000e6;
        address underlying = address(mUsdc.underlying());

        deal(underlying, address(this), mintAmount);

        IERC20(underlying).approve(address(mUsdc), mintAmount);
        mUsdc.mint(mintAmount);

        address[] memory mToken = new address[](1);
        mToken[0] = address(mUsdc);

        comptroller.enterMarkets(mToken);

        vm.expectRevert("market borrow cap reached");
        mUsdc.borrow(borrowAmount);
    }
}
