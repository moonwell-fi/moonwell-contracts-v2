pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {IWstETH, ILidoAccountingOracle, WstETHExchangeRateAdapter} from "@protocol/oracles/WstETHExchangeRateAdapter.sol";
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

/// @notice Mock Lido AccountingOracle for unit testing
contract MockLidoAccountingOracle is ILidoAccountingOracle {
    uint256 public slot;

    constructor(uint256 _slot) {
        slot = _slot;
    }

    function getLastProcessingRefSlot()
        external
        view
        override
        returns (uint256)
    {
        return slot;
    }

    function setSlot(uint256 _slot) external {
        slot = _slot;
    }
}

contract WstETHExchangeRateAdapterUnitTest is Test {
    WstETHExchangeRateAdapter public adapter;
    MockWstETH public mockWstETH;
    MockLidoAccountingOracle public mockOracle;

    /// ~1.19 stETH per wstETH (realistic rate)
    uint256 constant MOCK_RATE = 1.19e18;

    /// Beacon Chain constants
    uint256 constant BEACON_GENESIS_TIMESTAMP = 1606824023;
    uint256 constant SECONDS_PER_SLOT = 12;

    /// A realistic slot number (~April 2025)
    uint256 constant MOCK_SLOT = 10_000_000;
    uint256 constant MOCK_TIMESTAMP =
        BEACON_GENESIS_TIMESTAMP + (MOCK_SLOT * SECONDS_PER_SLOT);

    function setUp() public {
        mockWstETH = new MockWstETH(MOCK_RATE);
        mockOracle = new MockLidoAccountingOracle(MOCK_SLOT);
        adapter = new WstETHExchangeRateAdapter(
            address(mockWstETH),
            address(mockOracle)
        );
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

    function testLidoOracleAddress() public view {
        assertEq(address(adapter.lidoOracle()), address(mockOracle));
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
        assertEq(startedAt, MOCK_TIMESTAMP);
        assertEq(updatedAt, MOCK_TIMESTAMP);
        assertEq(answeredInRound, 1);
    }

    function testUpdatedAtReflectsOracleSlot() public {
        uint256 newSlot = 11_000_000;
        mockOracle.setSlot(newSlot);

        (, , , uint256 updatedAt, ) = adapter.latestRoundData();
        assertEq(
            updatedAt,
            BEACON_GENESIS_TIMESTAMP + (newSlot * SECONDS_PER_SLOT)
        );
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
        assertEq(startedAt, MOCK_TIMESTAMP);
        assertEq(updatedAt, MOCK_TIMESTAMP);
        assertEq(answeredInRound, 1);
    }

    function testRevertsWhenExchangeRateIsZero() public {
        mockWstETH.setRate(0);
        vm.expectRevert(WstETHExchangeRateAdapter.InvalidExchangeRate.selector);
        adapter.latestRoundData();
    }

    function testRevertsWhenExchangeRateOverflows() public {
        mockWstETH.setRate(uint256(type(int256).max) + 1);
        vm.expectRevert(
            WstETHExchangeRateAdapter.ExchangeRateOverflow.selector
        );
        adapter.latestRoundData();
    }

    function testWorksWithChainlinkCompositeOracle() public {
        /// Warp to a realistic timestamp so MockChainlinkOracle (which uses
        /// block.timestamp) returns a timestamp comparable to the adapter's
        vm.warp(MOCK_TIMESTAMP + 100);

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
        /// After HAL-02, ChainlinkCompositeOracle propagates the minimum
        /// `updatedAt` across all sub-feeds instead of substituting
        /// block.timestamp. `MockChainlinkOracle` hardcodes its `_updatedAt`
        /// to a fixed point in time that is older than the adapter's
        /// Lido-derived timestamp, so the ETH/USD sub-feed's `updatedAt` is
        /// the minimum and must be what the composite oracle surfaces.
        (, , , uint256 minSubFeedUpdatedAt, ) = ethUsd.latestRoundData();
        assertEq(updatedAt, minSubFeedUpdatedAt);
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
