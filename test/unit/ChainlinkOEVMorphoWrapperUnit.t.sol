// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ChainlinkOEVMorphoWrapper} from "@protocol/oracles/ChainlinkOEVMorphoWrapper.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {EIP20Interface} from "@protocol/EIP20Interface.sol";
import {IMorphoChainlinkOracleV2} from "@protocol/morpho/IMorphoChainlinkOracleV2.sol";
import {MarketParams} from "@protocol/morpho/IMetaMorpho.sol";
import {MockChainlinkOracle} from "@test/mock/MockChainlinkOracle.sol";
import {MockERC20Decimals} from "@test/mock/MockERC20Decimals.sol";

/// @notice Test harness exposing internal helpers for unit tests.
/// @dev `_getLoanTokenPrice` visibility is `internal` so this harness can call
///      it directly with a constructed MarketParams pointing at a mock per-
///      market Morpho oracle whose `QUOTE_FEED_1()` returns a configurable feed.
contract ChainlinkOEVMorphoWrapperHarness is ChainlinkOEVMorphoWrapper {
    function exposed_getLoanTokenPrice(
        MarketParams memory marketParams
    ) external view returns (uint256) {
        return _getLoanTokenPrice(marketParams);
    }
}

contract ChainlinkOEVMorphoWrapperUnitTest is Test {
    address public owner = address(0x1);
    address public morphoBlue = address(0xB);
    address public feeRecipient = address(0x5);
    uint16 public defaultFeeBps = 100; // 1%
    uint256 public defaultMaxRoundDelay = 300; // 5 minutes
    uint256 public defaultMaxDecrements = 5;

    MockChainlinkOracle mockPriceFeed;
    address public mockChainlinkOracle = address(0xABCD); // vestigial registry stub
    MockERC20Decimals loanToken;

    ChainlinkOEVMorphoWrapperHarness harness;

    function setUp() public {
        // A minimal Chainlink feed used as the wrapper's own `priceFeed`.
        mockPriceFeed = new MockChainlinkOracle(1e8, 8);
        mockPriceFeed.set(1, 1e8, 1, block.timestamp, 1);

        loanToken = new MockERC20Decimals("Loan", "LOAN", 18);

        // Deploy harness behind an ERC1967Proxy so the reinitializer path
        // works. The implementation is our harness subclass so the exposed_*
        // external view functions are callable through the proxy.
        ChainlinkOEVMorphoWrapperHarness impl = new ChainlinkOEVMorphoWrapperHarness();
        bytes memory initData = abi.encodeWithSelector(
            ChainlinkOEVMorphoWrapper.initializeV2.selector,
            address(mockPriceFeed),
            owner,
            morphoBlue,
            mockChainlinkOracle,
            feeRecipient,
            defaultFeeBps,
            defaultMaxRoundDelay,
            defaultMaxDecrements
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        harness = ChainlinkOEVMorphoWrapperHarness(payable(address(proxy)));
    }

    /// @notice Helper that constructs a MarketParams pointing at a mock Morpho
    ///         oracle whose `QUOTE_FEED_1()` returns the supplied address.
    /// @dev Stubs `QUOTE_FEED_2()` and `BASE_FEED_2()` to return address(0)
    ///      by default, satisfying the wrapper's defensive checks against
    ///      chained feeds. Tests that need a non-zero second feed should
    ///      override the stub with their own `vm.mockCall`.
    function _makeMarketParams(
        address loanTokenAddr,
        address quoteFeed
    ) internal returns (MarketParams memory mp) {
        address mockMorphoOracle = address(
            uint160(uint256(keccak256(abi.encode("morpho-oracle", quoteFeed))))
        );
        vm.mockCall(
            mockMorphoOracle,
            abi.encodeWithSelector(
                IMorphoChainlinkOracleV2.QUOTE_FEED_1.selector
            ),
            abi.encode(quoteFeed)
        );
        vm.mockCall(
            mockMorphoOracle,
            abi.encodeWithSelector(
                IMorphoChainlinkOracleV2.QUOTE_FEED_2.selector
            ),
            abi.encode(address(0))
        );
        vm.mockCall(
            mockMorphoOracle,
            abi.encodeWithSelector(
                IMorphoChainlinkOracleV2.BASE_FEED_2.selector
            ),
            abi.encode(address(0))
        );
        mp = MarketParams({
            loanToken: loanTokenAddr,
            collateralToken: address(0),
            oracle: mockMorphoOracle,
            irm: address(0),
            lltv: 0
        });
    }

    /// @notice The Morpho wrapper sources the loan-token price from the per-
    ///         market oracle's `QUOTE_FEED_1()` — which is a raw Chainlink
    ///         aggregator by Morpho convention. No registry lookup, no deref.
    function testLoanPriceReadsQuoteFeed1() public {
        MockChainlinkOracle quoteFeed = new MockChainlinkOracle(2_000e8, 8);
        quoteFeed.set(1, 2_000e8, 1, block.timestamp, 1);

        MarketParams memory mp = _makeMarketParams(
            address(loanToken),
            address(quoteFeed)
        );

        uint256 priceScaled = harness.exposed_getLoanTokenPrice(mp);
        assertEq(priceScaled, 2_000e18, "QUOTE_FEED_1 price not used");
    }

    /// @notice Defensive: if the per-market oracle returns address(0) for
    ///         QUOTE_FEED_1, the wrapper must revert with a clear message.
    function testLoanPriceRevertsWhenQuoteFeed1IsZero() public {
        MarketParams memory mp = _makeMarketParams(
            address(loanToken),
            address(0)
        );
        vm.expectRevert("ChainlinkOEVMorphoWrapper: loan feed not set");
        harness.exposed_getLoanTokenPrice(mp);
    }

    /// @notice Validation parity: updatedAt == 0 must revert (matches the
    ///         Core wrapper via _validateRoundData).
    function testLoanPriceRevertsOnZeroUpdatedAt() public {
        MockChainlinkOracle quoteFeed = new MockChainlinkOracle(1e8, 8);
        quoteFeed.set(1, 1e8, 1, 0, 1); // updatedAt = 0

        MarketParams memory mp = _makeMarketParams(
            address(loanToken),
            address(quoteFeed)
        );

        vm.expectRevert("Round is in incompleted state");
        harness.exposed_getLoanTokenPrice(mp);
    }

    /// @notice Validation parity: answeredInRound < roundId must revert.
    function testLoanPriceRevertsOnStaleAnsweredInRound() public {
        MockChainlinkOracle quoteFeed = new MockChainlinkOracle(1e8, 8);
        quoteFeed.set(2, 1e8, 1, block.timestamp, 1); // answeredInRound (1) < roundId (2)

        MarketParams memory mp = _makeMarketParams(
            address(loanToken),
            address(quoteFeed)
        );

        vm.expectRevert("Stale price");
        harness.exposed_getLoanTokenPrice(mp);
    }

    /// @notice Validation parity: answer <= 0 must revert.
    function testLoanPriceRevertsOnNonPositiveAnswer() public {
        MockChainlinkOracle quoteFeed = new MockChainlinkOracle(1e8, 8);
        quoteFeed.set(1, 0, 1, block.timestamp, 1); // answer = 0

        MarketParams memory mp = _makeMarketParams(
            address(loanToken),
            address(quoteFeed)
        );

        vm.expectRevert("Chainlink price cannot be lower or equal to 0");
        harness.exposed_getLoanTokenPrice(mp);
    }

    /// @notice Defensive: if the per-market oracle exposes a non-zero
    ///         QUOTE_FEED_2(), the wrapper must reject — Morpho's chained
    ///         feed mode is not supported by this OEV wrapper because the
    ///         split math reads only QUOTE_FEED_1 directly.
    function testLoanPriceRevertsWhenQuoteFeed2IsSet() public {
        MockChainlinkOracle quoteFeed = new MockChainlinkOracle(2_000e8, 8);
        quoteFeed.set(1, 2_000e8, 1, block.timestamp, 1);

        MarketParams memory mp = _makeMarketParams(
            address(loanToken),
            address(quoteFeed)
        );

        // Override the helper's default address(0) stub with a non-zero feed
        // address to simulate a chained-quote market.
        vm.mockCall(
            mp.oracle,
            abi.encodeWithSelector(
                IMorphoChainlinkOracleV2.QUOTE_FEED_2.selector
            ),
            abi.encode(address(0xBEEF))
        );

        vm.expectRevert(
            "ChainlinkOEVMorphoWrapper: chained quote feeds unsupported"
        );
        harness.exposed_getLoanTokenPrice(mp);
    }

    /// @notice Mirror of the QUOTE_FEED_2 guard for BASE_FEED_2: a non-zero
    ///         BASE_FEED_2 means the Morpho oracle chains the base price
    ///         through a second feed. This wrapper only reads BASE_FEED_1
    ///         (the collateral aggregator), so chained-base markets must be
    ///         rejected to avoid silently mispricing the loan-vs-collateral
    ///         split.
    function testLoanPriceRevertsWhenBaseFeed2IsSet() public {
        MockChainlinkOracle quoteFeed = new MockChainlinkOracle(2_000e8, 8);
        quoteFeed.set(1, 2_000e8, 1, block.timestamp, 1);

        MarketParams memory mp = _makeMarketParams(
            address(loanToken),
            address(quoteFeed)
        );

        vm.mockCall(
            mp.oracle,
            abi.encodeWithSelector(
                IMorphoChainlinkOracleV2.BASE_FEED_2.selector
            ),
            abi.encode(address(0xBEEF))
        );

        vm.expectRevert(
            "ChainlinkOEVMorphoWrapper: chained base feeds unsupported"
        );
        harness.exposed_getLoanTokenPrice(mp);
    }

    /// @notice 6-decimal loan token (USDC-like) must scale to 1e30 when fed
    ///         a 1e8 price from an 8-decimal Chainlink aggregator.
    function testLoanPriceScalesToTokenDecimals6() public {
        MockERC20Decimals usdcLike = new MockERC20Decimals(
            "USDC-like",
            "USDC6",
            6
        );
        MockChainlinkOracle quoteFeed = new MockChainlinkOracle(1e8, 8);
        quoteFeed.set(1, 1e8, 1, block.timestamp, 1);

        MarketParams memory mp = _makeMarketParams(
            address(usdcLike),
            address(quoteFeed)
        );

        uint256 priceScaled = harness.exposed_getLoanTokenPrice(mp);
        // 1e8 @ 8 decimals -> 1e18 in feed-scaled.
        // Then 6-decimal token scales by 1e12 -> 1e30.
        assertEq(priceScaled, 1e30, "6-decimal scaling wrong");
    }
}
