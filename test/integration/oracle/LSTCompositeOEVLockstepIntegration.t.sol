// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {MToken} from "@protocol/MToken.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {ChainlinkOEVWrapper} from "@protocol/oracles/ChainlinkOEVWrapper.sol";
import {ChainlinkCompositeOracle} from "@protocol/oracles/ChainlinkCompositeOracle.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {ChainlinkOracleConfigs} from "@proposals/ChainlinkOracleConfigs.sol";
import {BASE_FORK_ID} from "@utils/ChainIds.sol";

/// @notice MOO-1023: Base ETH-derivative composites and WETH read the same
/// delayed ETH/USD round, so liquidations seize exactly the configured incentive.
contract LSTCompositeOEVLockstepIntegrationTest is
    PostProposalCheck,
    ChainlinkOracleConfigs
{
    /// @notice ETH/USD move between the cached and the new round
    int256 internal constant MOVE_BPS = 100;

    uint256 internal constant REPAY = 10e18;

    string internal constant DEPRECATED_SUFFIX = "_DEPRECATED_RAW_BASE";

    Comptroller internal comptroller;
    ChainlinkOracle internal oracle;
    ChainlinkOEVWrapper internal wrapper;
    AggregatorV3Interface internal ethFeed;
    MToken internal mWeth;
    CompositeOracleConfig[] internal lsts;

    function setUp() public override {
        super.setUp();
        vm.selectFork(BASE_FORK_ID);

        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        oracle = ChainlinkOracle(addresses.getAddress("CHAINLINK_ORACLE"));
        wrapper = ChainlinkOEVWrapper(
            payable(addresses.getAddress("CHAINLINK_ETH_USD_OEV_WRAPPER"))
        );
        ethFeed = AggregatorV3Interface(
            addresses.getAddress("CHAINLINK_ETH_USD")
        );
        mWeth = MToken(addresses.getAddress("MOONWELL_WETH"));

        CompositeOracleConfig[]
            memory configs = getCompositeOracleConfigurations(block.chainid);
        for (uint256 i = 0; i < configs.length; i++) {
            if (
                keccak256(bytes(configs[i].baseFeedName)) ==
                keccak256("CHAINLINK_ETH_USD")
            ) {
                lsts.push(configs[i]);
            }
        }
        assertEq(lsts.length, 5, "expected five ETH-based composites");

        // start outside any delay window so "outside" reads are the latest round
        vm.warp(block.timestamp + wrapper.maxRoundDelay() + 1);
        (, int256 raw, , , ) = ethFeed.latestRoundData();
        (, int256 wrapped, , , ) = wrapper.latestRoundData();
        assertEq(wrapped, raw, "fork still inside a delay window");
    }

    function testLstCompositesReadTheWethWrapper() public view {
        address wethFeed = address(oracle.getFeed("WETH"));
        assertEq(wethFeed, address(wrapper), "WETH feed is not the wrapper");

        for (uint256 i = 0; i < lsts.length; i++) {
            ChainlinkCompositeOracle composite = ChainlinkCompositeOracle(
                address(oracle.getFeed(_symbol(lsts[i])))
            );
            assertEq(
                composite.base(),
                wethFeed,
                string.concat(
                    lsts[i].symbol,
                    " composite base is not WETH's feed"
                )
            );
        }
    }

    function testSeizeIncentiveExactInsideFallingWindow() public {
        _assertSeizeUnaffectedByWindow(-MOVE_BPS);
    }

    function testSeizeIncentiveExactInsideRisingWindow() public {
        _assertSeizeUnaffectedByWindow(MOVE_BPS);
    }

    /// @notice control: the pre-fix raw-base composite over-seizes in the same window
    function testRawBaseCompositeOverSeizesInsideWindow() public {
        uint256 incentive = comptroller.liquidationIncentiveMantissa();

        for (uint256 i = 0; i < lsts.length; i++) {
            uint256 snapshot = vm.snapshot();
            ChainlinkCompositeOracle rawComposite = _deprecated(lsts[i]);

            // hoisted: an external call in argument position would consume the prank
            string memory symbol = _symbol(lsts[i]);
            address admin = oracle.admin();
            vm.prank(admin);
            oracle.setFeed(symbol, address(rawComposite));

            int256 fresh = _openWindow(-MOVE_BPS);
            MToken mLst = MToken(addresses.getAddress(lsts[i].mTokenKey));
            (uint256 err, uint256 seized) = comptroller
                .liquidateCalculateSeizeTokens(
                    address(mWeth),
                    address(mLst),
                    REPAY
                );
            assertEq(err, 0, "seize calculation errored");

            uint256 effective = _effectiveIncentive(
                mLst,
                rawComposite,
                seized,
                fresh
            );
            // 1.10 / (1 - 1%) = 1.1111
            assertGt(
                effective,
                (incentive * 10_050) / 10_000,
                string.concat(lsts[i].symbol, ": raw base did not over-seize")
            );

            // mocks are not part of the snapshot
            vm.clearMockedCalls();
            vm.revertTo(snapshot);
        }
    }

    function _assertSeizeUnaffectedByWindow(int256 moveBps) internal {
        uint256 incentive = comptroller.liquidationIncentiveMantissa();

        uint256[] memory seizedOutside = new uint256[](lsts.length);
        for (uint256 i = 0; i < lsts.length; i++) {
            seizedOutside[i] = _seize(lsts[i]);
        }

        uint256 wethPriceBefore = oracle.getUnderlyingPrice(mWeth);
        int256 fresh = _openWindow(moveBps);
        assertEq(
            oracle.getUnderlyingPrice(mWeth),
            wethPriceBefore,
            "WETH price moved inside the delay window"
        );

        for (uint256 i = 0; i < lsts.length; i++) {
            MToken mLst = MToken(addresses.getAddress(lsts[i].mTokenKey));
            ChainlinkCompositeOracle rawComposite = _deprecated(lsts[i]);
            ChainlinkCompositeOracle composite = ChainlinkCompositeOracle(
                address(oracle.getFeed(_symbol(lsts[i])))
            );

            // non-vacuity: the raw-base composite already sees the new round
            (, int256 rawAnswer, , , ) = rawComposite.latestRoundData();
            (, int256 answer, , , ) = composite.latestRoundData();
            assertTrue(
                rawAnswer != answer,
                string.concat(lsts[i].symbol, ": window did not open")
            );

            uint256 seized = _seize(lsts[i]);
            assertEq(
                seized,
                seizedOutside[i],
                string.concat(lsts[i].symbol, ": seize changed inside window")
            );
            assertApproxEqRel(
                _effectiveIncentive(mLst, rawComposite, seized, fresh),
                incentive,
                1e12,
                string.concat(lsts[i].symbol, ": effective incentive drifted")
            );
        }
    }

    /// @notice mock a new ETH/USD round moved by `moveBps`, published this block
    function _openWindow(int256 moveBps) internal returns (int256 fresh) {
        (uint80 roundId, int256 answer, , , ) = ethFeed.latestRoundData();
        fresh = (answer * (10_000 + moveBps)) / 10_000;
        vm.mockCall(
            address(ethFeed),
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(
                roundId + 1,
                fresh,
                block.timestamp,
                block.timestamp,
                roundId + 1
            )
        );
    }

    function _seize(
        CompositeOracleConfig memory config
    ) internal view returns (uint256 seized) {
        uint256 err;
        (err, seized) = comptroller.liquidateCalculateSeizeTokens(
            address(mWeth),
            addresses.getAddress(config.mTokenKey),
            REPAY
        );
        assertEq(err, 0, "seize calculation errored");
    }

    /// @notice seized value over repaid value, both at the new ETH/USD round
    function _effectiveIncentive(
        MToken mLst,
        ChainlinkCompositeOracle freshComposite,
        uint256 seized,
        int256 freshEth
    ) internal view returns (uint256) {
        (, int256 lstPrice, , , ) = freshComposite.latestRoundData();
        uint256 seizedUsd = (seized *
            mLst.exchangeRateStored() *
            uint256(lstPrice)) / 1e36;
        uint256 repayUsd = (REPAY *
            uint256(freshEth) *
            10 ** (18 - ethFeed.decimals())) / 1e18;
        return (seizedUsd * 1e18) / repayUsd;
    }

    function _deprecated(
        CompositeOracleConfig memory config
    ) internal view returns (ChainlinkCompositeOracle) {
        return
            ChainlinkCompositeOracle(
                addresses.getAddress(
                    string.concat(config.compositeOracleName, DEPRECATED_SUFFIX)
                )
            );
    }

    function _symbol(
        CompositeOracleConfig memory config
    ) internal view returns (string memory) {
        return ERC20(addresses.getAddress(config.symbol)).symbol();
    }
}
