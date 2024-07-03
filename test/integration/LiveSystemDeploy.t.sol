//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {mip00} from "@proposals/mips/mip00.sol";
import {ChainIds} from "@utils/ChainIds.sol";
import {Configs} from "@proposals/Configs.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";

contract LiveSystemDeploy is Test {
    using ChainIds for uint256;

    MultiRewardDistributor mrd;
    Comptroller comptroller;
    Addresses addresses;
    address public well;

    function setUp() public {
        // TODO restrict chain ids passing the json here
        addresses = new Addresses();

        // TODO verify wheter the system has already been deployed and
        // initialized on chain and skip
        // proposal execution in case
        mip00 proposal = new mip00();
        proposal.primaryForkId().createForksAndSelect();

        proposal.deploy(addresses, address(proposal));
        proposal.afterDeploy(addresses, address(proposal));

        proposal.preBuildMock(addresses);
        proposal.build(addresses);
        proposal.run(addresses, address(proposal));
        proposal.validate(addresses, address(proposal));

        mrd = MultiRewardDistributor(addresses.getAddress("MRD_PROXY"));
        well = addresses.getAddress("xWELL_PROXY");
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
    }

    function testGuardianCanPauseTemporalGovernor() public {
        TemporalGovernor gov = TemporalGovernor(
            payable(addresses.getAddress("TEMPORAL_GOVERNOR"))
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
                addresses.getAddress("GOVTOKEN")
            );

        assertEq(
            config.owner,
            addresses.getAddress("EMISSIONS_ADMIN"),
            "Owner incorrect"
        );
        assertEq(config.emissionToken, well, "Emission token incorrect");
        // comment out since the system was deployed before block.timestamp
        assertEq(
            config.endTime,
            block.timestamp + 4 weeks,
            "End time incorrect"
        );
    }

    function testUpdateEmissionConfigSupplyUsdcSuccess() public {
        uint256 borrowIndex;

        MToken mToken = MToken(addresses.getAddress("MOONWELL_USDBC"));
        {
            // must calculate borrow index before updating end time
            // otherwise the global timestamp will be equal to the current block timestamp
            MultiRewardDistributorCommon.MarketConfig memory config = mrd
                .getConfigForMarket(mToken, addresses.getAddress("GOVTOKEN"));

            uint256 denominator = (mToken.totalBorrows() * 1e18) / // exp scale
                mToken.borrowIndex();

            uint256 deltaTimestamp = block.timestamp -
                config.borrowGlobalTimestamp;
            uint256 tokenAccrued = deltaTimestamp *
                config.borrowEmissionsPerSec;
            uint256 ratio = denominator > 0
                ? (tokenAccrued * 1e36) / denominator // double scale
                : 0;

            borrowIndex = config.borrowGlobalIndex + ratio;
        }

        testUpdateEmissionConfigEndTimeSuccess();

        {
            vm.startPrank(addresses.getAddress("EMISSIONS_ADMIN"));
            mrd._updateSupplySpeed(
                mToken, /// reward mUSDbC
                well, /// rewards paid in WELL
                1e18 /// pay 1 well per second in rewards
            );
            vm.stopPrank();

            MultiRewardDistributorCommon.MarketConfig memory config = mrd
                .getConfigForMarket(mToken, addresses.getAddress("GOVTOKEN"));

            deal(
                well,
                address(mrd),
                4 weeks * 1e18 /// fund for entire period
            );

            assertEq(
                config.owner,
                addresses.getAddress("EMISSIONS_ADMIN"),
                "Owner incorrect"
            );
            assertEq(config.emissionToken, well, "Emission token incorrect");
            assertEq(
                config.supplyEmissionsPerSec,
                1e18,
                "Supply emissions incorrect"
            );
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
                borrowIndex,
                "Borrow global index incorrect"
            );
        }
    }

    function testUpdateEmissionConfigBorrowUsdcSuccess() public {
        uint256 supplyIndex;

        MToken mToken = MToken(addresses.getAddress("MOONWELL_USDBC"));
        {
            // must calculate supply index before updating end time
            // otherwise the global timestamp will be equal to the current block timestamp
            MultiRewardDistributorCommon.MarketConfig memory config = mrd
                .getConfigForMarket(mToken, addresses.getAddress("GOVTOKEN"));

            uint256 denominator = mToken.totalSupply();
            uint256 deltaTimestamp = block.timestamp -
                config.supplyGlobalTimestamp;
            uint256 tokenAccrued = deltaTimestamp *
                config.supplyEmissionsPerSec;
            uint256 ratio = denominator > 0
                ? (tokenAccrued * 1e36) / denominator // double scale
                : 0;

            supplyIndex = config.supplyGlobalIndex + ratio;
        }

        testUpdateEmissionConfigEndTimeSuccess();

        vm.startPrank(addresses.getAddress("EMISSIONS_ADMIN"));
        mrd._updateBorrowSpeed(
            mToken, /// reward mUSDbC
            well, /// rewards paid in WELL
            1e18 /// pay 1 well per second in rewards to borrowers
        );
        vm.stopPrank();

        deal(
            well,
            address(mrd),
            4 weeks * 1e18 /// fund for entire period
        );

        {
            MultiRewardDistributorCommon.MarketConfig memory config = mrd
                .getConfigForMarket(mToken, addresses.getAddress("GOVTOKEN"));

            assertEq(
                config.owner,
                addresses.getAddress("EMISSIONS_ADMIN"),
                "Owner incorrect"
            );
            assertEq(config.emissionToken, well, "Emission token incorrect");
            assertEq(
                config.borrowEmissionsPerSec,
                1e18,
                "Borrow emissions incorrect"
            );
            assertEq(
                config.endTime,
                block.timestamp + 4 weeks,
                "End time incorrect"
            );
            assertEq(
                config.supplyGlobalIndex,
                supplyIndex,
                "Supply global index incorrect"
            );
            assertEq(
                config.borrowGlobalIndex,
                1e36,
                "Borrow global index incorrect"
            );
        }
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

        assertEq(mToken.mint(mintAmount), 0, "Mint failed"); /// ensure successful mint
        assertTrue(
            mToken.balanceOf(sender) > 0,
            "mToken balance should be gt 0 after mint"
        ); /// ensure balance is gt 0
        assertEq(
            token.balanceOf(address(mToken)) - startingTokenBalance,
            mintAmount,
            "Underlying balance not updated"
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
            comptroller.checkMembership(sender, MToken(address(mToken))),
            "Membership check failed"
        ); /// ensure sender and mToken is in market

        assertEq(mToken.borrow(borrowAmount), 0, "Borrow failed"); /// ensure successful borrow

        assertEq(token.balanceOf(sender), borrowAmount, "Wrong borrow amount"); /// ensure balance is correct
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

        MToken mToken = MToken(addresses.getAddress("MOONWELL_USDBC"));

        MultiRewardDistributorCommon.RewardInfo[] memory rewards = mrd
            .getOutstandingRewardsForUser(mToken, address(this));

        assertEq(rewards[0].emissionToken, well);

        uint256 balance = mToken.balanceOf(address(this));
        uint256 totalSupply = mToken.totalSupply();

        MultiRewardDistributorCommon.MarketConfig memory config = mrd
            .getConfigForMarket(mToken, addresses.getAddress("GOVTOKEN"));

        uint256 expectedReward = ((toWarp * config.supplyEmissionsPerSec) *
            balance) / totalSupply;

        assertApproxEqRel(
            rewards[0].totalAmount,
            expectedReward,
            1e17,
            "Total rewards not within 1%"
        ); /// allow 1% error, anything more causes test failure
        assertApproxEqRel(
            rewards[0].supplySide,
            expectedReward,
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

        MToken mToken = MToken(addresses.getAddress("MOONWELL_USDBC"));

        MultiRewardDistributorCommon.RewardInfo[] memory rewards = mrd
            .getOutstandingRewardsForUser(mToken, address(this));

        uint256 userCurrentBorrow = mToken.borrowBalanceCurrent(address(this));
        uint256 totalBorrow = mToken.totalBorrows();

        MultiRewardDistributorCommon.MarketConfig memory config = mrd
            .getConfigForMarket(mToken, addresses.getAddress("GOVTOKEN"));

        // calculate expected borrow reward
        uint256 expectedBorrowReward = ((toWarp *
            config.borrowEmissionsPerSec) * userCurrentBorrow) / totalBorrow;

        assertEq(rewards[0].emissionToken, well);
        assertApproxEqRel(
            rewards[0].totalAmount,
            expectedBorrowReward,
            1e17,
            "Total rewards not within 1%"
        ); /// allow 1% error, anything more causes test failure
        assertApproxEqRel(
            rewards[0].borrowSide,
            expectedBorrowReward,
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

        MToken mToken = MToken(addresses.getAddress("MOONWELL_USDBC"));

        MultiRewardDistributorCommon.RewardInfo[] memory rewards = mrd
            .getOutstandingRewardsForUser(mToken, address(this));

        uint256 balance = mToken.balanceOf(address(this));
        uint256 totalSupply = mToken.totalSupply();

        MultiRewardDistributorCommon.MarketConfig memory config = mrd
            .getConfigForMarket(mToken, addresses.getAddress("GOVTOKEN"));

        uint256 expectedSupplyReward = ((toWarp *
            config.supplyEmissionsPerSec) * balance) / totalSupply;

        uint256 userCurrentBorrow = mToken.borrowBalanceCurrent(address(this));
        uint256 totalBorrow = mToken.totalBorrows();

        // calculate expected borrow reward
        uint256 expectedBorrowReward = ((toWarp *
            config.borrowEmissionsPerSec) * userCurrentBorrow) / totalBorrow;

        assertEq(rewards[0].emissionToken, well);
        assertApproxEqRel(
            rewards[0].totalAmount,
            expectedBorrowReward + expectedSupplyReward,
            1e17,
            "Total rewards not within 1%"
        ); /// allow 1% error, anything more causes test failure
        assertApproxEqRel(
            rewards[0].borrowSide,
            expectedBorrowReward,
            1e17,
            "Borrow side rewards not within 1%"
        ); /// allow 1% error, anything more causes test failure
        assertApproxEqRel(
            rewards[0].supplySide,
            expectedSupplyReward,
            1e17,
            "Supply side rewards not within 1%"
        );
    }

    function testLiquidateAccountReceivesRewards(uint256 toWarp) public {
        toWarp = _bound(toWarp, 1_000_000, 4 weeks);

        testUpdateEmissionConfigSupplyUsdcSuccess();

        vm.warp(block.timestamp + 1);

        testUpdateEmissionConfigBorrowUsdcSuccess();

        testBorrowMTokenSucceeds();

        MToken mToken = MToken(addresses.getAddress("MOONWELL_USDBC"));

        MultiRewardDistributorCommon.RewardInfo[] memory rewardsBefore = mrd
            .getOutstandingRewardsForUser(mToken, address(this));

        MultiRewardDistributorCommon.MarketConfig memory config = mrd
            .getConfigForMarket(mToken, addresses.getAddress("GOVTOKEN"));

        uint256 expectedSupplyReward;
        {
            uint256 balance = mToken.balanceOf(address(this)) / 2;
            uint256 totalSupply = mToken.totalSupply();

            expectedSupplyReward =
                ((toWarp * config.supplyEmissionsPerSec) * balance) /
                totalSupply;
        }

        uint256 expectedBorrowReward;
        {
            uint256 userCurrentBorrow = mToken.borrowBalanceCurrent(
                address(this)
            );
            uint256 totalBorrow = mToken.totalBorrows();

            // calculate expected borrow reward
            expectedBorrowReward =
                ((toWarp * config.borrowEmissionsPerSec) * userCurrentBorrow) /
                totalBorrow;
        }

        vm.warp(block.timestamp + toWarp);

        /// borrower is now underwater on loan
        deal(
            address(mToken),
            address(this),
            mToken.balanceOf(address(this)) / 2
        );

        {
            (uint256 err, uint256 liquidity, uint256 shortfall) = comptroller
                .getHypotheticalAccountLiquidity(
                    address(this),
                    address(mToken),
                    0,
                    0
                );

            assertEq(err, 0, "Error in hypothetical liquidity calculation");
            assertEq(liquidity, 0, "Liquidity not 0");
            assertGt(shortfall, 0, "Shortfall not gt 0");
        }

        uint256 repayAmt = 50e6;
        address liquidator = address(100_000_000);
        IERC20 usdc = IERC20(addresses.getAddress("USDBC"));

        deal(address(usdc), liquidator, repayAmt);
        vm.prank(liquidator);
        usdc.approve(address(mToken), repayAmt);

        _liquidateAccount(
            liquidator,
            address(this),
            MErc20(address(mToken)),
            1e5
        );

        MultiRewardDistributorCommon.RewardInfo[] memory rewardsAfter = mrd
            .getOutstandingRewardsForUser(mToken, address(this));

        assertEq(
            rewardsAfter[0].emissionToken,
            well,
            "Emission token incorrect"
        );
        assertApproxEqRel(
            rewardsAfter[0].totalAmount,
            rewardsBefore[0].totalAmount +
                expectedBorrowReward +
                expectedSupplyReward,
            1e17,
            "Total rewards not within 1%"
        ); /// allow 1% error, anything more causes test failure
        assertApproxEqRel(
            rewardsAfter[0].borrowSide,
            rewardsBefore[0].borrowSide + expectedBorrowReward,
            1e17,
            "Borrow side rewards not within 1%"
        ); /// allow 1% error, anything more causes test failure
        assertApproxEqRel(
            rewardsAfter[0].supplySide,
            rewardsBefore[0].supplySide + expectedSupplyReward,
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
