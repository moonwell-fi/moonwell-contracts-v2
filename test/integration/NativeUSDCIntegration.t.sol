// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@test/proposals/Configs.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {mip0x as mip} from "@test/proposals/mips/examples/mip-market-listing/mip-market-listing.sol";
import {TestProposals} from "@test/proposals/TestProposals.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {MultiRewardDistributor} from "@protocol/MultiRewardDistributor/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/MultiRewardDistributor/MultiRewardDistributorCommon.sol";

contract NativeUSDCLiveSystemBaseTest is Test, Configs {
    MultiRewardDistributor mrd;
    Comptroller comptroller;
    Addresses addresses;
    address well;
    MErc20 mUSDC;

    function setUp() public {
        vm.setEnv("LISTING_PATH", "./test/proposals/mips/mip-b04/MIP-B04.md");
        vm.setEnv("MTOKENS_PATH", "./test/proposals/mips/mip-b04/MTokens.json");
        vm.setEnv(
            "EMISSION_PATH",
            "./test/proposals/mips/mip-b04/RewardStreams.json"
        );

        /// do not broadcast these transactions: in after deploy
        ///    _setReserveFactor(config.reserveFactor);
        ///    _setProtocolSeizeShare(config.seizeShare);
        ///    _setPendingAdmin(payable(governor)); /// set governor as pending admin of the mToken
        vm.setEnv("DO_AFTER_DEPLOY_MTOKEN_BROADCAST", "false");

        // Run all pending proposals before doing e2e tests
        address[] memory mips = new address[](1);
        mips[0] = address(new mip());

        TestProposals proposals = new TestProposals(mips);
        proposals.setUp();
        /// after deploy, after deploy setup, build, run and validate
        proposals.testProposals(
            false, /// do not debug
            false, /// do not deploy mUSDC
            false,
            false,
            false,
            false,
            false, /// do not teardown as there is nothing to teardown
            false
        );

        addresses = proposals.addresses();
        well = addresses.getAddress("WELL");
        mUSDC = MErc20(addresses.getAddress("MOONWELL_USDC"));
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        mrd = MultiRewardDistributor(addresses.getAddress("MRD_PROXY"));
    }

    function testSetup() public {
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
        uint256 usdcMintAmount = _getMaxSupplyAmount(
            addresses.getAddress("MOONWELL_USDC")
        ) - 1_000e6;
        uint256 borrowAmount = 33_000_000e6;
        address underlying = address(mUSDC.underlying());

        deal(underlying, address(this), usdcMintAmount);

        IERC20(underlying).approve(address(mUSDC), usdcMintAmount);
        mUSDC.mint(usdcMintAmount);

        address[] memory mToken = new address[](1);
        mToken[0] = address(mUSDC);

        comptroller.enterMarkets(mToken);

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

        assertEq(err, 0, "Error getting account liquidity");
        assertApproxEqRel(
            liquidity,
            80e18,
            1e15,
            "liquidity not within .1% of $80"
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
                addresses.getAddress("WELL")
            );

        EmissionConfig[] memory emissionConfig = getEmissionConfigurations(
            block.chainid
        );

        assertEq(config.owner, addresses.getAddress("EMISSIONS_ADMIN"));
        assertEq(config.emissionToken, well);
        assertEq(config.borrowEmissionsPerSec, 1e18);
        assertEq(config.endTime, emissionConfig[0].endTime);
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
