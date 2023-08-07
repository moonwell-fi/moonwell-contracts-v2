// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {MErc20} from "@protocol/core/MErc20.sol";
import {MToken} from "@protocol/core/MToken.sol";
import {Configs} from "@test/proposals/Configs.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {WETHRouter} from "@protocol/core/router/WETHRouter.sol";
import {Comptroller} from "@protocol/core/Comptroller.sol";
import {TestProposals} from "@test/proposals/TestProposals.sol";
import {MErc20Delegator} from "@protocol/core/MErc20Delegator.sol";
import {ChainlinkOracle} from "@protocol/core/Oracles/ChainlinkOracle.sol";
import {TemporalGovernor} from "@protocol/core/Governance/TemporalGovernor.sol";
import {MultiRewardDistributor} from "@protocol/core/MultiRewardDistributor/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/core/MultiRewardDistributor/MultiRewardDistributorCommon.sol";

contract LiveSystemBaseTest is Test, Configs {
    MultiRewardDistributor mrd;
    Comptroller comptroller;
    TestProposals proposals;
    Addresses addresses;
    WETHRouter router;
    ChainlinkOracle oracle;
    address public well;

    function setUp() public {
        proposals = new TestProposals();
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
        mrd = MultiRewardDistributor(addresses.getAddress("MRD_PROXY"));
        well = addresses.getAddress("WELL");
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        router = WETHRouter(payable(addresses.getAddress("WETH_ROUTER")));
        oracle = ChainlinkOracle(addresses.getAddress("CHAINLINK_ORACLE"));
    }

    function testSetup() public {
        Configs.EmissionConfig[] memory configs = Configs(
            address(proposals.proposals(0))
        ).getEmissionConfigurations(block.chainid);
        Configs.CTokenConfiguration[] memory mTokenConfigs = Configs(
            address(proposals.proposals(0))
        ).getCTokenConfigurations(block.chainid);

        assertEq(configs.length, 3); /// 5 configs on base goerli
        assertEq(mTokenConfigs.length, 3); /// 5 mTokens on base goerli
    }

    function testOraclesReturnCorrectValues() public {
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

        EmissionConfig[] memory emissionConfig = getEmissionConfigurations(
            block.chainid
        );

        assertEq(config.owner, addresses.getAddress("EMISSIONS_ADMIN"));
        assertEq(config.emissionToken, well);
        assertEq(config.supplyEmissionsPerSec, 1e18);
        assertEq(config.endTime, emissionConfig[0].endTime);
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

        EmissionConfig[] memory emissionConfig = getEmissionConfigurations(
            block.chainid
        );

        assertEq(config.owner, addresses.getAddress("EMISSIONS_ADMIN"));
        assertEq(config.emissionToken, well);
        assertEq(config.borrowEmissionsPerSec, 1e18);
        assertEq(config.endTime, emissionConfig[0].endTime);
        assertEq(config.supplyGlobalIndex, 1e36);
        assertEq(config.borrowGlobalIndex, 1e36);
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

        console.log("liquidity: ", liquidity);

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

        console.log("liquidity: ", liquidity);

        assertEq(err, 0, "Error getting account liquidity");
        assertGt(liquidity, mintAmount * 1200, "liquidity incorrect");
        assertEq(shortfall, 0, "Incorrect shortfall");

        comptroller.exitMarket(address(mToken));
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
                MToken(addresses.getAddress("MOONWELL_USDC")),
                address(this)
            );

        assertEq(rewards[0].emissionToken, well);
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

        assertLe(
            rewards[0].supplySide,
            toWarp,
            "Supply side rewards not less than warp time"
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
                MToken(addresses.getAddress("MOONWELL_USDC")),
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
        mTokens[0] = addresses.getAddress("MOONWELL_USDC");
        mTokens[1] = addresses.getAddress("MOONWELL_WETH");
        mTokens[2] = addresses.getAddress("MOONWELL_cbETH");

        uint256[] memory errors = comptroller.enterMarkets(mTokens);
        for (uint256 i = 0; i < errors.length; i++) {
            assertEq(errors[i], 0);
        }
    }
}
