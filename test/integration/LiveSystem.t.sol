//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";

contract LiveSystemTest is Test {
    MultiRewardDistributor mrd;
    Comptroller comptroller;
    Addresses addresses;
    address public well;

    function setUp() public {
        addresses = new Addresses();
        mrd = MultiRewardDistributor(addresses.getAddress("MRD_PROXY"));
        well = addresses.getAddress("WELL");
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
    }

    function testGuardianCanPauseTemporalGovernor() public {
        TemporalGovernor gov = TemporalGovernor(
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR_GUARDIAN"));
        gov.togglePause();

        assertTrue(gov.paused());
        assertFalse(gov.guardianPauseAllowed());
        assertEq(gov.lastPauseTime(), block.timestamp);
    }

    function testEmissionsAdminCanChangeRewardStream() public {
        address emissionsAdmin = addresses.getAddress("EMISSIONS_ADMIN");
        MToken mUSDbC = MToken(addresses.getAddress("MOONWELL_USDBC"));

        vm.prank(emissionsAdmin);
        mrd._updateOwner(mUSDbC, address(well), emissionsAdmin);

        vm.prank(emissionsAdmin);
        mrd._updateBorrowSpeed(mUSDbC, address(well), 1e18);
    }

    function testUpdateEmissionConfigEndTimeSuccess() public {
        vm.startPrank(addresses.getAddress("EMISSIONS_ADMIN"));

        mrd._updateEndTime(
            MToken(addresses.getAddress("MOONWELL_USDBC")), /// reward mUSDbC
            well, /// rewards paid in WELL
            block.timestamp + 4 weeks /// end time
        );
        vm.stopPrank();

        MultiRewardDistributorCommon.MarketConfig memory config = mrd
            .getConfigForMarket(
                MToken(addresses.getAddress("MOONWELL_USDBC")),
                addresses.getAddress("WELL")
            );

        assertEq(config.owner, addresses.getAddress("EMISSIONS_ADMIN"));
        assertEq(config.emissionToken, well);
        // comment out since the system was deployed before block.timestamp
        assertEq(config.endTime, block.timestamp + 4 weeks);
    }

    function testUpdateEmissionConfigSupplyUsdcSuccess() public {
        testUpdateEmissionConfigEndTimeSuccess();
        vm.startPrank(addresses.getAddress("EMISSIONS_ADMIN"));
        mrd._updateSupplySpeed(
            MToken(addresses.getAddress("MOONWELL_USDBC")), /// reward mUSDbC
            well, /// rewards paid in WELL
            1e18 /// pay 1 well per second in rewards
        );
        vm.stopPrank();

        deal(
            well,
            address(mrd),
            4 weeks * 1e18 /// fund for entire period
        );

        MultiRewardDistributorCommon.MarketConfig memory config = mrd
            .getConfigForMarket(
                MToken(addresses.getAddress("MOONWELL_USDBC")),
                addresses.getAddress("WELL")
            );

        assertEq(config.owner, addresses.getAddress("EMISSIONS_ADMIN"));
        assertEq(config.emissionToken, well);
        assertEq(config.supplyEmissionsPerSec, 1e18);
        // comment out since the system was deployed before block.timestamp
        assertEq(config.endTime, block.timestamp + 4 weeks);
        assertEq(config.supplyGlobalIndex, 1e36);
        assertEq(config.borrowGlobalIndex, 1e36);
    }

    function testUpdateEmissionConfigBorrowUsdcSuccess() public {
        testUpdateEmissionConfigEndTimeSuccess();

        vm.startPrank(addresses.getAddress("EMISSIONS_ADMIN"));
        mrd._updateBorrowSpeed(
            MToken(addresses.getAddress("MOONWELL_USDBC")), /// reward mUSDbC
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
                MToken(addresses.getAddress("MOONWELL_USDBC")),
                addresses.getAddress("WELL")
            );

        assertEq(config.owner, addresses.getAddress("EMISSIONS_ADMIN"));
        assertEq(config.emissionToken, well);
        assertEq(
            config.borrowEmissionsPerSec,
            1e18,
            "Borrow emissions incorrect"
        );
        // comment out since the system was deployed before block.timestamp
        assertEq(
            config.endTime,
            block.timestamp + 4 weeks,
            "End time incorrect"
        );
        assertEq(
            config.supplyGlobalIndex,
            1e36,
            "Supply global index incorrect"
        );
        assertEq(
            config.borrowGlobalIndex,
            1e36,
            "Borrow global index incorrect"
        );
    }

    function testMintMTokenSucceeds() public {
        address sender = address(this);
        uint256 mintAmount = 100e6;

        IERC20 token = IERC20(addresses.getAddress("USDBC"));
        MErc20Delegator mToken = MErc20Delegator(
            payable(addresses.getAddress("MOONWELL_USDBC"))
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
    }

    function testBorrowMTokenSucceeds() public {
        testMintMTokenSucceeds();

        address sender = address(this);
        uint256 borrowAmount = 50e6;

        IERC20 token = IERC20(addresses.getAddress("USDBC"));
        MErc20Delegator mToken = MErc20Delegator(
            payable(addresses.getAddress("MOONWELL_USDBC"))
        );

        address[] memory mTokens = new address[](1);
        mTokens[0] = address(mToken);

        comptroller.enterMarkets(mTokens);
        assertTrue(
            comptroller.checkMembership(sender, MToken(address(mToken)))
        ); /// ensure sender and mToken is in market

        assertEq(mToken.borrow(borrowAmount), 0); /// ensure successful borrow

        assertEq(token.balanceOf(sender), borrowAmount); /// ensure balance is correct
    }

    function testBorrowOtherMTokenSucceeds() public {
        testMintMTokenSucceeds();

        address sender = address(this);
        deal(
            addresses.getAddress("WETH"),
            addresses.getAddress("MOONWELL_WETH"),
            1 ether
        );

        IERC20 weth = IERC20(addresses.getAddress("WETH"));

        uint256 borrowAmount = 1e6;

        MErc20Delegator mToken = MErc20Delegator(
            payable(addresses.getAddress("MOONWELL_WETH"))
        );

        address[] memory mTokens = new address[](1);
        mTokens[0] = addresses.getAddress("MOONWELL_USDBC");

        comptroller.enterMarkets(mTokens);
        assertTrue(
            comptroller.checkMembership(
                sender,
                MToken(addresses.getAddress("MOONWELL_USDBC"))
            )
        ); /// ensure sender and mToken is in market

        (, uint256 liquidity, uint256 shortfall) = comptroller
            .getAccountLiquidity(sender);

        assertEq(mToken.borrow(borrowAmount), 0); /// ensure successful borrow
        (
            ,
            uint256 liquidityAfterBorrow,
            uint256 shortfallAfterBorrow
        ) = comptroller.getAccountLiquidity(sender);

        assertEq(weth.balanceOf(sender), borrowAmount); /// ensure balance is correct

        assertGt(liquidity, liquidityAfterBorrow);
        assertEq(shortfall, shortfallAfterBorrow);
    }

    function testSupplyUsdcReceivesRewards(uint256 toWarp) public {
        toWarp = _bound(toWarp, 1_000_000, 4 weeks);

        testUpdateEmissionConfigSupplyUsdcSuccess();
        testMintMTokenSucceeds();

        vm.warp(block.timestamp + toWarp);

        MultiRewardDistributorCommon.RewardInfo[] memory rewards = mrd
            .getOutstandingRewardsForUser(
                MToken(addresses.getAddress("MOONWELL_USDBC")),
                address(this)
            );

        assertEq(rewards[0].emissionToken, well);
        assertApproxEqRel(
            rewards[0].totalAmount,
            toWarp * 1e18,
            1e17,
            "Total rewards not within 1%"
        ); /// allow 1% error, anything more causes test failure
        assertApproxEqRel(
            rewards[0].supplySide,
            toWarp * 1e18,
            1e17,
            "Supply side rewards not within 1%"
        ); /// allow 1% error, anything more causes test failure
        assertEq(rewards[0].borrowSide, 0);
    }

    function testBorrowUsdcReceivesRewards(uint256 toWarp) public {
        toWarp = _bound(toWarp, 1_000_000, 4 weeks);

        testUpdateEmissionConfigBorrowUsdcSuccess();
        testBorrowMTokenSucceeds();

        vm.warp(block.timestamp + toWarp);

        MultiRewardDistributorCommon.RewardInfo[] memory rewards = mrd
            .getOutstandingRewardsForUser(
                MToken(addresses.getAddress("MOONWELL_USDBC")),
                address(this)
            );

        assertEq(rewards[0].emissionToken, well);
        assertApproxEqRel(
            rewards[0].totalAmount,
            toWarp * 1e18,
            1e17,
            "Total rewards not within 1%"
        ); /// allow 1% error, anything more causes test failure
        assertApproxEqRel(
            rewards[0].borrowSide,
            toWarp * 1e18,
            1e17,
            "Supply side rewards not within 1%"
        ); /// allow 1% error, anything more causes test failure
        assertEq(rewards[0].supplySide, 0);
    }

    function testSupplyBorrowUsdcReceivesRewards(uint256 toWarp) public {
        toWarp = _bound(toWarp, 1_000_000, 4 weeks);

        testUpdateEmissionConfigBorrowUsdcSuccess();

        vm.warp(block.timestamp + 1);
        testUpdateEmissionConfigSupplyUsdcSuccess();

        testBorrowMTokenSucceeds();

        vm.warp(block.timestamp + toWarp);

        MultiRewardDistributorCommon.RewardInfo[] memory rewards = mrd
            .getOutstandingRewardsForUser(
                MToken(addresses.getAddress("MOONWELL_USDBC")),
                address(this)
            );

        assertEq(rewards[0].emissionToken, well);
        assertApproxEqRel(
            rewards[0].totalAmount,
            toWarp * 1e18 + toWarp * 1e18,
            1e17,
            "Total rewards not within 1%"
        ); /// allow 1% error, anything more causes test failure
        assertApproxEqRel(
            rewards[0].borrowSide,
            toWarp * 1e18,
            1e17,
            "Borrow side rewards not within 1%"
        ); /// allow 1% error, anything more causes test failure
        assertApproxEqRel(
            rewards[0].supplySide,
            toWarp * 1e18,
            1e17,
            "Supply side rewards not within 1%"
        );
    }

    function testLiquidateAccountReceivesRewards(uint256 toWarp) public {
        toWarp = _bound(toWarp, 1_000_000, 4 weeks);

        testUpdateEmissionConfigBorrowUsdcSuccess();

        vm.warp(block.timestamp + 1);
        testUpdateEmissionConfigSupplyUsdcSuccess();

        testBorrowMTokenSucceeds();

        vm.warp(block.timestamp + toWarp);

        MToken mToken = MToken(addresses.getAddress("MOONWELL_USDBC"));

        /// borrower is now underwater on loan
        deal(
            address(mToken),
            address(this),
            mToken.balanceOf(address(this)) / 2
        );

        (uint256 err, uint256 liquidity, uint256 shortfall) = comptroller
            .getHypotheticalAccountLiquidity(
                address(this),
                address(mToken),
                0,
                0
            );

        assertEq(err, 0);
        assertEq(liquidity, 0);
        assertGt(shortfall, 0);

        uint256 repayAmt = 50e6;
        address liquidator = address(100_000_000);
        IERC20 usdc = IERC20(addresses.getAddress("USDBC"));

        deal(addresses.getAddress("USDBC"), liquidator, repayAmt);
        vm.prank(liquidator);
        usdc.approve(address(mToken), repayAmt);

        _liquidateAccount(
            liquidator,
            address(this),
            MErc20(address(mToken)),
            1e6
        );

        MultiRewardDistributorCommon.RewardInfo[] memory rewards = mrd
            .getOutstandingRewardsForUser(
                MToken(addresses.getAddress("MOONWELL_USDBC")),
                address(this)
            );

        assertEq(rewards[0].emissionToken, well);
        assertGt(
            rewards[0].totalAmount,
            toWarp * 1e18,
            "Total rewards not gt 100%"
        ); /// allow 1% error, anything more causes test failure
        assertApproxEqRel(
            rewards[0].borrowSide,
            toWarp * 1e18,
            1e17,
            "Borrow side rewards not within 1%"
        ); /// allow 1% error, anything more causes test failure
        assertApproxEqRel(
            rewards[0].supplySide,
            (toWarp * 1e18) / 2,
            1e17,
            "Supply side rewards not within 1%"
        );
    }

    function _liquidateAccount(
        address liquidator,
        address liquidated,
        MErc20 token,
        uint256 repayAmt
    ) private {
        vm.prank(liquidator);
        assertEq(
            token.liquidateBorrow(liquidated, repayAmt, token),
            0,
            "user liquidation failure"
        );
    }
}
