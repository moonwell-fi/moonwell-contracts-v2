//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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

// Example:
// export DESCRIPTION_PATH=src/proposals/mips/mip-o00/MIP-O00.md && export
// export PRIMARY_FORK_ID=2 && export
// EMISSIONS_PATH=src/proposals/mips/mip-o00/emissionConfig.json && export
// MTOKENS_PATH="src/proposals/mips/mip-o00/mTokens.json"
contract LiveSystemDeploy is Test {
    using ChainIds for uint256;

    MultiRewardDistributor mrd;
    Comptroller comptroller;
    Addresses addresses;
    mip00 proposal;
    mapping(address mToken => Configs.EmissionConfig[] emissionConfig)
        public emissionsConfig;

    function setUp() public {
        // TODO restrict chain ids passing the json here
        addresses = new Addresses();

        // TODO verify wheter the system has already been deployed and
        // initialized on chain and skip
        // proposal execution in case
        proposal = new mip00();
        proposal.primaryForkId().createForksAndSelect();

        proposal.deploy(addresses, address(proposal));
        proposal.afterDeploy(addresses, address(proposal));

        proposal.preBuildMock(addresses);
        proposal.build(addresses);
        proposal.run(addresses, address(proposal));
        proposal.validate(addresses, address(proposal));

        mrd = MultiRewardDistributor(addresses.getAddress("MRD_PROXY"));
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));

        Configs.EmissionConfig[] memory emissionConfigs = proposal
            .getEmissionConfigurations(block.chainid);

        for (uint256 i = 0; i < emissionConfigs.length; i++) {
            address mToken = addresses.getAddress(emissionConfigs[i].mToken);
            emissionsConfig[mToken].push(emissionConfigs[i]);
        }
    }

    function testGuardianCanPauseTemporalGovernor() public {
        TemporalGovernor gov = TemporalGovernor(
            payable(addresses.getAddress("TEMPORAL_GOVERNOR"))
        );

        vm.prank(addresses.getAddress("OPTIMISM_SECURITY_COUNCIL"));
        gov.togglePause();

        assertTrue(gov.paused());
        assertFalse(gov.guardianPauseAllowed());
        assertEq(gov.lastPauseTime(), block.timestamp);
    }

    function testFuzz_EmissionsAdminCanChangeOwner(
        uint256 mTokenIndex,
        address newOwner
    ) public {
        Configs.CTokenConfiguration[] memory mTokensConfig = proposal
            .getCTokenConfigurations(block.chainid);
        mTokenIndex = _bound(mTokenIndex, 0, mTokensConfig.length - 1);
        address emissionsAdmin = addresses.getAddress("TEMPORAL_GOVERNOR");
        vm.assume(newOwner != emissionsAdmin);

        vm.startPrank(emissionsAdmin);

        address mToken = addresses.getAddress(
            mTokensConfig[mTokenIndex].addressesString
        );
        for (uint256 i = 0; i < emissionsConfig[mToken].length; i++) {
            mrd._updateOwner(
                MToken(mToken),
                emissionsConfig[mToken][i].emissionToken,
                newOwner
            );
        }
        vm.stopPrank();
    }

    function testFuzz_EmissionsAdminCanChangeRewardStream(
        uint256 mTokenIndex,
        address newOwner
    ) public {
        Configs.CTokenConfiguration[] memory mTokensConfig = proposal
            .getCTokenConfigurations(block.chainid);

        mTokenIndex = _bound(mTokenIndex, 0, mTokensConfig.length - 1);
        address emissionsAdmin = addresses.getAddress("TEMPORAL_GOVERNOR");
        vm.assume(newOwner != emissionsAdmin);

        vm.startPrank(emissionsAdmin);
        address mToken = addresses.getAddress(
            mTokensConfig[mTokenIndex].addressesString
        );
        for (uint256 i = 0; i < emissionsConfig[mToken].length; i++) {
            mrd._updateBorrowSpeed(
                MToken(mToken),
                emissionsConfig[mToken][i].emissionToken,
                0.123e18
            );
        }
        vm.stopPrank();
    }

    function testFuzz_UpdateEmissionConfigEndTimeSuccess(
        uint256 mTokenIndex
    ) public {
        Configs.CTokenConfiguration[] memory mTokensConfig = proposal
            .getCTokenConfigurations(block.chainid);

        mTokenIndex = _bound(mTokenIndex, 0, mTokensConfig.length - 1);
        address mToken = addresses.getAddress(
            mTokensConfig[mTokenIndex].addressesString
        );
        vm.startPrank(addresses.getAddress("TEMPORAL_GOVERNOR"));

        for (uint256 i = 0; i < emissionsConfig[mToken].length; i++) {
            mrd._updateEndTime(
                MToken(mToken),
                emissionsConfig[mToken][i].emissionToken,
                emissionsConfig[mToken][i].endTime + 4 weeks
            );

            MultiRewardDistributorCommon.MarketConfig memory config = mrd
                .getConfigForMarket(
                    MToken(mToken),
                    emissionsConfig[mToken][i].emissionToken
                );

            assertEq(
                config.endTime,
                emissionsConfig[mToken][i].endTime + 4 weeks,
                "End time incorrect"
            );
        }
        vm.stopPrank();
    }

    function testFuzz_UpdateEmissionConfigSupplySuccess(
        uint256 mTokenIndex
    ) public {
        Configs.CTokenConfiguration[] memory mTokensConfig = proposal
            .getCTokenConfigurations(block.chainid);

        mTokenIndex = _bound(mTokenIndex, 0, mTokensConfig.length - 1);

        address mToken = addresses.getAddress(
            mTokensConfig[mTokenIndex].addressesString
        );
        for (uint256 i = 0; i < emissionsConfig[mToken].length; i++) {
            vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
            mrd._updateSupplySpeed(
                MToken(mToken),
                emissionsConfig[mToken][i].emissionToken,
                1e18 /// pay 1 op per second in rewards
            );

            MultiRewardDistributorCommon.MarketConfig memory config = mrd
                .getConfigForMarket(
                    MToken(mToken),
                    emissionsConfig[mToken][i].emissionToken
                );

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
        Configs.CTokenConfiguration[] memory mTokensConfig = proposal
            .getCTokenConfigurations(block.chainid);

        mTokenIndex = _bound(mTokenIndex, 0, mTokensConfig.length - 1);

        address mToken = addresses.getAddress(
            mTokensConfig[mTokenIndex].addressesString
        );
        for (uint256 i = 0; i < emissionsConfig[mToken].length; i++) {
            vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
            mrd._updateBorrowSpeed(
                MToken(mToken),
                emissionsConfig[mToken][i].emissionToken,
                1e18 /// pay 1 op per second in rewards to borrowers
            );

            MultiRewardDistributorCommon.MarketConfig memory config = mrd
                .getConfigForMarket(
                    MToken(mToken),
                    emissionsConfig[mToken][i].emissionToken
                );

            assertEq(
                config.borrowEmissionsPerSec,
                1e18,
                "Borrow emissions incorrect"
            );
        }
    }

    function _mintMToken(address mToken, uint256 amount) internal {
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
    }

    function testFuzz_MintMTokenSucceeds(
        uint256 mTokenIndex,
        uint256 mintAmount
    ) public {
        Configs.CTokenConfiguration[] memory mTokensConfig = proposal
            .getCTokenConfigurations(block.chainid);

        mTokenIndex = _bound(mTokenIndex, 0, mTokensConfig.length - 1);

        IERC20 token = IERC20(
            addresses.getAddress(mTokensConfig[mTokenIndex].tokenAddressName)
        );

        mintAmount = bound(
            mintAmount,
            1 * 10 ** token.decimals(),
            100_000_000 * 10 ** token.decimals()
        );

        address sender = address(this);

        address mToken = addresses.getAddress(
            mTokensConfig[mTokenIndex].addressesString
        );

        uint256 startingTokenBalance = token.balanceOf(mToken);

        _mintMToken(mToken, mintAmount);
        assertTrue(
            MErc20Delegator(payable(mToken)).balanceOf(sender) > 0,
            "mToken balance should be gt 0 after mint"
        ); /// ensure balance is gt 0
        assertEq(
            token.balanceOf(mToken) - startingTokenBalance,
            mintAmount,
            "Underlying balance not updated"
        ); /// ensure underlying balance is sent to mToken
    }

    function testFuzz_BorrowMTokenSucceed(
        uint256 mTokenIndex,
        uint256 borrowAmount
    ) public {
        Configs.CTokenConfiguration[] memory mTokensConfig = proposal
            .getCTokenConfigurations(block.chainid);

        mTokenIndex = _bound(mTokenIndex, 0, mTokensConfig.length - 1);

        IERC20 token = IERC20(
            addresses.getAddress(mTokensConfig[mTokenIndex].tokenAddressName)
        );

        borrowAmount = bound(
            borrowAmount,
            1 * 10 ** token.decimals(),
            100_000_000 * 10 ** token.decimals()
        );

        address mToken = addresses.getAddress(
            mTokensConfig[mTokenIndex].addressesString
        );
        _mintMToken(mToken, borrowAmount * 3);

        uint256 expectedCollateralFactor = 0.5e18;
        (, uint256 collateralFactorMantissa) = comptroller.markets(mToken);
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

        address[] memory mTokens = new address[](1);
        mTokens[0] = mToken;

        comptroller.enterMarkets(mTokens);
        assertTrue(
            comptroller.checkMembership(sender, MToken(mToken)),
            "Membership check failed"
        );

        assertEq(
            MErc20Delegator(payable(mToken)).borrow(borrowAmount),
            0,
            "Borrow failed"
        );

        if (address(token) == addresses.getAddress("WETH")) {
            assertEq(sender.balance - balanceBefore, borrowAmount);
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
        Configs.CTokenConfiguration[] memory mTokensConfig = proposal
            .getCTokenConfigurations(block.chainid);

        mTokenIndex = _bound(mTokenIndex, 0, mTokensConfig.length - 1);

        IERC20 token = IERC20(
            addresses.getAddress(mTokensConfig[mTokenIndex].tokenAddressName)
        );

        supplyAmount = bound(
            supplyAmount,
            1 * 10 ** token.decimals(),
            100_000_000 * 10 ** token.decimals()
        );

        toWarp = _bound(toWarp, 1_000_000, 4 weeks);

        address mToken = addresses.getAddress(
            mTokensConfig[mTokenIndex].addressesString
        );

        _mintMToken(mToken, supplyAmount);

        vm.warp(block.timestamp + toWarp);

        Configs.EmissionConfig[] memory emissionConfig = emissionsConfig[
            mToken
        ];

        for (uint256 i = 0; i < emissionConfig.length; i++) {
            uint256 expectedReward = (toWarp *
                emissionConfig[i].supplyEmissionPerSec *
                supplyAmount) / MErc20(mToken).totalSupply();

            assertEq(
                mrd
                .getOutstandingRewardsForUser(MToken(mToken), address(this))[0]
                    .totalAmount,
                expectedReward,
                "Total rewards not correct"
            );
        }
    }

    //
    //    function testSupplyUsdcReceivesRewards(uint256 toWarp) public {
    //        toWarp = _bound(toWarp, 1_000_000, 4 weeks);
    //
    //        testUpdateEmissionConfigSupplyUsdcSuccess();
    //        testMintMTokenSucceeds();
    //
    //        vm.warp(block.timestamp + toWarp);
    //
    //        MToken mToken = MToken(addresses.getAddress("MOONWELL_USDC"));
    //
    //        MultiRewardDistributorCommon.RewardInfo[] memory rewards = mrd
    //            .getOutstandingRewardsForUser(mToken, address(this));
    //
    //        assertEq(rewards[0].emissionToken, op);
    //
    //        uint256 balance = mToken.balanceOf(address(this));
    //        uint256 totalSupply = mToken.totalSupply();
    //
    //        MultiRewardDistributorCommon.MarketConfig memory config = mrd
    //            .getConfigForMarket(mToken, addresses.getAddress("OP"));
    //
    //        uint256 expectedReward = ((toWarp * config.supplyEmissionsPerSec) *
    //            balance) / totalSupply;
    //
    //        assertApproxEqRel(
    //            rewards[0].totalAmount,
    //            expectedReward,
    //            1e17,
    //            "Total rewards not within 1%"
    //        ); /// allow 1% error, anything more causes test failure
    //        assertApproxEqRel(
    //            rewards[0].supplySide,
    //            expectedReward,
    //            1e17,
    //            "Supply side rewards not within 1%"
    //        ); /// allow 1% error, anything more causes test failure
    //        assertEq(rewards[0].borrowSide, 0);
    //    }
    //
    //    function testBorrowUsdcReceivesRewards(uint256 toWarp) public {
    //        toWarp = _bound(toWarp, 1_000_000, 4 weeks);
    //
    //        testUpdateEmissionConfigBorrowUsdcSuccess();
    //        testBorrowMTokenSucceeds();
    //
    //        vm.warp(block.timestamp + toWarp);
    //
    //        MToken mToken = MToken(addresses.getAddress("MOONWELL_USDC"));
    //
    //        MultiRewardDistributorCommon.RewardInfo[] memory rewards = mrd
    //            .getOutstandingRewardsForUser(mToken, address(this));
    //
    //        uint256 userCurrentBorrow = mToken.borrowBalanceCurrent(address(this));
    //        uint256 totalBorrow = mToken.totalBorrows();
    //
    //        MultiRewardDistributorCommon.MarketConfig memory config = mrd
    //            .getConfigForMarket(mToken, addresses.getAddress("OP"));
    //
    //        // calculate expected borrow reward
    //        uint256 expectedBorrowReward = ((toWarp *
    //            config.borrowEmissionsPerSec) * userCurrentBorrow) / totalBorrow;
    //
    //        assertEq(rewards[0].emissionToken, op);
    //        assertApproxEqRel(
    //            rewards[0].totalAmount,
    //            expectedBorrowReward,
    //            1e17,
    //            "Total rewards not within 1%"
    //        ); /// allow 1% error, anything more causes test failure
    //        assertApproxEqRel(
    //            rewards[0].borrowSide,
    //            expectedBorrowReward,
    //            1e17,
    //            "Supply side rewards not within 1%"
    //        ); /// allow 1% error, anything more causes test failure
    //        assertEq(rewards[0].supplySide, 0);
    //    }
    //
    //    function testSupplyBorrowUsdcReceivesRewards(uint256 toWarp) public {
    //        toWarp = _bound(toWarp, 1_000_000, 4 weeks);
    //
    //        testUpdateEmissionConfigBorrowUsdcSuccess();
    //
    //        vm.warp(block.timestamp + 1);
    //        testUpdateEmissionConfigSupplyUsdcSuccess();
    //
    //        testBorrowMTokenSucceeds();
    //
    //        vm.warp(block.timestamp + toWarp);
    //
    //        MToken mToken = MToken(addresses.getAddress("MOONWELL_USDC"));
    //
    //        MultiRewardDistributorCommon.RewardInfo[] memory rewards = mrd
    //            .getOutstandingRewardsForUser(mToken, address(this));
    //
    //        uint256 balance = mToken.balanceOf(address(this));
    //        uint256 totalSupply = mToken.totalSupply();
    //
    //        MultiRewardDistributorCommon.MarketConfig memory config = mrd
    //            .getConfigForMarket(mToken, addresses.getAddress("OP"));
    //
    //        uint256 expectedSupplyReward = ((toWarp *
    //            config.supplyEmissionsPerSec) * balance) / totalSupply;
    //
    //        uint256 userCurrentBorrow = mToken.borrowBalanceCurrent(address(this));
    //        uint256 totalBorrow = mToken.totalBorrows();
    //
    //        // calculate expected borrow reward
    //        uint256 expectedBorrowReward = ((toWarp *
    //            config.borrowEmissionsPerSec) * userCurrentBorrow) / totalBorrow;
    //
    //        assertEq(rewards[0].emissionToken, op);
    //        assertApproxEqRel(
    //            rewards[0].totalAmount,
    //            expectedBorrowReward + expectedSupplyReward,
    //            1e17,
    //            "Total rewards not within 1%"
    //        ); /// allow 1% error, anything more causes test failure
    //        assertApproxEqRel(
    //            rewards[0].borrowSide,
    //            expectedBorrowReward,
    //            1e17,
    //            "Borrow side rewards not within 1%"
    //        ); /// allow 1% error, anything more causes test failure
    //        assertApproxEqRel(
    //            rewards[0].supplySide,
    //            expectedSupplyReward,
    //            1e17,
    //            "Supply side rewards not within 1%"
    //        );
    //    }
    //
    //    function testLiquidateAccountReceivesRewards(uint256 toWarp) public {
    //        toWarp = _bound(toWarp, 1_000_000, 4 weeks);
    //
    //        testUpdateEmissionConfigSupplyUsdcSuccess();
    //
    //        vm.warp(block.timestamp + 1);
    //
    //        testUpdateEmissionConfigBorrowUsdcSuccess();
    //
    //        testBorrowMTokenSucceeds();
    //
    //        MToken mToken = MToken(addresses.getAddress("MOONWELL_USDC"));
    //
    //        MultiRewardDistributorCommon.RewardInfo[] memory rewardsBefore = mrd
    //            .getOutstandingRewardsForUser(mToken, address(this));
    //
    //        MultiRewardDistributorCommon.MarketConfig memory config = mrd
    //            .getConfigForMarket(mToken, addresses.getAddress("OP"));
    //
    //        uint256 expectedSupplyReward;
    //        {
    //            uint256 balance = mToken.balanceOf(address(this)) / 2;
    //            uint256 totalSupply = mToken.totalSupply();
    //
    //            expectedSupplyReward =
    //                ((toWarp * config.supplyEmissionsPerSec) * balance) /
    //                totalSupply;
    //        }
    //
    //        uint256 expectedBorrowReward;
    //        {
    //            uint256 userCurrentBorrow = mToken.borrowBalanceCurrent(
    //                address(this)
    //            );
    //            uint256 totalBorrow = mToken.totalBorrows();
    //
    //            // calculate expected borrow reward
    //            expectedBorrowReward =
    //                ((toWarp * config.borrowEmissionsPerSec) * userCurrentBorrow) /
    //                totalBorrow;
    //        }
    //
    //        vm.warp(block.timestamp + toWarp);
    //
    //        /// borrower is now underwater on loan
    //        deal(
    //            address(mToken),
    //            address(this),
    //            mToken.balanceOf(address(this)) / 2
    //        );
    //
    //        {
    //            (uint256 err, uint256 liquidity, uint256 shortfall) = comptroller
    //                .getHypotheticalAccountLiquidity(
    //                    address(this),
    //                    address(mToken),
    //                    0,
    //                    0
    //                );
    //
    //            assertEq(err, 0, "Error in hypothetical liquidity calculation");
    //            assertEq(liquidity, 0, "Liquidity not 0");
    //            assertGt(shortfall, 0, "Shortfall not gt 0");
    //        }
    //
    //        uint256 repayAmt = 50e6;
    //        address liquidator = address(100_000_000);
    //        IERC20 usdc = IERC20(addresses.getAddress("USDC"));
    //
    //        deal(address(usdc), liquidator, repayAmt);
    //        vm.prank(liquidator);
    //        usdc.approve(address(mToken), repayAmt);
    //
    //        _liquidateAccount(
    //            liquidator,
    //            address(this),
    //            MErc20(address(mToken)),
    //            1e5
    //        );
    //
    //        MultiRewardDistributorCommon.RewardInfo[] memory rewardsAfter = mrd
    //            .getOutstandingRewardsForUser(mToken, address(this));
    //
    //        assertEq(rewardsAfter[0].emissionToken, op, "Emission token incorrect");
    //        assertApproxEqRel(
    //            rewardsAfter[0].totalAmount,
    //            rewardsBefore[0].totalAmount +
    //                expectedBorrowReward +
    //                expectedSupplyReward,
    //            1e17,
    //            "Total rewards not within 1%"
    //        ); /// allow 1% error, anything more causes test failure
    //        assertApproxEqRel(
    //            rewardsAfter[0].borrowSide,
    //            rewardsBefore[0].borrowSide + expectedBorrowReward,
    //            1e17,
    //            "Borrow side rewards not within 1%"
    //        ); /// allow 1% error, anything more causes test failure
    //        assertApproxEqRel(
    //            rewardsAfter[0].supplySide,
    //            rewardsBefore[0].supplySide + expectedSupplyReward,
    //            1e17,
    //            "Supply side rewards not within 1%"
    //        );
    //    }
    //
    //    function _liquidateAccount(
    //        address liquidator,
    //        address liquidated,
    //        MErc20 token,
    //        uint256 repayAmt
    //    ) private {
    //        vm.prank(liquidator);
    //        assertEq(
    //            token.liquidateBorrow(liquidated, repayAmt, token),
    //            0,
    //            "user liquidation failure"
    //        );
    //    }

    receive() external payable {}
}
