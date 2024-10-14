//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20Metadata as IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {WETH9} from "@protocol/router/IWETH.sol";
import {Unitroller} from "@protocol/Unitroller.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MarketBase} from "@test/utils/MarketBase.sol";
import {WETHRouter} from "@protocol/router/WETHRouter.sol";
import {ChainIds, OPTIMISM_CHAIN_ID} from "@utils/ChainIds.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {MarketAddChecker} from "@protocol/governance/MarketAddChecker.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";

contract MultiRewardsDistributorLiveSystem is Test, PostProposalCheck {
    using ChainIds for uint256;

    MultiRewardDistributor mrd;
    MarketAddChecker checker;
    Comptroller comptroller;

    MToken[] mTokens;
    MarketBase public marketBase;

    mapping(MToken => address[] rewardTokens) rewardsConfig;

    function setUp() public override {
        uint256 primaryForkId = vm.envUint("PRIMARY_FORK_ID");
        super.setUp();

        vm.selectFork(primaryForkId);

        checker = MarketAddChecker(addresses.getAddress("MARKET_ADD_CHECKER"));

        mrd = MultiRewardDistributor(addresses.getAddress("MRD_PROXY"));
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));

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

    function testAllEmissionTokenConfigs() public view {
        MToken[] memory markets = comptroller.getAllMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            MultiRewardDistributorCommon.MarketConfig[] memory allConfigs = mrd
                .getAllMarketConfigs(markets[i]);
            for (uint256 j = 0; j < allConfigs.length; j++) {
                assertGt(
                    allConfigs[j].borrowEmissionsPerSec,
                    0,
                    "Emission speed below 1"
                );
                assertTrue(
                    allConfigs[j].emissionToken.code.length > 0,
                    "Invalid emission token"
                );

                /// ensure standard calls to token succeed
                IERC20(allConfigs[j].emissionToken).balanceOf(address(mrd));
                IERC20(allConfigs[j].emissionToken).totalSupply();
            }
        }
    }

    function testAllEmissionAdminTemporalGovernor() public view {
        MToken[] memory markets = comptroller.getAllMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            MultiRewardDistributorCommon.MarketConfig[] memory allConfigs = mrd
                .getAllMarketConfigs(markets[i]);

            for (uint256 j = 0; j < allConfigs.length; j++) {
                if (
                    address(markets[i]) ==
                    addresses.getAddress("MOONWELL_USDC") &&
                    block.chainid == block.chainid.toBaseChainId()
                ) {
                    assertEq(
                        allConfigs[j].owner,
                        addresses.getAddress("GAUNTLET_MULTISIG"),
                        "Gautlet not admin"
                    );
                } else {
                    assertEq(
                        allConfigs[j].owner,
                        addresses.getAddress("TEMPORAL_GOVERNOR"),
                        "Temporal Governor not admin"
                    );
                }
            }
        }
    }

    function testFuzz_OraclesReturnCorrectValues(
        uint256 mTokenIndex
    ) public view {
        mTokenIndex = _bound(mTokenIndex, 0, mTokens.length - 1);

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
        uint256 mTokenIndex,
        uint256 newEndTime
    ) public {
        mTokenIndex = _bound(mTokenIndex, 0, mTokens.length - 1);
        MToken mToken = mTokens[mTokenIndex];

        vm.startPrank(addresses.getAddress("TEMPORAL_GOVERNOR"));

        for (uint256 i = 0; i < rewardsConfig[mToken].length; i++) {
            MultiRewardDistributorCommon.MarketConfig memory configBefore = mrd
                .getConfigForMarket(mToken, rewardsConfig[mToken][i]);

            uint256 lowerBound = configBefore.endTime > vm.getBlockTimestamp()
                ? configBefore.endTime + 1
                : vm.getBlockTimestamp() + 1;

            newEndTime = bound(newEndTime, lowerBound, lowerBound + 4 weeks);

            mrd._updateEndTime(mToken, rewardsConfig[mToken][i], newEndTime);

            MultiRewardDistributorCommon.MarketConfig memory config = mrd
                .getConfigForMarket(mToken, rewardsConfig[mToken][i]);

            assertEq(config.endTime, newEndTime, "End time incorrect");
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

    receive() external payable {}
}
