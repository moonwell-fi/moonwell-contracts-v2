// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {WETH9} from "@protocol/router/IWETH.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {WETHRouter} from "@protocol/router/WETHRouter.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {TestProposals} from "@proposals/TestProposals.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";
import {ForkID} from "@utils/Enums.sol";

contract LiveSystemBasePostProposalTest is PostProposalCheck, Configs {
    MultiRewardDistributor mrd;
    Comptroller comptroller;
    WETHRouter router;
    ChainlinkOracle oracle;
    WETH9 weth;
    address public well;

    function setUp() public override {
        super.setUp();

        vm.selectFork(uint256(ForkID.Base));

        mrd = MultiRewardDistributor(addresses.getAddress("MRD_PROXY"));
        well = addresses.getAddress("GOVTOKEN");
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        router = WETHRouter(payable(addresses.getAddress("WETH_ROUTER")));
        oracle = ChainlinkOracle(addresses.getAddress("CHAINLINK_ORACLE"));
        weth = WETH9(addresses.getAddress("WETH"));
    }

    function testOraclesReturnCorrectValues() public view {
        Configs.CTokenConfiguration[]
            memory cTokenConfigs = getCTokenConfigurations(block.chainid);
        unchecked {
            for (uint256 i = 0; i < cTokenConfigs.length; i++) {
                assertGt(
                    oracle.getUnderlyingPrice(
                        MToken(
                            addresses.getAddress(
                                cTokenConfigs[i].addressesString
                            )
                        )
                    ),
                    1,
                    "oracle price must be non zero"
                );
            }
        }
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

    function testUpdateEmissionConfigSupplyUsdcSuccess() public {
        vm.startPrank(addresses.getAddress("TEMPORAL_GOVERNOR"));
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
                addresses.getAddress("GOVTOKEN")
            );

        assertEq(config.owner, addresses.getAddress("EMISSIONS_ADMIN"));
        assertEq(config.emissionToken, well);
        assertEq(
            config.supplyEmissionsPerSec,
            1e18,
            "supply emissions per second incorrect"
        );
    }

    function testUpdateEmissionConfigBorrowUsdcSuccess() public {
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
                addresses.getAddress("GOVTOKEN")
            );

        assertEq(config.owner, addresses.getAddress("EMISSIONS_ADMIN"));
        assertEq(config.emissionToken, well, "emission token not well");
        assertEq(
            config.borrowEmissionsPerSec,
            1e18,
            "well per second incorrect"
        );
    }

    function testMintMWethMTokenSucceeds() public {
        address sender = address(this);
        uint256 mintAmount = 100e18;

        IERC20 token = IERC20(addresses.getAddress("WETH"));
        MErc20Delegator mToken = MErc20Delegator(
            payable(addresses.getAddress("MOONWELL_WETH"))
        );
        uint256 startingTokenBalance = token.balanceOf(address(mToken));

        vm.deal(sender, mintAmount); /// fund with raw eth
        token.approve(address(mToken), mintAmount);

        router.mint{value: mintAmount}(address(this)); /// ensure successful mint
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
                MToken(addresses.getAddress("MOONWELL_WETH"))
            )
        ); /// ensure sender and mToken is in market

        (uint256 err, uint256 liquidity, uint256 shortfall) = comptroller
            .getAccountLiquidity(address(this));

        assertEq(err, 0, "Error getting account liquidity");
        assertGt(liquidity, mintAmount * 1_000, "liquidity not correct");
        assertEq(shortfall, 0, "Incorrect shortfall");

        comptroller.exitMarket(address(mToken));
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

        address[] memory mTokens = new address[](1);
        mTokens[0] = address(mToken);

        comptroller.enterMarkets(mTokens);
        assertTrue(
            comptroller.checkMembership(
                sender,
                MToken(addresses.getAddress("MOONWELL_USDBC"))
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

    function testMintcbETHmTokenSucceeds() public {
        address sender = address(this);
        uint256 mintAmount = 100e18;

        IERC20 token = IERC20(addresses.getAddress("cbETH"));
        MErc20Delegator mToken = MErc20Delegator(
            payable(addresses.getAddress("MOONWELL_cbETH"))
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
                MToken(addresses.getAddress("MOONWELL_cbETH"))
            )
        ); /// ensure sender and mToken is in market

        (uint256 err, uint256 liquidity, uint256 shortfall) = comptroller
            .getAccountLiquidity(address(this));

        assertEq(err, 0, "Error getting account liquidity");
        assertGt(liquidity, mintAmount * 1200, "liquidity incorrect");
        assertEq(shortfall, 0, "Incorrect shortfall");

        comptroller.exitMarket(address(mToken));
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
        vm.deal(sender, 0); /// set sender's WETH balance to 0 ether

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

        assertEq(mToken.borrow(borrowAmount), 0, "unsuccessful borrow"); /// ensure successful borrow
        (
            ,
            uint256 liquidityAfterBorrow,
            uint256 shortfallAfterBorrow
        ) = comptroller.getAccountLiquidity(sender);

        assertEq(
            sender.balance,
            borrowAmount,
            "incorrect ether amount borrowed"
        ); /// ensure eth balance is correct

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
        assertLe(
            rewards[0].totalAmount,
            toWarp * 1e18,
            "Total rewards not LT warp time * 1e18"
        );
        assertLe(
            rewards[0].supplySide,
            toWarp * 1e18,
            "Supply side rewards not LT warp time * 1e18"
        );
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

        assertEq(rewards[0].emissionToken, well, "incorrect emission token");
        /// ensure rewards are less than warp time * 1e18 as rounding
        /// down happens + temporal governor owns mTokens in the pool
        assertLe(
            rewards[0].totalAmount,
            toWarp * 1e18 + toWarp,
            "Total rewards not less than warp time * 1e18"
        );
        assertLe(
            rewards[0].borrowSide,
            toWarp * 1e18,
            "Borrow side rewards not less than warp time * 1e18"
        );
    }

    function testSupplyBorrowUsdcReceivesRewards(uint256 toWarp) public {
        toWarp = _bound(toWarp, 1_000_000, 4 weeks);

        testUpdateEmissionConfigBorrowUsdcSuccess();
        testUpdateEmissionConfigSupplyUsdcSuccess();
        testBorrowMTokenSucceeds();

        vm.warp(block.timestamp + toWarp);

        MultiRewardDistributorCommon.RewardInfo[] memory rewards = mrd
            .getOutstandingRewardsForUser(
                MToken(addresses.getAddress("MOONWELL_USDBC")),
                address(this)
            );

        assertEq(rewards[0].emissionToken, well);
        assertLe(
            rewards[0].totalAmount,
            toWarp * 1e18 + toWarp * 1e18,
            "Total rewards not less than warp time * reward speed"
        );
        assertLe(
            rewards[0].borrowSide,
            toWarp * 1e18,
            "Borrow side rewards not less than warp time * reward speed"
        );
        assertLe(
            rewards[0].supplySide,
            toWarp * 1e18,
            "Supply side rewards not less than warp time * reward speed"
        );
    }

    function testLiquidateAccountReceivesRewards(uint256 toWarp) public {
        toWarp = _bound(toWarp, 1_000_000, 4 weeks);

        testUpdateEmissionConfigBorrowUsdcSuccess();
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
            toWarp * 1e18 * 2,
            rewards[0].totalAmount,
            "Total rewards not less than or equal to upper bound"
        );
        assertLe(
            rewards[0].borrowSide,
            toWarp * 1e18,
            "Borrow side rewards not less than upper bound"
        );
        assertLe(
            rewards[0].supplySide,
            (toWarp * 1e18) / 2,
            "Supply side rewards not less than upper bound"
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

    function testAddLiquidityMultipleAssets() public {
        testMintMTokenSucceeds();
        testMintcbETHmTokenSucceeds();
        testMintMWethMTokenSucceeds();

        address[] memory mTokens = new address[](3);
        mTokens[0] = addresses.getAddress("MOONWELL_USDBC");
        mTokens[1] = addresses.getAddress("MOONWELL_WETH");
        mTokens[2] = addresses.getAddress("MOONWELL_cbETH");

        uint256[] memory errors = comptroller.enterMarkets(mTokens);
        for (uint256 i = 0; i < errors.length; i++) {
            assertEq(errors[i], 0);
        }

        MToken[] memory assets = comptroller.getAssetsIn(address(this));

        assertEq(address(assets[0]), addresses.getAddress("MOONWELL_USDBC"));
        assertEq(address(assets[1]), addresses.getAddress("MOONWELL_WETH"));
        assertEq(address(assets[2]), addresses.getAddress("MOONWELL_cbETH"));
    }

    function testAddCloseToMaxLiquidity() public {
        testAddLiquidityMultipleAssets();

        uint256 usdcMintAmount = _getMaxSupplyAmount(
            addresses.getAddress("MOONWELL_USDBC")
        );
        uint256 wethMintAmount = _getMaxSupplyAmount(
            addresses.getAddress("MOONWELL_WETH")
        ) - 100e18;
        uint256 cbEthMintAmount = _getMaxSupplyAmount(
            addresses.getAddress("MOONWELL_cbETH")
        ) - 100e18;

        _addLiquidity(addresses.getAddress("MOONWELL_USDBC"), usdcMintAmount);
        _addLiquidity(addresses.getAddress("MOONWELL_WETH"), wethMintAmount);
        _addLiquidity(addresses.getAddress("MOONWELL_cbETH"), cbEthMintAmount);

        (uint256 err, uint256 liquidity, uint256 shortfall) = comptroller
            .getAccountLiquidity(address(this));

        /// normalize up usdc decimals from 6 to 18 by adding 12
        uint256 expectedMinLiquidity = (((usdcMintAmount * 1e12) * 8) / 10) +
            wethMintAmount *
            1_000 +
            cbEthMintAmount *
            1_200;

        assertEq(err, 0, "Error getting account liquidity");
        assertGt(liquidity, expectedMinLiquidity, "liquidity not correct");
        assertEq(shortfall, 0, "Incorrect shortfall");
    }

    function testMaxBorrowWeth() public returns (uint256) {
        testAddCloseToMaxLiquidity();

        uint256 borrowAmount = _getMaxSupplyAmount(
            addresses.getAddress("MOONWELL_WETH")
        );
        address mweth = addresses.getAddress("MOONWELL_WETH");

        {
            (uint256 err, , uint256 shortfall) = comptroller
                .getAccountLiquidity(address(this));

            assertEq(0, err);
            assertEq(0, shortfall);
        }

        assertEq(MErc20(mweth).borrow(borrowAmount), 0);
        assertEq(address(this).balance, borrowAmount);

        {
            (uint256 err, , uint256 shortfall) = comptroller
                .getAccountLiquidity(address(this));

            assertEq(0, err);
            assertEq(0, shortfall);
        }

        return borrowAmount;
    }

    function testMaxBorrowcbEth() public {
        testAddCloseToMaxLiquidity();

        uint256 borrowAmount = _getMaxSupplyAmount(
            addresses.getAddress("MOONWELL_cbETH")
        );
        address mcbeth = addresses.getAddress("MOONWELL_cbETH");

        assertEq(MErc20(mcbeth).borrow(borrowAmount), 0);
        assertEq(
            IERC20(addresses.getAddress("cbETH")).balanceOf(address(this)),
            borrowAmount
        );
    }

    function testMaxBorrowUsdc() public {
        testAddCloseToMaxLiquidity();

        uint256 borrowAmount = _getMaxSupplyAmount(
            addresses.getAddress("MOONWELL_USDBC")
        );
        address mUSDbC = addresses.getAddress("MOONWELL_USDBC");

        assertEq(MErc20(mUSDbC).borrow(borrowAmount), 0);
        assertEq(
            IERC20(addresses.getAddress("USDBC")).balanceOf(address(this)),
            borrowAmount
        );
    }

    function testRepayBorrowBehalfWethRouter() public {
        uint256 borrowAmount = testMaxBorrowWeth();
        address mweth = addresses.getAddress("MOONWELL_WETH");

        router = new WETHRouter(
            WETH9(addresses.getAddress("WETH")),
            MErc20(addresses.getAddress("MOONWELL_WETH"))
        );

        vm.deal(address(this), borrowAmount);

        router.repayBorrowBehalf{value: borrowAmount}(address(this));

        assertEq(MErc20(mweth).borrowBalanceStored(address(this)), 0); /// fully repaid
    }

    function testRepayMoreThanBorrowBalanceWethRouter() public {
        uint256 borrowRepayAmount = testMaxBorrowWeth() * 2;

        address mweth = addresses.getAddress("MOONWELL_WETH");

        router = new WETHRouter(
            WETH9(addresses.getAddress("WETH")),
            MErc20(addresses.getAddress("MOONWELL_WETH"))
        );

        vm.deal(address(this), borrowRepayAmount);

        router.repayBorrowBehalf{value: borrowRepayAmount}(address(this));

        assertEq(MErc20(mweth).borrowBalanceStored(address(this)), 0); /// fully repaid
        assertEq(address(this).balance, borrowRepayAmount / 2); /// excess eth returned
    }

    function testMintWithRouter() public {
        MErc20 mToken = MErc20(addresses.getAddress("MOONWELL_WETH"));
        uint256 startingMTokenWethBalance = weth.balanceOf(address(mToken));

        uint256 mintAmount = 1 ether;
        vm.deal(address(this), mintAmount);

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

    function _addLiquidity(address market, uint256 amount) private {
        address underlying = MErc20(market).underlying();
        deal(underlying, address(this), amount);
        IERC20(underlying).approve(market, amount);
        assertEq(MErc20(market).mint(amount), 0);
    }

    function _getMaxBorrowAmount(
        address mToken
    ) internal view returns (uint256) {
        uint256 borrowCap = comptroller.borrowCaps(address(mToken));
        uint256 totalBorrows = MToken(mToken).totalBorrows();

        return borrowCap - totalBorrows - 1;
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

        return supplyCap - totalSupplies - 1_000e6;
    }

    receive() external payable {}
}
