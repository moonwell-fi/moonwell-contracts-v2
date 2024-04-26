// SPDX-License-Iden`fier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {TestProposals} from "@proposals/TestProposals.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";

contract SupplyBorrowCapsLiveSystemBaseTest is PostProposalCheck, Configs {
    Comptroller comptroller;
    MErc20 mUSDbC;
    MErc20 mWeth;
    MErc20 mcbEth;

    /// @notice max mint amount for usdc market
    uint256 public constant maxMintAmountUsdc = 40_000_000e6;

    /// @notice max mint amount for weth market
    uint256 public constant maxMintAmountWeth = 40_000e18;

    /// @notice max mint amt for cbEth market
    uint256 public constant maxMintAmountcbEth = 5_000e18;

    function setUp() public override {
        super.setUp();

        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        mUSDbC = MErc20(addresses.getAddress("MOONWELL_USDBC"));
        mWeth = MErc20(addresses.getAddress("MOONWELL_WETH"));
        mcbEth = MErc20(addresses.getAddress("MOONWELL_cbETH"));
    }

    function testSupplyingOverSupplyCapFailsUsdc() public {
        address underlying = address(mUSDbC.underlying());
        deal(underlying, address(this), 50_000_000e6);

        IERC20(underlying).approve(address(mUSDbC), 50_000_000e6);
        vm.expectRevert("market supply cap reached");
        mUSDbC.mint(50_000_000e6);
    }

    function testSupplyingOverSupplyCapFailsWeth() public {
        uint256 mintAmount = maxMintAmountWeth + 1e18;
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
        mcbEth.accrueInterest();

        uint256 mintAmount = _getMaxSupplyAmount(
            addresses.getAddress("MOONWELL_cbETH")
        ) - 1;
        uint256 borrowAmount = _getMaxBorrowAmount(
            addresses.getAddress("MOONWELL_cbETH")
        );
        address underlying = address(mcbEth.underlying());

        deal(underlying, address(this), mintAmount);

        IERC20(underlying).approve(address(mcbEth), mintAmount);
        mcbEth.mint(mintAmount);

        address[] memory mToken = new address[](1);
        mToken[0] = address(mcbEth);

        comptroller.enterMarkets(mToken);

        vm.expectRevert("market borrow cap reached");
        mcbEth.borrow(borrowAmount + 1);
    }

    function testBorrowingOverBorrowCapFailsWeth() public {
        uint256 mintAmount = _getMaxSupplyAmount(
            addresses.getAddress("MOONWELL_WETH")
        ) - 1e18;
        uint256 borrowAmount = _getMaxBorrowAmount(
            addresses.getAddress("MOONWELL_WETH")
        );
        address underlying = address(mWeth.underlying());

        deal(underlying, address(this), mintAmount);

        IERC20(underlying).approve(address(mWeth), mintAmount);
        mWeth.mint(mintAmount);

        address[] memory mToken = new address[](1);
        mToken[0] = address(mWeth);

        comptroller.enterMarkets(mToken);

        vm.expectRevert("market borrow cap reached");
        mWeth.borrow(borrowAmount + 1e18);
    }

    function testBorrowingOverBorrowCapFailsUsdc() public {
        uint256 usdcMintAmount = _getMaxSupplyAmount(
            addresses.getAddress("MOONWELL_USDBC")
        ) - 1_000e6;
        uint256 borrowAmount = 33_000_000e6;
        address underlying = address(mUSDbC.underlying());

        deal(underlying, address(this), usdcMintAmount);

        IERC20(underlying).approve(address(mUSDbC), usdcMintAmount);
        mUSDbC.mint(usdcMintAmount);

        address[] memory mToken = new address[](1);
        mToken[0] = address(mUSDbC);

        comptroller.enterMarkets(mToken);

        vm.expectRevert("market borrow cap reached");
        mUSDbC.borrow(borrowAmount);
    }

    function _getMaxSupplyAmount(
        address mToken
    ) internal view returns (uint256) {
        uint256 supplyCap = comptroller.supplyCaps(address(mToken));

        uint256 totalCash = MToken(mToken).getCash();
        uint256 totalBorrows = MToken(mToken).totalBorrows();
        uint256 totalReserves = MToken(mToken).totalReserves();

        // totalSupplies = totalCash + totalBorrows - totalReserves
        uint256 totalSupplies = (totalCash + totalBorrows) - totalReserves;

        return supplyCap - totalSupplies - 1;
    }

    function _getMaxBorrowAmount(
        address mToken
    ) internal view returns (uint256) {
        uint256 borrowCap = comptroller.borrowCaps(address(mToken));
        uint256 totalBorrows = MToken(mToken).totalBorrows();

        return borrowCap - totalBorrows - 1;
    }
}
