// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {mip0x as mip} from "@proposals/mips/examples/mip-market-listing/mip-market-listing.sol";
import {BASE_FORK_ID} from "@utils/ChainIds.sol";
import {TestProposals} from "@proposals/TestProposals.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract NativeUSDCPostProposalTest is Test, PostProposalCheck, Configs {
    MultiRewardDistributor mrd;
    Comptroller comptroller;
    address well;
    MErc20 mUSDC;

    function setUp() public override {
        super.setUp();

        vm.selectFork(BASE_FORK_ID);

        well = addresses.getAddress("GOVTOKEN");
        mUSDC = MErc20(addresses.getAddress("MOONWELL_USDC"));
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        mrd = MultiRewardDistributor(addresses.getAddress("MRD_PROXY"));
    }

    function testSetupUsdc() public {
        assertEq(address(mUSDC.underlying()), addresses.getAddress("USDC"));
        assertEq(mUSDC.name(), "Moonwell USDC");
        assertEq(mUSDC.symbol(), "mUSDC");
        assertEq(mUSDC.decimals(), 8);
        assertGt(mUSDC.exchangeRateCurrent(), 0.0002e18); /// exchange starting price is 0.0002e18
        assertEq(mUSDC.reserveFactorMantissa(), 0.15e18);
        assertEq(
            address(mUSDC.comptroller()),
            addresses.getAddress("UNITROLLER")
        );
    }

    function testEmissionsAdminCanChangeRewardStream() public {
        address emissionsAdmin = addresses.getAddress("EMISSIONS_ADMIN");

        vm.prank(emissionsAdmin);
        mrd._updateOwner(mUSDC, address(well), emissionsAdmin);

        vm.prank(emissionsAdmin);
        mrd._updateBorrowSpeed(mUSDC, address(well), 1e18);
    }

    function testSupplyingOverSupplyCapFailsUsdc() public {
        address underlying = address(mUSDC.underlying());
        deal(underlying, address(this), 50_000_000e6);

        IERC20(underlying).approve(address(mUSDC), 50_000_000e6);
        vm.expectRevert("market supply cap reached");
        mUSDC.mint(50_000_000e6);
    }

    function testBorrowingOverBorrowCapFailsUsdc() public {
        /// TODO figure out why this test intermittently fails when it subtracts 1000e6 from mintAmount
        /// fails with mintAllowed error, "market supply cap reached"
        uint256 usdcMintAmount = _getMaxSupplyAmount(
            addresses.getAddress("MOONWELL_USDC")
        ) / 10;

        uint256 borrowAmount = comptroller.borrowCaps(address(mUSDC)) + 1;
        address underlying = address(mUSDC.underlying());

        deal(underlying, address(this), usdcMintAmount);

        IERC20(underlying).approve(address(mUSDC), usdcMintAmount);
        assertEq(mUSDC.mint(usdcMintAmount), 0, "mint failed");

        address[] memory mToken = new address[](1);
        mToken[0] = address(mUSDC);

        comptroller.enterMarkets(mToken);

        if (borrowAmount > mUSDC.getCash()) {
            deal(address(underlying), address(mUSDC), borrowAmount);
        }

        vm.expectRevert("market borrow cap reached");
        mUSDC.borrow(borrowAmount);
    }

    function testMintMTokenSucceeds() public {
        address sender = address(this);
        uint256 mintAmount = 100e6;

        IERC20 token = IERC20(addresses.getAddress("USDC"));
        MErc20Delegator mToken = MErc20Delegator(
            payable(addresses.getAddress("MOONWELL_USDC"))
        );
        uint256 startingTokenBalance = token.balanceOf(address(mToken));

        deal(address(token), sender, mintAmount);
        token.approve(address(mToken), mintAmount);

        assertEq(mToken.mint(mintAmount), 0); /// ensure successful mint
        assertTrue(mToken.balanceOf(sender) > 0); /// ensure balance is gt 0
        assertEq(
            token.balanceOf(address(mToken)) - startingTokenBalance,
            mintAmount
        ); /// ensure underlying balance is sent to mToken

        address[] memory mTokens = new address[](1);
        mTokens[0] = address(mToken);

        comptroller.enterMarkets(mTokens);
        assertTrue(
            comptroller.checkMembership(
                sender,
                MToken(addresses.getAddress("MOONWELL_USDC"))
            )
        ); /// ensure sender and mToken is in market

        (uint256 err, uint256 liquidity, uint256 shortfall) = comptroller
            .getAccountLiquidity(address(this));

        (, uint256 collateralFactor) = comptroller.markets(address(mToken)); /// fetch collateral factor

        assertEq(err, 0, "Error getting account liquidity");
        assertApproxEqRel(
            liquidity,
            (mintAmount * 1e12 * collateralFactor) / 1e18,
            1e15,
            "liquidity not within .1% of given CF"
        );
        assertEq(shortfall, 0, "Incorrect shortfall");

        comptroller.exitMarket(address(mToken));
    }

    function testUpdateEmissionConfigBorrowUsdcSuccess() public {
        vm.startPrank(addresses.getAddress("EMISSIONS_ADMIN"));
        mrd._updateBorrowSpeed(
            MToken(addresses.getAddress("MOONWELL_USDC")), /// reward mUSDC
            well, /// rewards paid in WELL
            1e18 /// pay 1 well per second in rewards to borrowers
        );
        vm.stopPrank();

        deal(
            well,
            address(mrd),
            4 weeks * 1e18 /// fund for entire period
        );

        MultiRewardDistributorCommon.MarketConfig memory config = mrd
            .getConfigForMarket(
                MToken(addresses.getAddress("MOONWELL_USDC")),
                addresses.getAddress("GOVTOKEN")
            );

        assertEq(
            config.owner,
            addresses.getAddress("EMISSIONS_ADMIN"),
            "incorrect admin"
        );
        assertEq(config.emissionToken, well, "incorrect reward token");
        assertEq(config.borrowEmissionsPerSec, 1e18, "incorrect reward rate");
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
