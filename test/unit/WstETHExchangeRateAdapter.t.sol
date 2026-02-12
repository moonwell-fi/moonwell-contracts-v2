pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {IWstETH, WstETHExchangeRateAdapter} from "@protocol/oracles/WstETHExchangeRateAdapter.sol";
import {ChainlinkCompositeOracle} from "@protocol/oracles/ChainlinkCompositeOracle.sol";
import {MockChainlinkOracle} from "@test/mock/MockChainlinkOracle.sol";

/// @notice Mock wstETH contract for unit testing
contract MockWstETH is IWstETH {
    uint256 public rate;

    constructor(uint256 _rate) {
        rate = _rate;
    }

    function stEthPerToken() external view override returns (uint256) {
        return rate;
    }

    function setRate(uint256 _rate) external {
        rate = _rate;
    }
}

contract WstETHExchangeRateAdapterUnitTest is Test {
    WstETHExchangeRateAdapter public adapter;
    MockWstETH public mockWstETH;

    /// ~1.19 stETH per wstETH (realistic rate)
    uint256 constant MOCK_RATE = 1.19e18;

    function setUp() public {
        mockWstETH = new MockWstETH(MOCK_RATE);
        adapter = new WstETHExchangeRateAdapter(address(mockWstETH));
    }

    function testDecimals() public view {
        assertEq(adapter.decimals(), 18);
    }

    function testDescription() public view {
        assertEq(adapter.description(), "wstETH/stETH Exchange Rate");
    }

    function testVersion() public view {
        assertEq(adapter.version(), 1);
    }

    function testLatestRound() public view {
        assertEq(adapter.latestRound(), 1);
    }

    function testWstETHAddress() public view {
        assertEq(address(adapter.wstETH()), address(mockWstETH));
    }

    function testLatestRoundData() public view {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = adapter.latestRoundData();

        assertEq(roundId, 1);
        assertEq(answer, int256(MOCK_RATE));
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 1);
    }

    function testLatestRoundDataPositiveAnswer() public view {
        (, int256 answer, , , ) = adapter.latestRoundData();
        assertTrue(answer > 0, "Answer should be positive");
    }

    function testRoundIdEqualsAnsweredInRound() public view {
        (uint80 roundId, , , , uint80 answeredInRound) = adapter
            .latestRoundData();
        assertEq(
            roundId,
            answeredInRound,
            "roundId must equal answeredInRound for ChainlinkCompositeOracle validation"
        );
    }

    function testGetRoundDataDelegatesToLatestRoundData() public view {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = adapter.getRoundData(999);

        assertEq(roundId, 1);
        assertEq(answer, int256(MOCK_RATE));
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 1);
    }

    function testRevertsWhenExchangeRateIsZero() public {
        mockWstETH.setRate(0);
        vm.expectRevert(WstETHExchangeRateAdapter.InvalidExchangeRate.selector);
        adapter.latestRoundData();
    }

    function testWorksWithChainlinkCompositeOracle() public {
        /// ETH/USD = $2500
        MockChainlinkOracle ethUsd = new MockChainlinkOracle(2500e8, 8);
        /// stETH/ETH = 0.9998
        MockChainlinkOracle stEthEth = new MockChainlinkOracle(0.9998e18, 18);

        ChainlinkCompositeOracle compositeOracle = new ChainlinkCompositeOracle(
            address(ethUsd),
            address(stEthEth),
            address(adapter)
        );

        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = compositeOracle.latestRoundData();

        assertTrue(answer > 0, "Composite price should be positive");
        assertEq(updatedAt, block.timestamp);
        assertEq(roundId, 0);
        assertEq(answeredInRound, 0);

        /// Expected: 2500 * 0.9998 * 1.19 ≈ 2974.405e18
        uint256 expectedPrice = (2500e18 * 0.9998e18 * MOCK_RATE) / 1e36;
        assertApproxEqRel(
            uint256(answer),
            expectedPrice,
            0.001e18 // 0.1% tolerance
        );
    }

    function testFuzzRate(uint256 rate) public {
        rate = bound(rate, 1, 100e18); // reasonable range
        mockWstETH.setRate(rate);

        (, int256 answer, , , ) = adapter.latestRoundData();
        assertEq(uint256(answer), rate);
        assertTrue(answer > 0);
    }
}
