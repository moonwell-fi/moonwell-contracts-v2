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
import {BASE_FORK_ID, OPTIMISM_FORK_ID} from "@utils/ChainIds.sol";

/// @notice MOO-1023: on Base and Optimism, ETH-derivative composites and WETH read
/// the same delayed ETH/USD round, so liquidations seize exactly the configured incentive.
contract LSTCompositeOEVLockstepIntegrationTest is
    PostProposalCheck,
    ChainlinkOracleConfigs
{
    /// @notice ETH/USD move between the cached and the new round
    int256 internal constant MOVE_BPS = 100;

    uint256 internal constant REPAY = 10e18;

    Comptroller internal comptroller;
    ChainlinkOracle internal oracle;
    ChainlinkOEVWrapper internal wrapper;
    AggregatorV3Interface internal ethFeed;
    MToken internal mWeth;
    CompositeOracleConfig[] internal lsts;

    function setUp() public override {
        super.setUp();
    }

    /// @notice select `forkId` and load its WETH/LST pricing, outside any delay window
    function _useFork(uint256 forkId) internal {
        vm.selectFork(forkId);

        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        oracle = ChainlinkOracle(addresses.getAddress("CHAINLINK_ORACLE"));
        wrapper = ChainlinkOEVWrapper(
            payable(addresses.getAddress("CHAINLINK_ETH_USD_OEV_WRAPPER"))
        );
        ethFeed = AggregatorV3Interface(
            addresses.getAddress("CHAINLINK_ETH_USD")
        );
        mWeth = MToken(addresses.getAddress("MOONWELL_WETH"));

        delete lsts;
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

    function testLstCompositesReadTheWethWrapperBase() public {
        _useFork(BASE_FORK_ID);
        _assertLstCompositesReadTheWethWrapper();
    }

    function testLstCompositesReadTheWethWrapperOptimism() public {
        _useFork(OPTIMISM_FORK_ID);
        _assertLstCompositesReadTheWethWrapper();
    }

    function testSeizeIncentiveExactInsideFallingWindowBase() public {
        _useFork(BASE_FORK_ID);
        _assertSeizeUnaffectedByWindow(-MOVE_BPS);
    }

    function testSeizeIncentiveExactInsideFallingWindowOptimism() public {
        _useFork(OPTIMISM_FORK_ID);
        _assertSeizeUnaffectedByWindow(-MOVE_BPS);
    }

    function testSeizeIncentiveExactInsideRisingWindowBase() public {
        _useFork(BASE_FORK_ID);
        _assertSeizeUnaffectedByWindow(MOVE_BPS);
    }

    function testSeizeIncentiveExactInsideRisingWindowOptimism() public {
        _useFork(OPTIMISM_FORK_ID);
        _assertSeizeUnaffectedByWindow(MOVE_BPS);
    }

    function testRawBaseCompositeOverSeizesInsideWindowBase() public {
        _useFork(BASE_FORK_ID);
        _assertRawBaseOverSeizes();
    }

    function testRawBaseCompositeOverSeizesInsideWindowOptimism() public {
        _useFork(OPTIMISM_FORK_ID);
        _assertRawBaseOverSeizes();
    }

    function _assertLstCompositesReadTheWethWrapper() internal view {
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

    /// @notice control: a raw-base composite (the pre-fix shape) over-seizes in the same window
    function _assertRawBaseOverSeizes() internal {
        uint256 incentive = comptroller.liquidationIncentiveMantissa();
        ChainlinkCompositeOracle[] memory raws = _rawComposites();

        for (uint256 i = 0; i < lsts.length; i++) {
            uint256 snapshot = vm.snapshot();
            ChainlinkCompositeOracle rawComposite = raws[i];

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
        ChainlinkCompositeOracle[] memory raws = _rawComposites();

        uint256 wethPriceBefore = oracle.getUnderlyingPrice(mWeth);
        int256 fresh = _openWindow(moveBps);
        assertEq(
            oracle.getUnderlyingPrice(mWeth),
            wethPriceBefore,
            "WETH price moved inside the delay window"
        );

        for (uint256 i = 0; i < lsts.length; i++) {
            MToken mLst = MToken(addresses.getAddress(lsts[i].mTokenKey));
            ChainlinkCompositeOracle rawComposite = raws[i];
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

    /// @notice per LST, the live composite's multipliers on the raw ETH/USD feed
    function _rawComposites()
        internal
        returns (ChainlinkCompositeOracle[] memory raws)
    {
        raws = new ChainlinkCompositeOracle[](lsts.length);
        for (uint256 i = 0; i < lsts.length; i++) {
            ChainlinkCompositeOracle live = ChainlinkCompositeOracle(
                address(oracle.getFeed(_symbol(lsts[i])))
            );
            raws[i] = new ChainlinkCompositeOracle(
                address(ethFeed),
                live.multiplier(),
                live.secondMultiplier()
            );
        }
    }

    function _symbol(
        CompositeOracleConfig memory config
    ) internal view returns (string memory) {
        return ERC20(addresses.getAddress(config.symbol)).symbol();
    }
}
