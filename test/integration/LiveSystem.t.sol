// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@test/proposals/Configs.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {mipb00 as mip} from "@test/proposals/mips/mip-b00/mip-b00.sol";
import {TestProposals} from "@test/proposals/TestProposals.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {TemporalGovernor} from "@protocol/Governance/TemporalGovernor.sol";
import {MultiRewardDistributor} from "@protocol/MultiRewardDistributor/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/MultiRewardDistributor/MultiRewardDistributorCommon.sol";

contract LiveSystemTest is Test {
    MultiRewardDistributor mrd;
    Comptroller comptroller;
    TestProposals proposals;
    Addresses addresses;
    address public well;

    function setUp() public {
        address[] memory mips = new address[](1);
        mips[0] = address(new mip());

        proposals = new TestProposals(mips);
        proposals.setUp();
        addresses = proposals.addresses();
        proposals.testProposals(
            false,
            true,
            true,
            true,
            true,
            true,
            false,
            false
        ); /// do not debug, deploy, after deploy, build, and run, do not validate
        mrd = MultiRewardDistributor(addresses.getAddress("MRD_PROXY"));
        well = addresses.getAddress("WELL");
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
    }

    function testSetup() public {
        Configs.EmissionConfig[] memory configs = Configs(
            address(proposals.proposals(0))
        ).getEmissionConfigurations(block.chainid);
        Configs.CTokenConfiguration[] memory mTokenConfigs = Configs(
            address(proposals.proposals(0))
        ).getCTokenConfigurations(block.chainid);

        assertEq(configs.length, 5); /// 5 configs on base goerli
        assertEq(mTokenConfigs.length, 5); /// 5 mTokens on base goerli
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
        MToken musdc = MToken(addresses.getAddress("MOONWELL_USDC"));

        vm.prank(emissionsAdmin);
        mrd._updateOwner(musdc, address(well), emissionsAdmin);

        vm.prank(emissionsAdmin);
        mrd._updateBorrowSpeed(musdc, address(well), 1e18);
    }

    function testUpdateEmissionConfigSupplyUsdcSuccess() public {
        vm.startPrank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        mrd._updateSupplySpeed(
            MToken(addresses.getAddress("MOONWELL_USDC")), /// reward mUSDC
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
                MToken(addresses.getAddress("MOONWELL_USDC")),
                addresses.getAddress("WELL")
            );

        assertEq(config.owner, addresses.getAddress("EMISSIONS_ADMIN"));
        assertEq(config.emissionToken, well);
        assertEq(config.supplyEmissionsPerSec, 1e18);
        assertEq(config.endTime, block.timestamp + 4 weeks);
        assertEq(config.supplyGlobalIndex, 1e36);
        assertEq(config.borrowGlobalIndex, 1e36);
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

        assertEq(config.owner, addresses.getAddress("EMISSIONS_ADMIN"));
        assertEq(config.emissionToken, well);
        assertEq(config.borrowEmissionsPerSec, 1e18);
        assertEq(config.endTime, block.timestamp + 4 weeks);
        assertEq(config.supplyGlobalIndex, 1e36);
        assertEq(config.borrowGlobalIndex, 1e36);
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
    }

    function testBorrowMTokenSucceeds() public {
        testMintMTokenSucceeds();

        address sender = address(this);
        uint256 borrowAmount = 50e6;

        IERC20 token = IERC20(addresses.getAddress("USDC"));
        MErc20Delegator mToken = MErc20Delegator(
            payable(addresses.getAddress("MOONWELL_USDC"))
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
        mTokens[0] = addresses.getAddress("MOONWELL_USDC");

        comptroller.enterMarkets(mTokens);
        assertTrue(
            comptroller.checkMembership(
                sender,
                MToken(addresses.getAddress("MOONWELL_USDC"))
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
                MToken(addresses.getAddress("MOONWELL_USDC")),
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
                MToken(addresses.getAddress("MOONWELL_USDC")),
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
        testUpdateEmissionConfigSupplyUsdcSuccess();
        testBorrowMTokenSucceeds();

        vm.warp(block.timestamp + toWarp);

        MultiRewardDistributorCommon.RewardInfo[] memory rewards = mrd
            .getOutstandingRewardsForUser(
                MToken(addresses.getAddress("MOONWELL_USDC")),
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
        testUpdateEmissionConfigSupplyUsdcSuccess();
        testBorrowMTokenSucceeds();

        vm.warp(block.timestamp + toWarp);

        MToken mToken = MToken(addresses.getAddress("MOONWELL_USDC"));

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
        IERC20 usdc = IERC20(addresses.getAddress("USDC"));

        deal(addresses.getAddress("USDC"), liquidator, repayAmt);
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
                MToken(addresses.getAddress("MOONWELL_USDC")),
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
