//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20Metadata as IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "@forge-std/Test.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {WETH9} from "@protocol/router/IWETH.sol";
import {Unitroller} from "@protocol/Unitroller.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MarketBase} from "@test/utils/MarketBase.sol";
import {WETHRouter} from "@protocol/router/WETHRouter.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {MarketAddChecker} from "@protocol/governance/MarketAddChecker.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {ChainIds, OPTIMISM_CHAIN_ID} from "@utils/ChainIds.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract SupplyBorrowLiveSystem is Test, PostProposalCheck {
    using ChainIds for uint256;

    MultiRewardDistributor mrd;
    Comptroller comptroller;

    MToken[] mTokens;
    MarketAddChecker checker;
    MarketBase public marketBase;

    mapping(MToken => address[] rewardTokens) rewardsConfig;

    function setUp() public override {
        uint256 primaryForkId = vm.envUint("PRIMARY_FORK_ID");
        super.setUp();

        vm.selectFork(primaryForkId);

        mrd = MultiRewardDistributor(addresses.getAddress("MRD_PROXY"));
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        checker = MarketAddChecker(addresses.getAddress("MARKET_ADD_CHECKER"));
        marketBase = new MarketBase(comptroller);

        MToken[] memory markets = comptroller.getAllMarkets();

        MToken deprecatedMoonwellVelo = MToken(
            addresses.getAddress("DEPRECATED_MOONWELL_VELO", OPTIMISM_CHAIN_ID)
        );

        for (uint256 i = 0; i < markets.length; i++) {
            if (markets[i] == deprecatedMoonwellVelo) {
                continue;
            }
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
        address user,
        address mToken,
        uint256 amount
    ) internal {
        address underlying = MErc20(mToken).underlying();

        if (underlying == addresses.getAddress("WETH")) {
            vm.deal(addresses.getAddress("WETH"), amount);
        }
        deal(underlying, user, amount);
        vm.startPrank(user);

        IERC20(underlying).approve(mToken, amount);

        assertEq(
            MErc20Delegator(payable(mToken)).mint(amount),
            0,
            "Mint failed"
        );
        vm.stopPrank();
    }

    function _calculateSupplyRewards(
        MToken mToken,
        address emissionToken,
        uint256 amount,
        uint256 timeBefore,
        uint256 timeAfter
    ) private view returns (uint256 expectedRewards) {
        MultiRewardDistributorCommon.MarketConfig memory marketConfig = mrd
            .getConfigForMarket(mToken, emissionToken);

        uint256 endTime = marketConfig.endTime;

        uint256 timeDelta;

        if (timeAfter > endTime) {
            if (timeBefore > endTime) {
                timeDelta = 0;
            } else {
                timeDelta = endTime - timeBefore;
            }
        } else {
            timeDelta = timeAfter - timeBefore;
        }

        expectedRewards =
            (timeDelta * marketConfig.supplyEmissionsPerSec * amount) /
            MErc20(address(mToken)).totalSupply();
    }

    function _calculateBorrowRewards(
        MToken mToken,
        address emissionToken,
        uint256 amount,
        uint256 timeBefore,
        uint256 timeAfter
    ) private view returns (uint256 expectedRewards) {
        MultiRewardDistributorCommon.MarketConfig memory config = mrd
            .getConfigForMarket(mToken, emissionToken);

        uint256 endTime = config.endTime;

        uint256 timeDelta;

        if (timeAfter > endTime) {
            if (timeBefore > endTime) {
                timeDelta = 0;
            } else {
                timeDelta = endTime - timeBefore;
            }
        } else {
            timeDelta = timeAfter - timeBefore;
        }

        expectedRewards =
            (timeDelta * config.borrowEmissionsPerSec * amount) /
            mToken.totalBorrows();
    }

    function testAllMarketsNonZeroTotalSupply() public view {
        MToken[] memory markets = comptroller.getAllMarkets();

        for (uint256 i = 0; i < markets.length; i++) {
            assertGt(markets[i].totalSupply(), 2_000, "empty market");
            assertGt(markets[i].balanceOf(address(0)), 0, "no burnt tokens");
        }
    }

    function testMarketAddChecker() public view {
        checker.checkMarketAdd(addresses.getAddress("MOONWELL_cbETH"));
        checker.checkAllMarkets(addresses.getAddress("UNITROLLER"));
    }

    function _mintMTokenSucceed(
        uint256 mTokenIndex,
        uint256 mintAmount
    ) private {
        MToken mToken = mTokens[mTokenIndex];

        uint256 max = marketBase.getMaxSupplyAmount(mToken);

        if (max <= 10e8) {
            return;
        }

        mintAmount = _bound(mintAmount, 10e8, max);

        IERC20 token = IERC20(MErc20(address(mToken)).underlying());

        address sender = address(this);
        uint256 startingTokenBalance = token.balanceOf(address(mToken));

        _mintMToken(address(this), address(mToken), mintAmount);

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

    function testFuzzMintMTokenSucceed(uint256 mintAmount) public {
        for (uint256 i = 0; i < mTokens.length; i++) {
            _mintMTokenSucceed(i, mintAmount);
        }
    }

    function _borrowMTokenSucceed(
        uint256 mTokenIndex,
        uint256 mintAmount
    ) private {
        MToken mToken = mTokens[mTokenIndex];

        uint256 max = marketBase.getMaxSupplyAmount(mToken);

        if (max <= 10e8) {
            return;
        }

        mintAmount = _bound(mintAmount, 10e8, max);

        _mintMToken(address(this), address(mToken), mintAmount);

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

        uint256 borrowAmount = marketBase.getMaxUserBorrowAmount(
            mToken,
            address(this)
        );

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

    function testFuzzBorrowMTokenSucceed(uint256 mintAmount) public {
        for (uint256 i = 0; i < mTokens.length; i++) {
            _borrowMTokenSucceed(i, mintAmount);
        }
    }

    function _supplyReceivesRewards(
        uint256 mTokenIndex,
        uint256 supplyAmount,
        uint256 toWarp
    ) public {
        MToken mToken = mTokens[mTokenIndex];

        uint256 max = marketBase.getMaxSupplyAmount(mToken);

        if (max <= 1000e8) {
            return;
        }

        // 1000e8 to 90% of max supply
        supplyAmount = _bound(supplyAmount, 1000e8, max);

        _mintMToken(address(this), address(mToken), supplyAmount);

        toWarp = _bound(toWarp, 1_000_000, 4 weeks);

        uint256 timeBefore = vm.getBlockTimestamp();
        vm.warp(timeBefore + toWarp);
        uint256 timeAfter = vm.getBlockTimestamp();

        for (uint256 i = 0; i < rewardsConfig[mToken].length; i++) {
            uint256 expectedReward = _calculateSupplyRewards(
                MToken(mToken),
                rewardsConfig[mToken][i],
                mToken.balanceOf(address(this)),
                timeBefore,
                timeAfter
            );

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

    function testFuzzSupplyReceivesRewards(
        uint256 supplyAmount,
        uint256 toWarp
    ) public {
        for (uint256 i = 0; i < mTokens.length; i++) {
            _supplyReceivesRewards(i, supplyAmount, toWarp);
        }
    }

    function _borrowReceivesRewards(
        uint256 mTokenIndex,
        uint256 supplyAmount,
        uint256 toWarp
    ) private {
        MToken mToken = mTokens[mTokenIndex];

        uint256 max = marketBase.getMaxSupplyAmount(mToken);

        if (max <= 1000e8) {
            return;
        }

        toWarp = _bound(toWarp, 1_000_000, 4 weeks);
        supplyAmount = _bound(supplyAmount, 1000e8, max);

        _mintMToken(address(this), address(mToken), supplyAmount);

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

        uint256 borrowAmount = supplyAmount / 3 >
            marketBase.getMaxUserBorrowAmount(mToken, address(this))
            ? marketBase.getMaxUserBorrowAmount(mToken, address(this))
            : supplyAmount / 3;

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

        uint256 timeBefore = vm.getBlockTimestamp();
        vm.warp(timeBefore + toWarp);
        uint256 timeAfter = vm.getBlockTimestamp();

        for (uint256 i = 0; i < rewardsConfig[mToken].length; i++) {
            uint256 expectedReward = _calculateBorrowRewards(
                MToken(mToken),
                rewardsConfig[mToken][i],
                mToken.borrowBalanceStored(sender),
                timeBefore,
                timeAfter
            );
            MultiRewardDistributorCommon.RewardInfo[] memory rewards = mrd
                .getOutstandingRewardsForUser(MToken(mToken), sender);

            for (uint256 j = 0; j < rewards.length; j++) {
                if (rewards[j].emissionToken != rewardsConfig[mToken][i]) {
                    continue;
                }
                assertApproxEqRel(
                    rewards[j].borrowSide,
                    expectedReward,
                    0.1e18,
                    "Borrow rewards not correct"
                );
            }
        }
    }

    function testFuzzBorrowReceivesRewards(
        uint256 supplyAmount,
        uint256 toWarp
    ) public {
        for (uint256 i = 0; i < mTokens.length; i++) {
            _borrowReceivesRewards(i, supplyAmount, toWarp);
        }
    }

    function _supplyBorrowReceiveRewards(
        uint256 mTokenIndex,
        uint256 supplyAmount,
        uint256 toWarp
    ) private {
        MToken mToken = mTokens[mTokenIndex];

        uint256 max = marketBase.getMaxSupplyAmount(mToken);

        if (max <= 1e12) {
            return;
        }

        toWarp = _bound(toWarp, 1_000_000, 4 weeks);
        supplyAmount = _bound(supplyAmount, 1e12, max);

        _mintMToken(address(this), address(mToken), supplyAmount);

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
            uint256 borrowAmount = marketBase.getMaxUserBorrowAmount(
                mToken,
                address(this)
            );

            assertEq(
                MErc20Delegator(payable(address(mToken))).borrow(borrowAmount),
                0,
                "Borrow failed"
            );
        }

        uint256 timeBefore = vm.getBlockTimestamp();
        vm.warp(timeBefore + toWarp);
        uint256 timeAfter = vm.getBlockTimestamp();

        for (uint256 i = 0; i < rewardsConfig[mToken].length; i++) {
            uint256 expectedSupplyReward = _calculateSupplyRewards(
                MToken(mToken),
                rewardsConfig[mToken][i],
                mToken.balanceOf(sender),
                timeBefore,
                timeAfter
            );

            uint256 expectedBorrowReward = _calculateBorrowRewards(
                MToken(mToken),
                rewardsConfig[mToken][i],
                mToken.borrowBalanceStored(sender),
                timeBefore,
                timeAfter
            );

            MultiRewardDistributorCommon.RewardInfo[] memory rewards = mrd
                .getOutstandingRewardsForUser(MToken(mToken), sender);

            for (uint256 j = 0; j < rewards.length; j++) {
                if (rewards[j].emissionToken != rewardsConfig[mToken][i]) {
                    continue;
                }

                assertApproxEqRel(
                    rewards[j].supplySide,
                    expectedSupplyReward,
                    0.1e18,
                    "Supply rewards not correct"
                );

                assertApproxEqRel(
                    rewards[j].borrowSide,
                    expectedBorrowReward,
                    0.1e18,
                    "Borrow rewards not correct"
                );

                assertApproxEqRel(
                    rewards[j].totalAmount,
                    expectedSupplyReward + expectedBorrowReward,
                    0.1e18,
                    "Total rewards not correct"
                );
            }
        }
    }

    function testFuzzSupplyBorrowReceiveRewards(
        uint256 supplyAmount,
        uint256 toWarp
    ) public {
        for (uint256 i = 0; i < mTokens.length; i++) {
            _supplyBorrowReceiveRewards(i, supplyAmount, toWarp);
        }
    }

    mapping(address token => uint256 borrowRewardPerToken) borrowRewardPerToken;
    mapping(address token => uint256 supplyRewardPerToken) supplyRewardPerToken;

    function _liquidateAccountReceiveRewards(
        uint256 mTokenIndex,
        uint256 mintAmount,
        uint256 toWarp
    ) private {
        MToken mToken = mTokens[mTokenIndex];

        uint256 max = marketBase.getMaxSupplyAmount(mToken);

        if (max <= 10e8) {
            return;
        }

        toWarp = _bound(toWarp, 1_000_000, 4 weeks);

        mintAmount = _bound(mintAmount, 10e8, max);

        // uses different users to each market ensuring that previous liquidations do not impact this test
        address user = address(uint160(mTokenIndex + 123));

        _mintMToken(user, address(mToken), mintAmount);

        {
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

            address[] memory _mTokens = new address[](1);
            _mTokens[0] = address(mToken);

            vm.startPrank(user);
            comptroller.enterMarkets(_mTokens);

            assertTrue(
                comptroller.checkMembership(user, MToken(mToken)),
                "Membership check failed"
            );
        }

        if (mintAmount / 3 > marketBase.getMaxUserBorrowAmount(mToken, user)) {
            return;
        }

        assertEq(
            MErc20Delegator(payable(address(mToken))).borrow(mintAmount / 3),
            0,
            "Borrow failed"
        );

        vm.stopPrank();

        uint256 timeBefore = vm.getBlockTimestamp();
        vm.warp(timeBefore + toWarp);
        uint256 timeAfter = vm.getBlockTimestamp();

        for (uint256 i = 0; i < rewardsConfig[mToken].length; i++) {
            supplyRewardPerToken[
                rewardsConfig[mToken][i]
            ] = _calculateSupplyRewards(
                MToken(mToken),
                rewardsConfig[mToken][i],
                mToken.balanceOf(user) / 3,
                timeBefore,
                timeAfter
            );

            borrowRewardPerToken[
                rewardsConfig[mToken][i]
            ] = _calculateBorrowRewards(
                MToken(mToken),
                rewardsConfig[mToken][i],
                mToken.borrowBalanceStored(user),
                timeBefore,
                timeAfter
            );
        }

        /// borrower is now underwater on loan
        deal(address(mToken), user, mToken.balanceOf(user) / 3);

        {
            (uint256 err, uint256 liquidity, uint256 shortfall) = comptroller
                .getHypotheticalAccountLiquidity(user, address(mToken), 0, 0);

            assertEq(err, 0, "Error in hypothetical liquidity calculation");
            assertEq(liquidity, 0, "Liquidity not 0");
            assertGt(shortfall, 0, "Shortfall not gt 0");
        }

        {
            uint256 repayAmount = mintAmount / 6;
            deal(
                MErc20(address(mToken)).underlying(),
                address(100_000_000),
                repayAmount
            );

            vm.startPrank(address(100_000_000));
            IERC20(MErc20(address(mToken)).underlying()).approve(
                address(mToken),
                repayAmount
            );

            assertEq(
                MErc20Delegator(payable(address(mToken))).liquidateBorrow(
                    user,
                    repayAmount,
                    MErc20(address(mToken))
                ),
                0,
                "Liquidation failed"
            );

            vm.stopPrank();
        }

        MultiRewardDistributorCommon.RewardInfo[] memory rewardsPaid = mrd
            .getOutstandingRewardsForUser(MToken(mToken), user);

        for (uint256 j = 0; j < rewardsPaid.length; j++) {
            uint256 expectedSupplyReward = supplyRewardPerToken[
                rewardsPaid[j].emissionToken
            ];
            uint256 expectedBorrowReward = borrowRewardPerToken[
                rewardsPaid[j].emissionToken
            ];

            assertApproxEqRel(
                rewardsPaid[j].supplySide,
                expectedSupplyReward,
                0.1e18,
                "Supply rewards not correct"
            );

            assertApproxEqRel(
                rewardsPaid[j].borrowSide,
                expectedBorrowReward,
                0.1e18,
                "Borrow rewards not correct"
            );

            assertApproxEqRel(
                rewardsPaid[j].totalAmount,
                expectedSupplyReward + expectedBorrowReward,
                0.1e18,
                "Total rewards not correct"
            );
        }
    }

    function testFuzzLiquidateAccountReceiveRewards(
        uint256 mintAmount,
        uint256 toWarp
    ) public {
        for (uint256 i = 0; i < mTokens.length; i++) {
            _liquidateAccountReceiveRewards(i, mintAmount, toWarp);
        }
    }

    function testRepayBorrowBehalfWethRouter() public {
        MToken mToken = MToken(addresses.getAddress("MOONWELL_WETH"));
        uint256 mintAmount = marketBase.getMaxSupplyAmount(mToken);

        _mintMToken(address(this), address(mToken), mintAmount);

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

        uint256 borrowAmount = marketBase.getMaxUserBorrowAmount(
            mToken,
            address(this)
        );

        assertEq(
            MErc20Delegator(payable(address(mToken))).borrow(borrowAmount),
            0,
            "Borrow failed"
        );

        address mweth = addresses.getAddress("MOONWELL_WETH");
        WETH9 weth = WETH9(addresses.getAddress("WETH"));

        WETHRouter router = new WETHRouter(
            weth,
            MErc20(addresses.getAddress("MOONWELL_WETH"))
        );

        vm.deal(address(this), borrowAmount);

        router.repayBorrowBehalf{value: borrowAmount}(address(this));

        assertEq(MErc20(mweth).borrowBalanceStored(address(this)), 0); /// fully repaid
    }

    function testRepayMoreThanBorrowBalanceWethRouter() public {
        MToken mToken = MToken(addresses.getAddress("MOONWELL_WETH"));
        uint256 mintAmount = marketBase.getMaxSupplyAmount(mToken);

        _mintMToken(address(this), address(mToken), mintAmount);

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

        uint256 borrowAmount = marketBase.getMaxUserBorrowAmount(
            mToken,
            address(this)
        );

        assertEq(
            MErc20Delegator(payable(address(mToken))).borrow(borrowAmount),
            0,
            "Borrow failed"
        );

        uint256 borrowRepayAmount = borrowAmount * 2;

        address mweth = addresses.getAddress("MOONWELL_WETH");
        WETH9 weth = WETH9(addresses.getAddress("WETH"));

        WETHRouter router = new WETHRouter(
            weth,
            MErc20(addresses.getAddress("MOONWELL_WETH"))
        );

        vm.deal(address(this), borrowRepayAmount);

        router.repayBorrowBehalf{value: borrowRepayAmount}(address(this));

        assertEq(MErc20(mweth).borrowBalanceStored(address(this)), 0); /// fully repaid
        assertEq(address(this).balance, borrowRepayAmount / 2); /// excess eth returned
    }

    function testMintWithRouter() public {
        WETH9 weth = WETH9(addresses.getAddress("WETH"));
        MErc20 mToken = MErc20(addresses.getAddress("MOONWELL_WETH"));
        uint256 startingMTokenWethBalance = weth.balanceOf(address(mToken));

        uint256 mintAmount = marketBase.getMaxSupplyAmount(mToken);
        vm.deal(address(this), mintAmount);

        WETHRouter router = new WETHRouter(
            weth,
            MErc20(addresses.getAddress("MOONWELL_WETH"))
        );

        router.mint{value: mintAmount}(address(this));

        assertEq(address(this).balance, 0, "incorrect test contract eth value");
        assertEq(
            weth.balanceOf(address(mToken)),
            mintAmount + startingMTokenWethBalance,
            "incorrect mToken weth value after mint"
        );

        mToken.redeem(type(uint256).max);

        assertApproxEqRel(
            address(this).balance,
            mintAmount,
            1e15, /// tiny loss due to rounding down
            "incorrect test contract eth value after redeem"
        );
        assertApproxEqRel(
            startingMTokenWethBalance,
            weth.balanceOf(address(mToken)),
            1e15, /// tiny gain due to rounding down in protocol's favor
            "incorrect mToken weth value after redeem"
        );
    }

    function _supplyingOverSupplyCapFails(uint256 mTokenIndex) private {
        MToken mToken = mTokens[mTokenIndex];

        uint256 amount = marketBase.getMaxSupplyAmount(mToken) + 1;

        if (amount == 1) {
            return;
        }

        address underlying = MErc20(address(mToken)).underlying();

        if (underlying == addresses.getAddress("WETH")) {
            vm.deal(addresses.getAddress("WETH"), amount);
        }

        deal(underlying, address(this), amount);
        IERC20(underlying).approve(address(mToken), amount);

        vm.expectRevert("market supply cap reached");
        MErc20Delegator(payable(address(mToken))).mint(amount);
    }

    function test_SupplyingOverSupplyCapFails() public {
        for (uint256 i = 0; i < mTokens.length; i++) {
            _supplyingOverSupplyCapFails(i);
        }
    }

    function _borrowingOverBorrowCapFails(uint256 mTokenIndex) private {
        MToken mToken = mTokens[mTokenIndex];

        uint256 mintAmount = marketBase.getMaxSupplyAmount(mToken);

        if (mintAmount == 0) {
            return;
        }

        _mintMToken(address(this), address(mToken), mintAmount);

        address[] memory _mTokens = new address[](1);
        _mTokens[0] = address(mToken);

        comptroller.enterMarkets(_mTokens);

        uint256 amount = marketBase.getMaxBorrowAmount(mToken) + 1;

        if (amount == 1 || amount > type(uint128).max) {
            return;
        }

        address underlying = MErc20(address(mToken)).underlying();

        if (underlying == addresses.getAddress("WETH")) {
            vm.deal(addresses.getAddress("WETH"), amount);
        }

        deal(underlying, address(this), amount);
        IERC20(underlying).approve(address(mToken), amount);

        vm.expectRevert("market borrow cap reached");
        MErc20Delegator(payable(address(mToken))).borrow(amount);
    }

    function testBorrowingOverBorrowCapFails() public {
        for (uint256 i = 0; i < mTokens.length; i++) {
            _borrowingOverBorrowCapFails(i);
        }
    }

    function _oraclesReturnCorrectValues(uint256 mTokenIndex) private view {
        MToken mToken = mTokens[mTokenIndex];

        ChainlinkOracle oracle = ChainlinkOracle(
            addresses.getAddress("CHAINLINK_ORACLE")
        );

        assertGt(
            oracle.getUnderlyingPrice(mToken),
            1,
            "oracle price must be non zero"
        );
    }

    function testOraclesReturnCorrectValues() public view {
        for (uint256 i = 0; i < mTokens.length; i++) {
            _oraclesReturnCorrectValues(i);
        }
    }

    receive() external payable {}
}
