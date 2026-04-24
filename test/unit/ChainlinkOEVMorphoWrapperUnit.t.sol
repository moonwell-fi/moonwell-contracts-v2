// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ChainlinkOEVMorphoWrapper} from "@protocol/oracles/ChainlinkOEVMorphoWrapper.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {IOEVWrapperFeed} from "@protocol/oracles/IOEVWrapperFeed.sol";
import {EIP20Interface} from "@protocol/EIP20Interface.sol";
import {MockChainlinkOracle} from "@test/mock/MockChainlinkOracle.sol";
import {MockERC20Decimals} from "@test/mock/MockERC20Decimals.sol";
import {MockOEVWrapperFeed} from "@test/mock/MockOEVWrapperFeed.sol";

/// @notice Test harness exposing internal helpers for unit tests.
/// @dev Requires Task 9 to (a) change `_getLoanTokenPrice` visibility from
///      private to internal and (b) add `_resolveRawFeed`. Until Task 9 lands
///      this file will not compile — that is the intended TDD "red" state.
contract ChainlinkOEVMorphoWrapperHarness is ChainlinkOEVMorphoWrapper {
    function exposed_getLoanTokenPrice(
        EIP20Interface loanToken
    ) external view returns (uint256) {
        return _getLoanTokenPrice(loanToken);
    }

    function exposed_resolveRawFeed(
        AggregatorV3Interface registryFeed
    ) external view returns (AggregatorV3Interface) {
        return _resolveRawFeed(registryFeed);
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
    address public mockChainlinkOracle = address(0xABCD); // registry stub via vm.mockCall
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

    /// @notice DRY helper: mock ChainlinkOracle.getFeed(symbol) on the
    ///         registry AND stub priceFeed() on the returned feed address
    ///         to return address(0), so _resolveRawFeed's zero-inner
    ///         defensive fallback fires and _getLoanTokenPrice reads the
    ///         feed directly as a raw aggregator.
    function _mockRegistryGetFeed(
        address registry,
        string memory symbol,
        address feed
    ) internal {
        vm.mockCall(
            registry,
            abi.encodeWithSignature("getFeed(string)", symbol),
            abi.encode(feed)
        );
        vm.mockCall(
            feed,
            abi.encodeWithSelector(IOEVWrapperFeed.priceFeed.selector),
            abi.encode(address(0))
        );
    }

    /// @notice TDD (Task 8): when the registry returns an OEV wrapper (a
    ///         contract that exposes priceFeed() pointing at an inner raw
    ///         aggregator), _getLoanTokenPrice must single-hop-dereference
    ///         to the inner aggregator and read the fresh price from it.
    ///
    ///         FAILING MECHANISM (pre-Task 9):
    ///         - Current `_getLoanTokenPrice` is PRIVATE (this file will not
    ///           compile until Task 9 changes it to internal).
    ///         - Current code does not call `_resolveRawFeed` (which Task 9
    ///           adds), so the outer wrapper's own (stale) price is read.
    ///         After Task 9 the harness compiles, _resolveRawFeed dereferences
    ///         outer → inner, and this assertion passes.
    function testLoanPriceDerefsPriceFeedWhenRegistryEntryIsOEVWrapper()
        public
    {
        // Inner (raw) feed — this is what _getLoanTokenPrice must read.
        MockChainlinkOracle innerRaw = new MockChainlinkOracle(2_000e8, 8);
        innerRaw.set(1, 2_000e8, 1, block.timestamp, 1);

        // Outer OEV wrapper registered in ChainlinkOracle. Its own
        // latestRoundData returns a stale 1_500e8 to prove we don't read it.
        MockOEVWrapperFeed outerWrapper = new MockOEVWrapperFeed(
            address(innerRaw),
            8,
            "MOCK_WRAPPER",
            1
        );
        outerWrapper.setLatestRound(1, 1_500e8, 1, block.timestamp, 1);

        string memory loanSymbol = loanToken.symbol();
        // Only mock getFeed — outerWrapper's priceFeed() is native.
        vm.mockCall(
            mockChainlinkOracle,
            abi.encodeWithSignature("getFeed(string)", loanSymbol),
            abi.encode(address(outerWrapper))
        );

        uint256 priceScaled = harness.exposed_getLoanTokenPrice(
            EIP20Interface(address(loanToken))
        );

        assertEq(priceScaled, 2_000e18, "wrapper was not dereferenced");
    }

    /// @notice Regression: registry returns a raw aggregator (helper stubs
    ///         priceFeed() to address(0), triggering zero-inner defensive
    ///         fallback). _getLoanTokenPrice must read the feed directly.
    function testLoanPriceReadsRawFeedWhenRegistryEntryIsRaw() public {
        MockChainlinkOracle rawLoanFeed = new MockChainlinkOracle(2_000e8, 8);
        rawLoanFeed.set(1, 2_000e8, 1, block.timestamp, 1);

        string memory loanSymbol = loanToken.symbol();
        _mockRegistryGetFeed(
            mockChainlinkOracle,
            loanSymbol,
            address(rawLoanFeed)
        );

        uint256 priceScaled = harness.exposed_getLoanTokenPrice(
            EIP20Interface(address(loanToken))
        );
        assertEq(priceScaled, 2_000e18, "raw feed price not used");
    }

    /// @notice Genuine try/catch branch: registry returns a contract that has
    ///         no priceFeed() selector (MockChainlinkOracle doesn't). The
    ///         try/catch must swallow the revert and fall through.
    function testLoanPriceReadsRawFeedWhenRegistryEntryLacksPriceFeedSelector()
        public
    {
        MockChainlinkOracle rawLoanFeed = new MockChainlinkOracle(2_500e8, 8);
        rawLoanFeed.set(1, 2_500e8, 1, block.timestamp, 1);

        string memory loanSymbol = loanToken.symbol();
        // Mock ONLY getFeed — do NOT stub priceFeed() on the feed, so the
        // MockChainlinkOracle's missing selector triggers a revert that the
        // try/catch must catch.
        vm.mockCall(
            mockChainlinkOracle,
            abi.encodeWithSignature("getFeed(string)", loanSymbol),
            abi.encode(address(rawLoanFeed))
        );

        uint256 priceScaled = harness.exposed_getLoanTokenPrice(
            EIP20Interface(address(loanToken))
        );
        assertEq(
            priceScaled,
            2_500e18,
            "try/catch fallthrough did not read raw feed"
        );
    }

    /// @notice Defensive fallback: registry returns an OEV wrapper whose
    ///         priceFeed() is address(0). _resolveRawFeed must ignore the
    ///         zero inner and return the outer wrapper — which is then read.
    function testLoanPriceFallsBackToOuterWhenInnerIsZero() public {
        MockOEVWrapperFeed outerWrapper = new MockOEVWrapperFeed(
            address(0),
            8,
            "MOCK_WRAPPER_ZERO_INNER",
            1
        );
        outerWrapper.setLatestRound(1, 1_500e8, 1, block.timestamp, 1);

        string memory loanSymbol = loanToken.symbol();
        vm.mockCall(
            mockChainlinkOracle,
            abi.encodeWithSignature("getFeed(string)", loanSymbol),
            abi.encode(address(outerWrapper))
        );

        uint256 priceScaled = harness.exposed_getLoanTokenPrice(
            EIP20Interface(address(loanToken))
        );
        assertEq(priceScaled, 1_500e18, "defensive fallback not taken");
    }

    /// @notice Single-hop: three-level chain outer -> middle -> innerInner.
    ///         _resolveRawFeed must stop at middle.
    function testDerefIsSingleHop() public {
        MockChainlinkOracle innerInner = new MockChainlinkOracle(9_999e8, 8);
        innerInner.set(1, 9_999e8, 1, block.timestamp, 1);

        MockOEVWrapperFeed middleWrapper = new MockOEVWrapperFeed(
            address(innerInner),
            8,
            "MIDDLE",
            1
        );
        middleWrapper.setLatestRound(1, 4_242e8, 1, block.timestamp, 1);

        MockOEVWrapperFeed outerWrapper = new MockOEVWrapperFeed(
            address(middleWrapper),
            8,
            "OUTER",
            1
        );
        outerWrapper.setLatestRound(1, 1e8, 1, block.timestamp, 1);

        string memory loanSymbol = loanToken.symbol();
        vm.mockCall(
            mockChainlinkOracle,
            abi.encodeWithSignature("getFeed(string)", loanSymbol),
            abi.encode(address(outerWrapper))
        );

        uint256 priceScaled = harness.exposed_getLoanTokenPrice(
            EIP20Interface(address(loanToken))
        );
        assertEq(priceScaled, 4_242e18, "deref took more than one hop");
    }

    /// @notice Validation parity: updatedAt == 0 must revert (previously the
    ///         Morpho wrapper skipped this check; now it matches the Core
    ///         wrapper via _validateRoundData).
    function testLoanPriceRevertsOnZeroUpdatedAt() public {
        MockChainlinkOracle rawLoanFeed = new MockChainlinkOracle(1e8, 8);
        rawLoanFeed.set(1, 1e8, 1, 0, 1); // updatedAt = 0

        string memory loanSymbol = loanToken.symbol();
        _mockRegistryGetFeed(
            mockChainlinkOracle,
            loanSymbol,
            address(rawLoanFeed)
        );

        vm.expectRevert("Round is in incompleted state");
        harness.exposed_getLoanTokenPrice(EIP20Interface(address(loanToken)));
    }

    /// @notice Validation parity: answeredInRound < roundId must revert.
    function testLoanPriceRevertsOnStaleAnsweredInRound() public {
        MockChainlinkOracle rawLoanFeed = new MockChainlinkOracle(1e8, 8);
        rawLoanFeed.set(2, 1e8, 1, block.timestamp, 1); // answeredInRound (1) < roundId (2)

        string memory loanSymbol = loanToken.symbol();
        _mockRegistryGetFeed(
            mockChainlinkOracle,
            loanSymbol,
            address(rawLoanFeed)
        );

        vm.expectRevert("Stale price");
        harness.exposed_getLoanTokenPrice(EIP20Interface(address(loanToken)));
    }

    /// @notice Validation parity: answer <= 0 must revert (was already checked
    ///         but via a different error message; now uses _validateRoundData's
    ///         standard message).
    function testLoanPriceRevertsOnNonPositiveAnswer() public {
        MockChainlinkOracle rawLoanFeed = new MockChainlinkOracle(1e8, 8);
        rawLoanFeed.set(1, 0, 1, block.timestamp, 1); // answer = 0

        string memory loanSymbol = loanToken.symbol();
        _mockRegistryGetFeed(
            mockChainlinkOracle,
            loanSymbol,
            address(rawLoanFeed)
        );

        vm.expectRevert("Chainlink price cannot be lower or equal to 0");
        harness.exposed_getLoanTokenPrice(EIP20Interface(address(loanToken)));
    }
}
