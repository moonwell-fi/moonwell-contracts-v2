pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {WstETHExchangeRateAdapter} from "@protocol/oracles/WstETHExchangeRateAdapter.sol";
import {ChainlinkCompositeOracle} from "@protocol/oracles/ChainlinkCompositeOracle.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

contract WstETHExchangeRateAdapterIntegrationTest is Test {
    WstETHExchangeRateAdapter public adapter;

    /// Ethereum mainnet addresses
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant CHAINLINK_ETH_USD =
        0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public constant CHAINLINK_STETH_ETH =
        0x86392dC19c0b719886221c78AB11eb8Cf5c52812;

    function setUp() public {
        adapter = new WstETHExchangeRateAdapter(WSTETH);
    }

    function testAdapterReturnsValidExchangeRate() public view {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = adapter.latestRoundData();

        assertTrue(answer > 0, "Exchange rate should be positive");
        assertEq(roundId, 1);
        assertEq(answeredInRound, 1);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
    }

    function testExchangeRateInExpectedRange() public view {
        (, int256 answer, , , ) = adapter.latestRoundData();

        /// wstETH/stETH rate should be between 1.0 and 2.0 stETH per wstETH
        /// As of early 2025, the rate is ~1.19-1.22
        assertTrue(
            answer >= 1.0e18,
            "Rate should be at least 1.0 stETH per wstETH"
        );
        assertTrue(
            answer <= 2.0e18,
            "Rate should be at most 2.0 stETH per wstETH"
        );
    }

    function testDecimalsIs18() public view {
        assertEq(adapter.decimals(), 18);
    }

    function testThreeFeedCompositeOracle() public {
        /// Deploy 3-feed composite: ETH/USD × stETH/ETH × wstETH/stETH(adapter)
        ChainlinkCompositeOracle compositeOracle = new ChainlinkCompositeOracle(
            CHAINLINK_ETH_USD,
            CHAINLINK_STETH_ETH,
            address(adapter)
        );

        (, int256 answer, , uint256 updatedAt, ) = compositeOracle
            .latestRoundData();

        assertTrue(answer > 0, "wstETH/USD price should be positive");
        assertEq(updatedAt, block.timestamp);

        /// wstETH/USD should be roughly ETH price * 1.19
        /// With ETH at ~$1500-$5000, wstETH should be in a reasonable range
        /// Use a wide range to avoid flaky tests across different fork blocks
        assertTrue(
            answer >= 100e18, // at least $100
            "wstETH/USD price too low"
        );
        assertTrue(
            answer <= 100_000e18, // at most $100,000
            "wstETH/USD price too high"
        );
    }

    function testCompositeOraclePriceVsStETHSanityCheck() public {
        /// 3-feed wstETH/USD oracle
        ChainlinkCompositeOracle wstEthOracle = new ChainlinkCompositeOracle(
            CHAINLINK_ETH_USD,
            CHAINLINK_STETH_ETH,
            address(adapter)
        );

        /// 2-feed stETH/USD oracle (for comparison)
        ChainlinkCompositeOracle stEthOracle = new ChainlinkCompositeOracle(
            CHAINLINK_ETH_USD,
            CHAINLINK_STETH_ETH,
            address(0)
        );

        (, int256 wstEthPrice, , , ) = wstEthOracle.latestRoundData();
        (, int256 stEthPrice, , , ) = stEthOracle.latestRoundData();

        /// wstETH should be worth more than stETH (since 1 wstETH > 1 stETH)
        assertTrue(
            wstEthPrice > stEthPrice,
            "wstETH/USD should be greater than stETH/USD"
        );

        /// The ratio should match the exchange rate from the adapter
        (, int256 exchangeRate, , , ) = adapter.latestRoundData();

        /// wstETH/USD ≈ stETH/USD × exchangeRate
        uint256 expectedWstEthPrice = (uint256(stEthPrice) *
            uint256(exchangeRate)) / 1e18;
        assertApproxEqRel(
            uint256(wstEthPrice),
            expectedWstEthPrice,
            0.001e18 // 0.1% tolerance for rounding
        );
    }
}
