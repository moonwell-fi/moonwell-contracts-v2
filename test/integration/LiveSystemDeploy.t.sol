//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "@forge-std/Test.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {ChainIds} from "@utils/ChainIds.sol";
import {Configs} from "@proposals/Configs.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {Unitroller} from "@protocol/Unitroller.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";

import {ExponentialNoError} from "@protocol/ExponentialNoError.sol";

contract LiveSystemDeploy is Test, ExponentialNoError, PostProposalCheck {
    using ChainIds for uint256;

    MultiRewardDistributor mrd;
    Comptroller comptroller;

    address deprecatedMoonwellVelo;

    MToken[] mTokens;

    mapping(MToken => address[] rewardTokens) rewardsConfig;

    function setUp() public override {
        //super.setUp();
        vm.createFork("optimism", 124540329);

        addresses = new Addresses();

        mrd = MultiRewardDistributor(addresses.getAddress("MRD_PROXY"));
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));

        MToken[] memory markets = comptroller.getAllMarkets();

        for (uint256 i = 0; i < markets.length; i++) {
            mTokens.push(markets[i]);

            MultiRewardDistributorCommon.MarketConfig[] memory configs = mrd
                .getAllMarketConfigs(markets[i]);

            for (uint256 j = 0; j < configs.length; j++) {
                rewardsConfig[markets[i]].push(configs[j].emissionToken);
            }
        }

        assertEq(mTokens.length > 0, true, "No markets found");
    }

    function _mintMToken(
        address mToken,
        uint256 amount
    ) internal returns (bool) {
        if (mToken == deprecatedMoonwellVelo) {
            return false;
        }

        address underlying = MErc20(mToken).underlying();

        if (underlying == addresses.getAddress("WETH")) {
            vm.deal(addresses.getAddress("WETH"), amount);
        }
        deal(underlying, address(this), amount);
        IERC20(underlying).approve(mToken, amount);

        assertEq(
            MErc20Delegator(payable(mToken)).mint(amount),
            0,
            "Mint failed"
        );

        return true;
    }

    function _calculateBorrowRewards(
        MToken mToken,
        address emissionToken,
        address sender
    ) private view returns (uint256 expectedRewards) {
        MultiRewardDistributorCommon.MarketConfig memory config = mrd
            .getConfigForMarket(mToken, emissionToken);

        uint256 deltaTimestamp;
        if (vm.getBlockTimestamp() > config.endTime) {
            deltaTimestamp = config.endTime - config.borrowGlobalTimestamp;
        } else {
            deltaTimestamp =
                vm.getBlockTimestamp() -
                config.borrowGlobalTimestamp;
        }

        Exp memory marketBorrowIndex = Exp({mantissa: mToken.borrowIndex()});

        uint256 totalBorrowed = div_(mToken.totalBorrows(), marketBorrowIndex);

        uint256 totalAccrued = mul_(
            deltaTimestamp,
            config.borrowEmissionsPerSec
        );

        Double memory updateIndex = totalBorrowed > 0
            ? fraction(totalAccrued, totalBorrowed)
            : Double({mantissa: 0});

        uint224 newGlobalIndex = safe224(
            add_(Double({mantissa: config.borrowGlobalIndex}), updateIndex)
                .mantissa,
            "new index exceeds 224 bits"
        );

        // User borrow
        uint256 userBorrow = div_(
            mToken.borrowBalanceStored(sender),
            marketBorrowIndex
        );

        // 1e36 is the initial default index
        uint256 deltaUser = sub_(newGlobalIndex, 1e36);

        expectedRewards = mul_(deltaUser, userBorrow) / 1e36;
    }

    function testGuardianCanPauseTemporalGovernor() public {
        TemporalGovernor gov = TemporalGovernor(
            payable(addresses.getAddress("TEMPORAL_GOVERNOR"))
        );

        vm.prank(addresses.getAddress("SECURITY_COUNCIL"));
        gov.togglePause();

        assertTrue(gov.paused());
        assertFalse(gov.guardianPauseAllowed());
        assertEq(gov.lastPauseTime(), block.timestamp);
    }

    function testFuzz_EmissionsAdminCanChangeOwner(
        uint256 mTokenIndex,
        address newOwner
    ) public {
        mTokenIndex = _bound(mTokenIndex, 0, mTokens.length - 1);
        address emissionsAdmin = addresses.getAddress("TEMPORAL_GOVERNOR");
        vm.assume(newOwner != emissionsAdmin);

        vm.startPrank(emissionsAdmin);

        MToken mToken = mTokens[mTokenIndex];

        for (uint256 i = 0; i < rewardsConfig[mToken].length; i++) {
            mrd._updateOwner(mToken, rewardsConfig[mToken][i], newOwner);
        }
        vm.stopPrank();
    }

    function testFuzz_EmissionsAdminCanChangeRewardStream(
        uint256 mTokenIndex,
        address newOwner
    ) public {
        mTokenIndex = _bound(mTokenIndex, 0, mTokens.length - 1);
        address emissionsAdmin = addresses.getAddress("TEMPORAL_GOVERNOR");
        vm.assume(newOwner != emissionsAdmin);

        vm.startPrank(emissionsAdmin);
        MToken mToken = mTokens[mTokenIndex];

        for (uint256 i = 0; i < rewardsConfig[mToken].length; i++) {
            mrd._updateBorrowSpeed(mToken, rewardsConfig[mToken][i], 0.123e18);
        }
        vm.stopPrank();
    }

    function testFuzz_UpdateEmissionConfigEndTimeSuccess(
        uint256 mTokenIndex
    ) public {
        mTokenIndex = _bound(mTokenIndex, 0, mTokens.length - 1);
        MToken mToken = mTokens[mTokenIndex];

        vm.startPrank(addresses.getAddress("TEMPORAL_GOVERNOR"));

        for (uint256 i = 0; i < rewardsConfig[mToken].length; i++) {
            mrd._updateEndTime(
                mToken,
                rewardsConfig[mToken][i],
                block.timestamp + 4 weeks
            );

            MultiRewardDistributorCommon.MarketConfig memory config = mrd
                .getConfigForMarket(mToken, rewardsConfig[mToken][i]);

            assertEq(
                config.endTime,
                block.timestamp + 4 weeks,
                "End time incorrect"
            );
        }
        vm.stopPrank();
    }

    function testFuzz_UpdateEmissionConfigSupplySuccess(
        uint256 mTokenIndex
    ) public {
        mTokenIndex = _bound(mTokenIndex, 0, mTokens.length - 1);

        MToken mToken = mTokens[mTokenIndex];

        for (uint256 i = 0; i < rewardsConfig[mToken].length; i++) {
            vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
            mrd._updateSupplySpeed(
                mToken,
                rewardsConfig[mToken][i],
                1e18 /// pay 1 op per second in rewards
            );

            MultiRewardDistributorCommon.MarketConfig memory config = mrd
                .getConfigForMarket(mToken, rewardsConfig[mToken][i]);

            assertEq(
                config.supplyEmissionsPerSec,
                1e18,
                "Supply emissions incorrect"
            );
        }
    }

    function testFuzz_UpdateEmissionConfigBorrowSuccess(
        uint256 mTokenIndex
    ) public {
        mTokenIndex = _bound(mTokenIndex, 0, mTokens.length - 1);

        MToken mToken = mTokens[mTokenIndex];

        for (uint256 i = 0; i < rewardsConfig[mToken].length; i++) {
            vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
            mrd._updateBorrowSpeed(
                mToken,
                rewardsConfig[mToken][i],
                1e18 /// pay 1 op per second in rewards to borrowers
            );

            MultiRewardDistributorCommon.MarketConfig memory config = mrd
                .getConfigForMarket(mToken, rewardsConfig[mToken][i]);

            assertEq(
                config.borrowEmissionsPerSec,
                1e18,
                "Borrow emissions incorrect"
            );
        }
    }

    function testFuzz_MintMTokenSucceeds(
        uint256 mTokenIndex,
        uint256 mintAmount
    ) public {
        mTokenIndex = _bound(mTokenIndex, 0, mTokens.length - 1);

        MToken mToken = mTokens[mTokenIndex];

        uint256 max = _getMaxSupplyAmount(address(mToken));

        if (max <= 1000e8) {
            return;
        }

        // 1000e8 to 90% of max supply
        mintAmount = _bound(mintAmount, 1000e8, max - (max / 10));

        IERC20 token = IERC20(MErc20(address(mToken)).underlying());

        address sender = address(this);
        uint256 startingTokenBalance = token.balanceOf(address(mToken));

        bool minted = _mintMToken(address(mToken), mintAmount);
        assertEq(minted, true, "Mint failed");

        assertTrue(
            MErc20Delegator(payable(address(mToken))).balanceOf(sender) > 0,
            "mToken balance should be gt 0 after mint"
        ); /// ensure balance is gt 0

        assertEq(
            token.balanceOf(address(mToken)) - startingTokenBalance,
            mintAmount,
            "Underlying balance not updated"
        ); /// ensure underlying balance is sent to mToken
    }

    function testFuzz_BorrowMTokenSucceed(
        uint256 mTokenIndex,
        uint256 mintAmount
    ) public {
        mTokenIndex = _bound(mTokenIndex, 0, mTokens.length - 1);
        MToken mToken = mTokens[mTokenIndex];

        uint256 max = _getMaxSupplyAmount(address(mToken));

        if (max <= 1000e8) {
            return;
        }

        // 1000e8 to 90% of max supply
        mintAmount = _bound(mintAmount, 1000e8, max - (max / 10));

        bool minted = _mintMToken(address(mToken), mintAmount);
        if (!minted) {
            return;
        }

        uint256 expectedCollateralFactor = 0.5e18;
        (, uint256 collateralFactorMantissa) = comptroller.markets(
            address(mToken)
        );

        // check colateral factor
        if (collateralFactorMantissa < expectedCollateralFactor) {
            vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
            comptroller._setCollateralFactor(
                MToken(mToken),
                expectedCollateralFactor
            );
        }

        address sender = address(this);

        uint256 balanceBefore = sender.balance;

        address[] memory _mTokens = new address[](1);
        _mTokens[0] = address(mToken);

        comptroller.enterMarkets(_mTokens);
        assertTrue(
            comptroller.checkMembership(sender, mToken),
            "Membership check failed"
        );

        uint256 borrowAmount = mintAmount / 3;

        assertEq(
            MErc20Delegator(payable(address(mToken))).borrow(borrowAmount),
            0,
            "Borrow failed"
        );

        IERC20 token = IERC20(MErc20(address(mToken)).underlying());

        if (address(token) == addresses.getAddress("WETH")) {
            assertEq(
                sender.balance - balanceBefore,
                borrowAmount,
                "Wrong borrow amount"
            );
        } else {
            assertEq(
                token.balanceOf(sender),
                borrowAmount,
                "Wrong borrow amount"
            );
        }
    }

    function testFuzz_SupplyReceivesRewards(
        uint256 mTokenIndex,
        uint256 supplyAmount,
        uint256 toWarp
    ) public {
        mTokenIndex = _bound(mTokenIndex, 0, mTokens.length - 1);
        MToken mToken = mTokens[mTokenIndex];

        uint256 max = _getMaxSupplyAmount(address(mToken));

        if (max <= 1000e8) {
            return;
        }

        // 1000e8 to 90% of max supply
        supplyAmount = _bound(supplyAmount, 1000e8, max - (max / 10));

        MultiRewardDistributorCommon.RewardInfo[] memory rewards = mrd
            .getOutstandingRewardsForUser(MToken(mToken), address(this));

        // check rewards are zero
        for (uint256 i = 0; i < rewards.length; i++) {
            assertEq(rewards[i].totalAmount, 0, "Rewards not zero");
        }

        bool minted = _mintMToken(address(mToken), supplyAmount);

        if (!minted) {
            return;
        }

        toWarp = _bound(toWarp, 1_000_000, 4 weeks);

        vm.warp(block.timestamp + toWarp);

        for (uint256 i = 0; i < rewardsConfig[mToken].length; i++) {
            uint256 supplyEmissionPerSec = mrd
                .getConfigForMarket(mToken, rewardsConfig[mToken][i])
                .supplyEmissionsPerSec;

            uint256 expectedReward = ((toWarp * supplyEmissionPerSec) /
                MErc20(address(mToken)).totalSupply()) * supplyAmount;

            MultiRewardDistributorCommon.RewardInfo[] memory rewards = mrd
                .getOutstandingRewardsForUser(MToken(mToken), address(this));

            for (uint256 j = 0; j < rewards.length; j++) {
                if (rewards[j].emissionToken != rewardsConfig[mToken][i]) {
                    continue;
                }
                assertApproxEqRel(
                    rewards[j].supplySide,
                    expectedReward,
                    0.1e18,
                    "Supply rewards not correct"
                );
                assertApproxEqRel(
                    rewards[j].totalAmount,
                    expectedReward,
                    0.1e18,
                    "Total rewards not correct"
                );
            }
        }
    }

    function testFuzz_BorrowReceivesRewards(
        uint256 mTokenIndex,
        uint256 supplyAmount,
        uint256 toWarp
    ) public {
        mTokenIndex = _bound(mTokenIndex, 0, mTokens.length - 1);
        MToken mToken = mTokens[mTokenIndex];

        uint256 max = _getMaxSupplyAmount(address(mToken));

        if (max <= 1000e8) {
            return;
        }

        // 1000e8 to 90% of max supply
        supplyAmount = _bound(supplyAmount, 1000e8, max - (max / 10));

        bool minted = _mintMToken(address(mToken), supplyAmount);

        if (!minted) {
            return;
        }

        uint256 expectedCollateralFactor = 0.5e18;
        (, uint256 collateralFactorMantissa) = comptroller.markets(
            address(mToken)
        );

        // check colateral factor
        if (collateralFactorMantissa < expectedCollateralFactor) {
            vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
            comptroller._setCollateralFactor(
                MToken(mToken),
                expectedCollateralFactor
            );
        }

        address sender = address(this);

        {
            address[] memory _mTokens = new address[](1);
            _mTokens[0] = address(mToken);

            comptroller.enterMarkets(_mTokens);
        }

        assertTrue(
            comptroller.checkMembership(sender, MToken(mToken)),
            "Membership check failed"
        );

        uint256 borrowAmount = supplyAmount / 3;

        assertEq(
            comptroller.borrowAllowed(address(mToken), sender, borrowAmount),
            0,
            "Borrow allowed"
        );

        assertEq(
            MErc20Delegator(payable(address(mToken))).borrow(borrowAmount),
            0,
            "Borrow failed"
        );

        vm.warp(vm.getBlockTimestamp() + toWarp);

        for (uint256 i = 0; i < rewardsConfig[mToken].length; i++) {
            uint256 expectedReward = _calculateBorrowRewards(
                MToken(mToken),
                rewardsConfig[mToken][i],
                sender
            );

            assertApproxEqRel(
                mrd
                .getOutstandingRewardsForUser(MToken(mToken), sender)[0]
                    .totalAmount,
                expectedReward,
                0.1e18,
                "Total rewards not correct"
            );

            assertApproxEqRel(
                mrd
                .getOutstandingRewardsForUser(MToken(mToken), address(this))[0]
                    .borrowSide,
                expectedReward,
                0.1e18,
                "Borrow rewards not correct"
            );
        }
    }

    function testFuzz_SupplyBorrowReceiveRewards(
        uint256 mTokenIndex,
        uint256 supplyAmount,
        uint256 toWarp
    ) public {
        toWarp = _bound(toWarp, 1_000_000, 4 weeks);

        mTokenIndex = _bound(mTokenIndex, 0, mTokens.length - 1);
        MToken mToken = mTokens[mTokenIndex];

        uint256 max = _getMaxSupplyAmount(address(mToken));

        if (max <= 1000e8) {
            return;
        }

        // 1000e8 to 90% of max supply
        supplyAmount = _bound(supplyAmount, 1000e8, max - (max / 10));

        bool minted = _mintMToken(address(mToken), supplyAmount);

        if (!minted) {
            return;
        }

        uint256 expectedCollateralFactor = 0.5e18;
        (, uint256 collateralFactorMantissa) = comptroller.markets(
            address(mToken)
        );

        // check colateral factor
        if (collateralFactorMantissa < expectedCollateralFactor) {
            vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
            comptroller._setCollateralFactor(
                MToken(mToken),
                expectedCollateralFactor
            );
        }

        address sender = address(this);

        address[] memory _mTokens = new address[](1);
        _mTokens[0] = address(mToken);

        comptroller.enterMarkets(_mTokens);
        assertTrue(
            comptroller.checkMembership(sender, mToken),
            "Membership check failed"
        );

        {
            uint256 borrowAmount = supplyAmount / 3;

            assertEq(
                MErc20Delegator(payable(address(mToken))).borrow(borrowAmount),
                0,
                "Borrow failed"
            );
        }

        vm.warp(block.timestamp + toWarp);

        for (uint256 i = 0; i < rewardsConfig[mToken].length; i++) {
            MultiRewardDistributorCommon.MarketConfig memory config = mrd
                .getConfigForMarket(MToken(mToken), rewardsConfig[mToken][i]);

            uint256 expectedSupplyReward = (toWarp *
                config.supplyEmissionsPerSec *
                supplyAmount) / MErc20(address(mToken)).totalSupply();

            uint256 expectedBorrowReward = _calculateBorrowRewards(
                MToken(mToken),
                rewardsConfig[mToken][i],
                sender
            );

            assertApproxEqRel(
                mrd
                .getOutstandingRewardsForUser(MToken(mToken), address(this))[0]
                    .totalAmount,
                expectedSupplyReward + expectedBorrowReward,
                0.1e18,
                "Total rewards not correct"
            );

            assertApproxEqRel(
                mrd
                .getOutstandingRewardsForUser(MToken(mToken), address(this))[0]
                    .supplySide,
                expectedSupplyReward,
                0.1e18,
                "Supply rewards not correct"
            );

            assertApproxEqRel(
                mrd
                .getOutstandingRewardsForUser(MToken(mToken), address(this))[0]
                    .borrowSide,
                expectedBorrowReward,
                0.1e18,
                "Borrow rewards not correct"
            );
        }
    }

    // function testFuzz_LiquidateAccountReceiveRewards(
    //     uint256 mTokenIndex,
    //     uint256 mintAmount,
    //     uint256 toWarp
    // ) public {
    //     Configs.CTokenConfiguration[] memory mTokensConfig = proposal
    //         .getCTokenConfigurations(block.chainid);

    //     mTokenIndex = _bound(mTokenIndex, 0, mTokensConfig.length - 1);

    //     toWarp = _bound(toWarp, 1_000_000, 4 weeks);

    //     address mToken = addresses.getAddress(
    //         mTokensConfig[mTokenIndex].addressesString
    //     );

    //     vm.warp(MToken(mToken).accrualBlockTimestamp());

    //     address token = addresses.getAddress(
    //         mTokensConfig[mTokenIndex].tokenAddressName
    //     );

    //     mintAmount = bound(
    //         mintAmount,
    //         1 * 10 ** IERC20(token).decimals(),
    //         100_000_000 * 10 ** IERC20(token).decimals()
    //     );

    //     bool minted = _mintMToken(mToken, mintAmount);
    //     if (!minted) {
    //         return;
    //     }

    //     MultiRewardDistributorCommon.RewardInfo[] memory rewardsBefore = mrd
    //         .getOutstandingRewardsForUser(MToken(mToken), address(this));

    //     // borrow
    //     uint256 borrowAmount = mintAmount / 3;

    //     {
    //         uint256 expectedCollateralFactor = 0.5e18;
    //         (, uint256 collateralFactorMantissa) = comptroller.markets(mToken);
    //         // check colateral factor
    //         if (collateralFactorMantissa < expectedCollateralFactor) {
    //             vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
    //             comptroller._setCollateralFactor(
    //                 MToken(mToken),
    //                 expectedCollateralFactor
    //             );
    //         }

    //         address[] memory mTokens = new address[](1);
    //         mTokens[0] = mToken;

    //         comptroller.enterMarkets(mTokens);

    //         assertTrue(
    //             comptroller.checkMembership(address(this), MToken(mToken)),
    //             "Membership check failed"
    //         );
    //     }

    //     assertEq(
    //         MErc20Delegator(payable(mToken)).borrow(borrowAmount),
    //         0,
    //         "Borrow failed"
    //     );

    //     vm.warp(vm.getBlockTimestamp() + toWarp);

    //     MultiRewardDistributorCommon.MarketConfig memory config = mrd
    //         .getConfigForMarket(
    //             MToken(mToken),
    //             emissionsConfig[mToken][0].emissionToken
    //         );

    //     uint256 expectedSupplyReward;
    //     {
    //         uint256 balance = MToken(mToken).balanceOf(address(this)) / 3;

    //         expectedSupplyReward =
    //             ((toWarp * config.supplyEmissionsPerSec) * balance) /
    //             MToken(mToken).totalSupply();
    //     }

    //     uint256 expectedBorrowReward = _calculateBorrowRewards(
    //         MToken(mToken),
    //         emissionsConfig[mToken][0].emissionToken,
    //         address(this)
    //     );

    //     if (token != addresses.getAddress("WETH")) {
    //         /// borrower is now underwater on loan
    //         deal(
    //             address(MErc20(mToken)),
    //             address(this),
    //             MErc20(mToken).balanceOf(address(this)) / 2
    //         );
    //     } else {
    //         vm.deal(addresses.getAddress("WETH"), address(this).balance / 2);
    //         /// borrower is now underwater on loan
    //         deal(
    //             address(MErc20(mToken)),
    //             address(this),
    //             MErc20(mToken).balanceOf(address(this)) / 2
    //         );
    //     }
    //     {
    //         (uint256 err, uint256 liquidity, uint256 shortfall) = comptroller
    //             .getHypotheticalAccountLiquidity(
    //                 address(this),
    //                 address(MErc20(mToken)),
    //                 0,
    //                 0
    //             );

    //         assertEq(err, 0, "Error in hypothetical liquidity calculation");
    //         assertEq(liquidity, 0, "Liquidity not 0");
    //         assertGt(shortfall, 0, "Shortfall not gt 0");
    //     }

    //     uint256 repayAmt = borrowAmount / 2;

    //     deal(token, address(100_000_000), repayAmt);

    //     vm.startPrank(address(100_000_000));

    //     IERC20(token).approve(address(MErc20(mToken)), repayAmt);
    //     assertEq(
    //         MErc20Delegator(payable(mToken)).liquidateBorrow(
    //             address(this),
    //             repayAmt,
    //             MErc20(mToken)
    //         ),
    //         0,
    //         "Liquidation failed"
    //     );

    //     vm.stopPrank();

    //     MultiRewardDistributorCommon.RewardInfo[] memory rewardsAfter = mrd
    //         .getOutstandingRewardsForUser(MToken(mToken), address(this));

    //     assertApproxEqRel(
    //         rewardsAfter[0].totalAmount,
    //         rewardsBefore[0].totalAmount +
    //             expectedSupplyReward +
    //             expectedBorrowReward,
    //         0.1e18,
    //         "Total rewards wrong"
    //     );

    //     assertApproxEqRel(
    //         rewardsAfter[0].borrowSide,
    //         rewardsBefore[0].borrowSide + expectedBorrowReward,
    //         0.1e18,
    //         "Borrow side rewards wrong"
    //     );

    //     assertApproxEqRel(
    //         rewardsAfter[0].supplySide,
    //         rewardsBefore[0].supplySide + expectedSupplyReward,
    //         1e17,
    //         "Supply side rewards not within 10%"
    //     );
    // }

    function _getMaxSupplyAmount(
        address mToken
    ) internal view returns (uint256) {
        uint256 supplyCap = comptroller.supplyCaps(address(mToken));

        uint256 totalCash = MToken(mToken).getCash();
        uint256 totalBorrows = MToken(mToken).totalBorrows();
        uint256 totalReserves = MToken(mToken).totalReserves();

        uint256 totalSupplies = (totalCash + totalBorrows) - totalReserves;

        if (totalSupplies >= supplyCap) {
            return 0;
        }

        return supplyCap - totalSupplies;
    }

    receive() external payable {}
}
