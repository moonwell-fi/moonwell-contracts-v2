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
import {Unitroller} from "@protocol/Unitroller.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";
import {ExponentialNoError} from "@protocol/ExponentialNoError.sol";

// Example:
// export DESCRIPTION_PATH=src/proposals/mips/mip-o00/MIP-O00.md && export
// export PRIMARY_FORK_ID=2 && export
// EMISSIONS_PATH=src/proposals/mips/mip-o00/emissionConfig.json && export
// MTOKENS_PATH="src/proposals/mips/mip-o00/mTokens.json"
contract LiveSystemDeploy is Test, ExponentialNoError {
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
        vm.makePersistent(address(addresses));

        proposal = new mip00();
        proposal.primaryForkId().createForksAndSelect();
        proposal.initProposal();

        if (!addresses.isAddressSet("UNITROLLER")) {
            proposal.deploy(addresses, address(proposal));
            proposal.afterDeploy(addresses, address(proposal));
        }

        address unitroller = addresses.getAddress("UNITROLLER");
        // this mean the calldata has not been executed yet
        if (
            Unitroller(unitroller).admin() !=
            addresses.getAddress("TEMPORAL_GOVERNOR")
        ) {
            proposal.preBuildMock(addresses);
            proposal.build(addresses);

            proposal.run(addresses, address(proposal));
            proposal.validate(addresses, address(proposal));
        }

        mrd = MultiRewardDistributor(addresses.getAddress("MRD_PROXY"));
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));

        Configs.EmissionConfig[] memory emissionConfigs = proposal
            .getEmissionConfigurations(block.chainid);

        for (uint256 i = 0; i < emissionConfigs.length; i++) {
            address mToken = addresses.getAddress(emissionConfigs[i].mToken);

            vm.warp(MToken(mToken).accrualBlockTimestamp());
            MToken(mToken).accrueInterest();

            emissionsConfig[mToken].push(emissionConfigs[i]);

            // update emission conf
            MultiRewardDistributorCommon.MarketConfig memory config = mrd
                .getConfigForMarket(
                    MToken(mToken),
                    emissionConfigs[i].emissionToken
                );

            if (config.borrowEmissionsPerSec == 1) {
                vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
                mrd._updateBorrowSpeed(
                    MToken(mToken),
                    emissionConfigs[i].emissionToken,
                    1e18
                );
            }
        }

        address mrdProxy = addresses.getAddress("MRD_PROXY");

        MultiRewardDistributor mrd = new MultiRewardDistributor();

        vm.prank(addresses.getAddress("MRD_PROXY_ADMIN"));
        ITransparentUpgradeableProxy(mrdProxy).upgradeTo(address(mrd));
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
        Configs.CTokenConfiguration[] memory mTokensConfig = proposal
            .getCTokenConfigurations(block.chainid);
        mTokenIndex = _bound(mTokenIndex, 0, mTokensConfig.length - 1);
        address emissionsAdmin = addresses.getAddress("TEMPORAL_GOVERNOR");
        vm.assume(newOwner != emissionsAdmin);

        vm.startPrank(emissionsAdmin);

        address mToken = addresses.getAddress(
            mTokensConfig[mTokenIndex].addressesString
        );
        vm.warp(MToken(mToken).accrualBlockTimestamp());
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
        vm.warp(MToken(mToken).accrualBlockTimestamp());
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
        vm.warp(MToken(mToken).accrualBlockTimestamp());
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
        vm.warp(MToken(mToken).accrualBlockTimestamp());
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
        vm.warp(MToken(mToken).accrualBlockTimestamp());
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

        vm.warp(MToken(mToken).accrualBlockTimestamp());

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

        vm.warp(MToken(mToken).accrualBlockTimestamp());

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

    function testFuzz_BorrowReceivesRewards(
        uint256 mTokenIndex,
        uint256 borrowAmount,
        uint256 toWarp
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

        toWarp = _bound(toWarp, 1_000_000, 4 weeks);

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

        {
            address[] memory mTokens = new address[](1);
            mTokens[0] = mToken;

            comptroller.enterMarkets(mTokens);
        }

        assertTrue(
            comptroller.checkMembership(sender, MToken(mToken)),
            "Membership check failed"
        );

        assertEq(
            comptroller.borrowAllowed(mToken, sender, borrowAmount),
            0,
            "Borrow allowed"
        );

        assertEq(
            MErc20Delegator(payable(mToken)).borrow(borrowAmount),
            0,
            "Borrow failed"
        );

        MultiRewardDistributorCommon.MarketConfig memory config = mrd
            .getConfigForMarket(MToken(mToken), addresses.getAddress("OP"));

        console.log("global borrow timestamp ", config.borrowGlobalTimestamp);
        console.log("global borrow index ", config.borrowGlobalIndex);

        {
            (uint256 borrowerIndice, uint256 rewardsAccrued) = mrd
                .getUserConfig(mToken, sender, addresses.getAddress("OP"));

            console.log("borrowerIndice", borrowerIndice);
            console.log("rewardsAccrued", rewardsAccrued);
        }

        console.log("timestampBefore", vm.getBlockTimestamp());
        vm.warp(vm.getBlockTimestamp() + toWarp);
        console.log("timestampAfter", vm.getBlockTimestamp());

        Configs.EmissionConfig[] memory emissionConfig = emissionsConfig[
            mToken
        ];

        for (uint256 i = 0; i < emissionConfig.length; i++) {
            MultiRewardDistributorCommon.MarketConfig memory config = mrd
                .getConfigForMarket(
                    MToken(mToken),
                    emissionConfig[i].emissionToken
                );

            MToken(mToken).accrueInterest();
            uint256 expectedReward;

            {
                uint256 globalTokenAccrued = ((vm.getBlockTimestamp() -
                    config.borrowGlobalTimestamp) *
                    config.borrowEmissionsPerSec);
                console.log("globalTokenAccrued", globalTokenAccrued);

                uint256 totalBorrowed = MErc20(mToken).totalBorrows() /
                    MToken(mToken).borrowIndex();
                console.log("totalBorrowed", totalBorrowed);

                uint256 updateIndex = fraction(
                    globalTokenAccrued,
                    totalBorrowed
                ).mantissa;

                console.log("Test updatedIndex", updateIndex);
                uint256 userIndex = 1e36;

                uint256 borrowerDelta = updateIndex - userIndex;

                console.log("Test borrowerDelta", borrowerDelta);

                uint256 userBorrow = MErc20(mToken).borrowBalanceStored(
                    sender
                ) / MToken(mToken).borrowIndex();

                console.log("Test borrowerAmount", borrowerAmount);

                expectedReward = borrowerDelta * userBorrow;
            }

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

        vm.warp(MToken(mToken).accrualBlockTimestamp());

        _mintMToken(mToken, supplyAmount);

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

        address[] memory mTokens = new address[](1);
        mTokens[0] = mToken;

        comptroller.enterMarkets(mTokens);
        assertTrue(
            comptroller.checkMembership(sender, MToken(mToken)),
            "Membership check failed"
        );

        {
            uint256 borrowAmount = supplyAmount / 3;

            assertEq(
                MErc20Delegator(payable(mToken)).borrow(borrowAmount),
                0,
                "Borrow failed"
            );
        }

        vm.warp(block.timestamp + toWarp);

        Configs.EmissionConfig[] memory emissionConfig = emissionsConfig[
            mToken
        ];

        for (uint256 i = 0; i < emissionConfig.length; i++) {
            MultiRewardDistributorCommon.MarketConfig memory config = mrd
                .getConfigForMarket(
                    MToken(mToken),
                    emissionConfig[i].emissionToken
                );

            uint256 expectedSupplyReward = (toWarp *
                config.supplyEmissionsPerSec *
                supplyAmount) / MErc20(mToken).totalSupply();

            uint256 expectedBorrowReward = (toWarp *
                config.borrowEmissionsPerSec *
                MErc20(mToken).borrowBalanceCurrent(address(this))) /
                MErc20(mToken).totalBorrows();

            assertApproxEqRel(
                mrd
                .getOutstandingRewardsForUser(MToken(mToken), address(this))[0]
                    .totalAmount,
                expectedSupplyReward + expectedBorrowReward,
                0.15e18,
                "Total rewards not correct"
            );

            assertApproxEqRel(
                mrd
                .getOutstandingRewardsForUser(MToken(mToken), address(this))[0]
                    .supplySide,
                expectedSupplyReward,
                1e17,
                "Supply rewards not correct"
            );

            assertApproxEqRel(
                mrd
                .getOutstandingRewardsForUser(MToken(mToken), address(this))[0]
                    .borrowSide,
                expectedBorrowReward,
                0.15e18,
                "Borrow rewards not correct"
            );
        }
    }

    function testFuzz_LiquidateAccountReceiveRewards(
        uint256 mTokenIndex,
        uint256 mintAmount,
        uint256 toWarp
    ) public {
        Configs.CTokenConfiguration[] memory mTokensConfig = proposal
            .getCTokenConfigurations(block.chainid);

        mTokenIndex = _bound(mTokenIndex, 0, mTokensConfig.length - 1);

        toWarp = _bound(toWarp, 1_000_000, 4 weeks);

        address mToken = addresses.getAddress(
            mTokensConfig[mTokenIndex].addressesString
        );

        vm.warp(MToken(mToken).accrualBlockTimestamp());

        address token = addresses.getAddress(
            mTokensConfig[mTokenIndex].tokenAddressName
        );

        mintAmount = bound(
            mintAmount,
            1 * 10 ** IERC20(token).decimals(),
            100_000_000 * 10 ** IERC20(token).decimals()
        );

        _mintMToken(mToken, mintAmount);

        MultiRewardDistributorCommon.RewardInfo[] memory rewardsBefore = mrd
            .getOutstandingRewardsForUser(MToken(mToken), address(this));

        // borrow
        uint256 borrowAmount = mintAmount / 3;

        {
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

            address[] memory mTokens = new address[](1);
            mTokens[0] = mToken;

            comptroller.enterMarkets(mTokens);

            assertTrue(
                comptroller.checkMembership(address(this), MToken(mToken)),
                "Membership check failed"
            );
        }

        assertEq(
            MErc20Delegator(payable(mToken)).borrow(borrowAmount),
            0,
            "Borrow failed"
        );

        MultiRewardDistributorCommon.MarketConfig memory config = mrd
            .getConfigForMarket(
                MToken(mToken),
                emissionsConfig[mToken][0].emissionToken
            );

        uint256 expectedSupplyReward;
        {
            uint256 balance = MToken(mToken).balanceOf(address(this)) / 3;

            expectedSupplyReward =
                ((toWarp * config.supplyEmissionsPerSec) * balance) /
                MToken(mToken).totalSupply();
        }

        uint256 expectedBorrowReward;
        {
            uint256 userCurrentBorrow = MToken(mToken).borrowBalanceCurrent(
                address(this)
            );

            // calculate expected borrow reward
            expectedBorrowReward =
                ((toWarp * config.borrowEmissionsPerSec) * userCurrentBorrow) /
                MToken(mToken).totalBorrows();
        }

        vm.warp(block.timestamp + toWarp);

        if (token != addresses.getAddress("WETH")) {
            /// borrower is now underwater on loan
            deal(
                address(MErc20(mToken)),
                address(this),
                MErc20(mToken).balanceOf(address(this)) / 2
            );
        } else {
            vm.deal(addresses.getAddress("WETH"), address(this).balance / 2);
            /// borrower is now underwater on loan
            deal(
                address(MErc20(mToken)),
                address(this),
                MErc20(mToken).balanceOf(address(this)) / 2
            );
        }
        {
            (uint256 err, uint256 liquidity, uint256 shortfall) = comptroller
                .getHypotheticalAccountLiquidity(
                    address(this),
                    address(MErc20(mToken)),
                    0,
                    0
                );

            assertEq(err, 0, "Error in hypothetical liquidity calculation");
            assertEq(liquidity, 0, "Liquidity not 0");
            assertGt(shortfall, 0, "Shortfall not gt 0");
        }

        uint256 repayAmt = borrowAmount / 2;

        deal(token, address(100_000_000), repayAmt);

        vm.startPrank(address(100_000_000));

        IERC20(token).approve(address(MErc20(mToken)), repayAmt);
        assertEq(
            MErc20Delegator(payable(mToken)).liquidateBorrow(
                address(this),
                repayAmt,
                MErc20(mToken)
            ),
            0,
            "Liquidation failed"
        );

        vm.stopPrank();

        MultiRewardDistributorCommon.RewardInfo[] memory rewardsAfter = mrd
            .getOutstandingRewardsForUser(MToken(mToken), address(this));

        assertEq(
            rewardsAfter[0].emissionToken,
            emissionsConfig[mToken][0].emissionToken,
            "Emission token incorrect"
        );

        assertApproxEqRel(
            rewardsAfter[0].totalAmount,
            rewardsBefore[0].totalAmount +
                expectedSupplyReward +
                expectedBorrowReward,
            0.15e18,
            "Total rewards wrong"
        );

        assertApproxEqRel(
            rewardsAfter[0].borrowSide,
            rewardsBefore[0].borrowSide + expectedBorrowReward,
            0.15e18,
            "Borrow side rewards wrong"
        );

        assertApproxEqRel(
            rewardsAfter[0].supplySide,
            rewardsBefore[0].supplySide + expectedSupplyReward,
            1e17,
            "Supply side rewards not within 10%"
        );
    }

    receive() external payable {}
}
