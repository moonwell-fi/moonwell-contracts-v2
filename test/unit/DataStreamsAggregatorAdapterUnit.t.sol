// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";

import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {PriceLib} from "@protocol/marketplace/PriceLib.sol";
import {
    DataStreamsAggregatorAdapter,
    IVerifierProxy,
    ReportV10
} from "@protocol/oracles/DataStreamsAggregatorAdapter.sol";
import {MockDataStreamsVerifierV10} from "@test/mock/MockDataStreamsVerifierV10.sol";
import {MockERC20Decimals} from "@test/mock/MockERC20Decimals.sol";

contract DataStreamsAggregatorAdapterUnit is Test {
    bytes32 internal constant FEED_ID =
        0x000a9811a9bef734e52059c184312bd9ebf24b3ce5f86285f693eacbb7151baa;
    int192 internal constant PRICE = 250e18; // $250 / share, 18-dec stream
    int192 internal constant MULT = 1e18; // 1.0 share per token

    uint256 internal constant NOW = 1_700_000_000;

    address internal owner = makeAddr("owner");
    address internal keeper = makeAddr("keeper");

    MockDataStreamsVerifierV10 internal verifier;
    DataStreamsAggregatorAdapter internal adapter;

    function setUp() public {
        vm.warp(NOW);
        verifier = new MockDataStreamsVerifierV10(FEED_ID, PRICE, MULT);
        adapter = new DataStreamsAggregatorAdapter(
            IVerifierProxy(address(verifier)),
            FEED_ID,
            18,
            owner,
            keeper
        );
    }

    /// fullReport that decodes as `(bytes32[3], bytes)` — the mock ignores it.
    function _fr() internal pure returns (bytes memory) {
        bytes32[3] memory ctx;
        return abi.encode(ctx, bytes(""));
    }

    function _update() internal {
        vm.prank(keeper);
        adapter.verifyAndUpdate(_fr());
    }

    // ─── verify + theoretical price ───────────────────────────────────────

    function test_verifyAndUpdate_cachesTheoreticalPrice() public {
        _update();
        (uint80 rid, int256 ans, , uint256 upd, ) = adapter.latestRoundData();
        assertEq(ans, 250e18, "answer = price * mult / 1e18");
        assertEq(upd, NOW, "updatedAt = observationsTimestamp");
        assertEq(rid, 1, "roundId increments from 0");
    }

    function test_verifyAndUpdate_appliesMultiplier() public {
        verifier.setMultiplier(2e18); // 2 shares per token
        _update();
        (, int256 ans, , , ) = adapter.latestRoundData();
        assertEq(ans, 500e18, "250 * 2");
    }

    function test_verifyAndUpdate_onlyKeeper() public {
        vm.expectRevert(DataStreamsAggregatorAdapter.OnlyKeeper.selector);
        adapter.verifyAndUpdate(_fr());
    }

    function test_verifyAndUpdate_wrongFeed_reverts() public {
        bytes32 other = bytes32(uint256(1));
        verifier.setFeedId(other);
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                DataStreamsAggregatorAdapter.WrongFeed.selector,
                other,
                FEED_ID
            )
        );
        adapter.verifyAndUpdate(_fr());
    }

    function test_verifyAndUpdate_marketClosed_reverts() public {
        verifier.setMarketStatus(1); // Closed
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                DataStreamsAggregatorAdapter.MarketClosed.selector,
                uint32(1)
            )
        );
        adapter.verifyAndUpdate(_fr());
    }

    function test_verifyAndUpdate_zeroPrice_reverts() public {
        verifier.setPrice(0);
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                DataStreamsAggregatorAdapter.InvalidPrice.selector,
                int192(0)
            )
        );
        adapter.verifyAndUpdate(_fr());
    }

    function test_verifyAndUpdate_zeroMultiplier_reverts() public {
        verifier.setMultiplier(0);
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                DataStreamsAggregatorAdapter.InvalidMultiplier.selector,
                int192(0)
            )
        );
        adapter.verifyAndUpdate(_fr());
    }

    function test_verifyAndUpdate_expired_reverts() public {
        verifier.setTimestamps(uint32(NOW - 10), uint32(NOW - 1));
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                DataStreamsAggregatorAdapter.ReportExpired.selector,
                uint32(NOW - 1)
            )
        );
        adapter.verifyAndUpdate(_fr());
    }

    function test_verifyAndUpdate_nonMonotonic_reverts() public {
        _update(); // observationsTimestamp = NOW, stored = NOW
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                DataStreamsAggregatorAdapter.StaleReport.selector,
                uint32(NOW),
                uint64(NOW)
            )
        );
        adapter.verifyAndUpdate(_fr()); // same block → not strictly newer
    }

    function test_verifyAndUpdate_monotonicAdvancesAcrossBlocks() public {
        _update();
        vm.warp(NOW + 60);
        _update(); // newer observationsTimestamp → ok
        (, , , uint256 upd, ) = adapter.latestRoundData();
        assertEq(upd, NOW + 60);
    }

    // ─── bootstrap ────────────────────────────────────────────────────────

    function test_bootstrap_setsAnswer() public {
        vm.prank(owner);
        adapter.bootstrap(100e18);
        (uint80 rid, int256 ans, , uint256 upd, ) = adapter.latestRoundData();
        assertEq(ans, 100e18);
        assertEq(upd, NOW, "updatedAt = block.timestamp at bootstrap");
        assertEq(rid, 1);
    }

    function test_bootstrap_onlyOwner() public {
        vm.expectRevert(DataStreamsAggregatorAdapter.OnlyOwner.selector);
        adapter.bootstrap(100e18);
    }

    function test_bootstrap_oneShot() public {
        vm.startPrank(owner);
        adapter.bootstrap(100e18);
        vm.expectRevert(
            DataStreamsAggregatorAdapter.AlreadyBootstrapped.selector
        );
        adapter.bootstrap(200e18);
        vm.stopPrank();
    }

    /// bootstrap leaves observationsTs = 0, so the first real report's
    /// timestamp passes the monotonic guard and overwrites the seed.
    function test_bootstrap_thenVerifyOverwrites() public {
        vm.prank(owner);
        adapter.bootstrap(100e18);
        _update();
        (, int256 ans, , , ) = adapter.latestRoundData();
        assertEq(ans, 250e18, "verified price overwrites bootstrap seed");
    }

    // ─── facade ───────────────────────────────────────────────────────────

    function test_latestRoundData_revertsBeforeInit() public {
        vm.expectRevert(DataStreamsAggregatorAdapter.NotInitialized.selector);
        adapter.latestRoundData();
    }

    function test_decimals_descriptionVersion() public view {
        assertEq(adapter.decimals(), 18);
        assertEq(adapter.version(), 1);
        assertGt(bytes(adapter.description()).length, 0);
    }

    // ─── ops ──────────────────────────────────────────────────────────────

    function test_setKeeper_onlyOwner_andEffect() public {
        address k2 = makeAddr("k2");
        vm.expectRevert(DataStreamsAggregatorAdapter.OnlyOwner.selector);
        adapter.setKeeper(k2);

        vm.prank(owner);
        adapter.setKeeper(k2);
        assertEq(adapter.keeper(), k2);

        vm.prank(k2);
        adapter.verifyAndUpdate(_fr()); // new keeper works
    }

    function test_setOwner_onlyOwner_andEffect() public {
        address o2 = makeAddr("o2");
        vm.prank(owner);
        adapter.setOwner(o2);
        assertEq(adapter.owner(), o2);
    }

    // ─── PriceLib integration (pins the decimals contract) ────────────────

    function test_priceLib_valuesCollateralInUsd1e18() public {
        _update(); // adapter answer = 250e18, decimals = 18
        MockERC20Decimals token = new MockERC20Decimals("wbCOIN", "wbCOIN", 18);
        // 3 tokens @ $250 = $750, in 1e18 USD
        uint256 v = PriceLib.valueToUsd1e18(
            address(token),
            3e18,
            AggregatorV3Interface(address(adapter)),
            1 hours
        );
        assertEq(v, 750e18);
    }
}
