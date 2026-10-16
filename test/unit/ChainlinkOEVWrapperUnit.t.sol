// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {ChainlinkOEVWrapper} from "@protocol/oracles/ChainlinkOEVWrapper.sol";
import {MockChainlinkOracle} from "@test/mock/MockChainlinkOracle.sol";
import {MockChainlinkOracleWithoutLatestRound} from "@test/mock/MockChainlinkOracleWithoutLatestRound.sol";
import {MockOEVWrapperFeed} from "@test/mock/MockOEVWrapperFeed.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {EIP20Interface} from "@protocol/EIP20Interface.sol";
import {MockERC20Decimals} from "@test/mock/MockERC20Decimals.sol";
import {IOEVWrapperFeed} from "@protocol/oracles/IOEVWrapperFeed.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract ChainlinkOEVWrapperUnitTest is Test {
    address public owner = address(0x1);
    address public chainlinkOracle = address(0x4);
    address public feeRecipient = address(0x5);
    uint16 public defaultFeeBps = 100; // 1%
    uint256 public defaultMaxRoundDelay = 300; // 5 minutes
    uint256 public defaultMaxDecrements = 5;

    // Tokens for decimal testing
    MockERC20Decimals token6;
    MockERC20Decimals token18;
    MockERC20Decimals token24;

    // Tokens for exchange rate testing
    MockERC20Decimals collateralToken;
    MockERC20Decimals loanToken;
    MockMToken mTokenCollateral;
    MockChainlinkOracle mockChainlinkOracle;
    ChainlinkOEVWrapperHarness harness;

    // Events mirrored for expectEmit
    event LiquidatorFeeBpsChanged(
        uint16 oldLiquidatorFeeBps,
        uint16 newLiquidatorFeeBps
    );

    event MaxRoundDelayChanged(
        uint256 oldMaxRoundDelay,
        uint256 newMaxRoundDelay
    );
    event MaxDecrementsChanged(
        uint256 oldMaxDecrements,
        uint256 newMaxDecrements
    );

    function setUp() public {
        token6 = new MockERC20Decimals("Token6", "T6", 6);
        token18 = new MockERC20Decimals("Token18", "T18", 18);
        token24 = new MockERC20Decimals("Token24", "T24", 24);

        collateralToken = new MockERC20Decimals("Collateral", "COLL", 18);
        loanToken = new MockERC20Decimals("Loan", "LOAN", 18);

        mockChainlinkOracle = new MockChainlinkOracle(1e8, 8);
        mockChainlinkOracle.set(1, 1e8, 1, 1, 1);

        harness = new ChainlinkOEVWrapperHarness(
            address(mockChainlinkOracle),
            address(1),
            address(1),
            address(1),
            500,
            3600,
            10
        );
    }

    /// @notice Stub both getFeed() on the registry and priceFeed() on the feed
    ///         address so that _resolveRawFeed's try/catch returns address(0)
    ///         and falls through to treat the feed as a raw aggregator.
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
        // Stub priceFeed() to return address(0) so _resolveRawFeed's
        // defensive fallback activates and reads `feed` directly.
        vm.mockCall(
            feed,
            abi.encodeWithSelector(IOEVWrapperFeed.priceFeed.selector),
            abi.encode(address(0))
        );
    }

    function _deploy(
        address feed
    ) internal returns (ChainlinkOEVWrapper wrapper) {
        wrapper = new ChainlinkOEVWrapper(
            feed,
            owner,
            chainlinkOracle,
            feeRecipient,
            defaultFeeBps,
            defaultMaxRoundDelay,
            defaultMaxDecrements
        );
    }

    /// @notice Create a harness with a mock price feed of specific decimals
    function _createHarness(
        uint8 feedDecimals,
        int256 answer
    ) internal returns (ChainlinkOEVWrapperHarness) {
        MockAggregatorV3 mockFeed = new MockAggregatorV3(feedDecimals, answer);
        // Use address(1) for owner, feeRecipient and chainlinkOracle since we're just testing price calculation
        return
            new ChainlinkOEVWrapperHarness(
                address(mockFeed),
                address(1), // owner
                address(1), // chainlinkOracle (not used in this test)
                address(1), // feeRecipient
                5000, // liquidatorFeeBps (50%)
                3600, // maxRoundDelay
                10 // maxDecrements
            );
    }

    function testLatestRoundFallbackWhenNotSupported() public {
        // Create a mock feed that doesn't support latestRound()
        MockChainlinkOracleWithoutLatestRound mockFeed = new MockChainlinkOracleWithoutLatestRound(
                100e8,
                8
            );
        mockFeed.set(12345, 100e8, 1, 1, 12345);

        // Constructor should revert because it calls latestRound()
        vm.expectRevert(bytes("latestRound not supported"));
        new ChainlinkOEVWrapper(
            address(mockFeed),
            owner,
            chainlinkOracle,
            feeRecipient,
            defaultFeeBps,
            defaultMaxRoundDelay,
            defaultMaxDecrements
        );
    }

    function testLatestRoundReturnsDirectlyWhenSupported() public {
        // Create a normal mock feed that supports latestRound()
        MockChainlinkOracle mockFeed = new MockChainlinkOracle(100e8, 8);
        mockFeed.set(99999, 100e8, 1, 1, 99999);

        ChainlinkOEVWrapper wrapper = _deploy(address(mockFeed));

        // Call latestRound() - should use the direct call
        uint256 round = wrapper.latestRound();

        // Verify it returns the correct roundId
        assertEq(round, 99999, "Should return roundId from direct call");
    }

    function testLatestRoundMatchesLatestRoundDataRoundId() public {
        // When supported, latestRound should match the roundId from latestRoundData
        MockChainlinkOracle mockFeed = new MockChainlinkOracle(150e8, 8);
        mockFeed.set(54321, 150e8, 100, 200, 54321);

        ChainlinkOEVWrapper wrapper = _deploy(address(mockFeed));

        // Get roundId from latestRoundData
        (uint80 roundId, , , , ) = wrapper.latestRoundData();

        // Get round from latestRound
        uint256 round = wrapper.latestRound();

        // They should match
        assertEq(
            round,
            uint256(roundId),
            "latestRound should match latestRoundData roundId"
        );
    }

    function testSetLiquidatorFeeBpsUpdatesAndEmits() public {
        MockChainlinkOracle mockFeed = new MockChainlinkOracle(100e8, 8);
        ChainlinkOEVWrapper wrapper = _deploy(address(mockFeed));

        uint16 newFee = 250; // 2.5%
        vm.prank(owner);
        vm.expectEmit(false, false, false, true, address(wrapper));
        emit LiquidatorFeeBpsChanged(defaultFeeBps, newFee);
        wrapper.setLiquidatorFeeBps(newFee);

        assertEq(
            wrapper.liquidatorFeeBps(),
            newFee,
            "liquidatorFeeBps not updated"
        );
    }

    function testSetLiquidatorFeeBpsAboveMaxReverts() public {
        MockChainlinkOracle mockFeed = new MockChainlinkOracle(100e8, 8);
        ChainlinkOEVWrapper wrapper = _deploy(address(mockFeed));

        uint16 overMax = wrapper.MAX_BPS() + 1;
        vm.prank(owner);
        vm.expectRevert(
            bytes(
                "ChainlinkOEVWrapper: liquidator fee cannot be greater than MAX_BPS"
            )
        );
        wrapper.setLiquidatorFeeBps(overMax);
    }

    function testSetLiquidatorFeeBpsOnlyOwner() public {
        MockChainlinkOracle mockFeed = new MockChainlinkOracle(100e8, 8);
        ChainlinkOEVWrapper wrapper = _deploy(address(mockFeed));

        vm.prank(address(0xDEAD));
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        wrapper.setLiquidatorFeeBps(200);
    }

    function testSetMaxRoundDelayUpdatesAndEmits() public {
        MockChainlinkOracle mockFeed = new MockChainlinkOracle(100e8, 8);
        ChainlinkOEVWrapper wrapper = _deploy(address(mockFeed));

        uint256 newDelay = 600; // 10 minutes
        vm.prank(owner);
        vm.expectEmit(false, false, false, true, address(wrapper));
        emit MaxRoundDelayChanged(defaultMaxRoundDelay, newDelay);
        wrapper.setMaxRoundDelay(newDelay);

        assertEq(
            wrapper.maxRoundDelay(),
            newDelay,
            "maxRoundDelay not updated"
        );
    }

    function testSetMaxRoundDelayZeroReverts() public {
        MockChainlinkOracle mockFeed = new MockChainlinkOracle(100e8, 8);
        ChainlinkOEVWrapper wrapper = _deploy(address(mockFeed));

        vm.prank(owner);
        vm.expectRevert(
            bytes("ChainlinkOEVWrapper: max round delay cannot be zero")
        );
        wrapper.setMaxRoundDelay(0);
    }

    function testSetMaxRoundDelayOnlyOwner() public {
        MockChainlinkOracle mockFeed = new MockChainlinkOracle(100e8, 8);
        ChainlinkOEVWrapper wrapper = _deploy(address(mockFeed));

        vm.prank(address(0xDEAD));
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        wrapper.setMaxRoundDelay(600);
    }

    function testSetMaxDecrementsUpdatesAndEmits() public {
        MockChainlinkOracle mockFeed = new MockChainlinkOracle(100e8, 8);
        ChainlinkOEVWrapper wrapper = _deploy(address(mockFeed));

        uint256 newDec = 10;
        vm.prank(owner);
        vm.expectEmit(false, false, false, true, address(wrapper));
        emit MaxDecrementsChanged(defaultMaxDecrements, newDec);
        wrapper.setMaxDecrements(newDec);

        assertEq(wrapper.maxDecrements(), newDec, "maxDecrements not updated");
    }

    function testSetMaxDecrementsZeroReverts() public {
        MockChainlinkOracle mockFeed = new MockChainlinkOracle(100e8, 8);
        ChainlinkOEVWrapper wrapper = _deploy(address(mockFeed));

        vm.prank(owner);
        vm.expectRevert(
            bytes("ChainlinkOEVWrapper: max decrements cannot be zero")
        );
        wrapper.setMaxDecrements(0);
    }

    function testSetMaxDecrementsOnlyOwner() public {
        MockChainlinkOracle mockFeed = new MockChainlinkOracle(100e8, 8);
        ChainlinkOEVWrapper wrapper = _deploy(address(mockFeed));

        vm.prank(address(0xDEAD));
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        wrapper.setMaxDecrements(10);
    }

    /// @notice Test feed decimals < 18, token decimals < 18
    function testGetCollateralTokenPrice_FeedLt18_TokenLt18() public {
        // Feed: 8 decimals (standard Chainlink), Token: 6 decimals (USDC)
        // Answer: $1.00 in 8 decimals = 1e8
        ChainlinkOEVWrapperHarness _harness = _createHarness(8, 1e8);

        uint256 price = _harness.exposed_getCollateralTokenPrice(
            1e8,
            address(token6)
        );

        // Expected: 1e8 * 1e10 (scale to 18) * 1e12 (adjust for 6 decimal token) = 1e30
        assertEq(
            price,
            1e30,
            "Price should be 1e30 for $1 with 6 decimal token"
        );
    }

    /// @notice Test feed decimals < 18, token decimals = 18
    function testGetCollateralTokenPrice_FeedLt18_TokenEq18() public {
        // Feed: 8 decimals, Token: 18 decimals
        // Answer: $1.00 in 8 decimals = 1e8
        ChainlinkOEVWrapperHarness _harness = _createHarness(8, 1e8);

        uint256 price = _harness.exposed_getCollateralTokenPrice(
            1e8,
            address(token18)
        );

        // Expected: 1e8 * 1e10 (scale to 18) = 1e18
        assertEq(
            price,
            1e18,
            "Price should be 1e18 for $1 with 18 decimal token"
        );
    }

    /// @notice Test feed decimals < 18, token decimals > 18
    function testGetCollateralTokenPrice_FeedLt18_TokenGt18() public {
        // Feed: 8 decimals, Token: 24 decimals
        // Answer: $1.00 in 8 decimals = 1e8
        ChainlinkOEVWrapperHarness _harness = _createHarness(8, 1e8);

        uint256 price = _harness.exposed_getCollateralTokenPrice(
            1e8,
            address(token24)
        );

        // Expected: 1e8 * 1e10 (scale to 18) / 1e6 (adjust for 24 decimal token) = 1e12
        assertEq(
            price,
            1e12,
            "Price should be 1e12 for $1 with 24 decimal token"
        );
    }

    /// @notice Test feed decimals = 18, token decimals < 18
    function testGetCollateralTokenPrice_FeedEq18_TokenLt18() public {
        // Feed: 18 decimals, Token: 6 decimals
        // Answer: $1.00 in 18 decimals = 1e18
        ChainlinkOEVWrapperHarness _harness = _createHarness(18, 1e18);

        uint256 price = _harness.exposed_getCollateralTokenPrice(
            1e18,
            address(token6)
        );

        // Expected: 1e18 (no feed scaling) * 1e12 (adjust for 6 decimal token) = 1e30
        assertEq(
            price,
            1e30,
            "Price should be 1e30 for $1 with 6 decimal token"
        );
    }

    /// @notice Test feed decimals = 18, token decimals = 18
    function testGetCollateralTokenPrice_FeedEq18_TokenEq18() public {
        // Feed: 18 decimals, Token: 18 decimals
        // Answer: $1.00 in 18 decimals = 1e18
        ChainlinkOEVWrapperHarness _harness = _createHarness(18, 1e18);

        uint256 price = _harness.exposed_getCollateralTokenPrice(
            1e18,
            address(token18)
        );

        // Expected: 1e18 (no scaling needed)
        assertEq(
            price,
            1e18,
            "Price should be 1e18 for $1 with 18 decimal token"
        );
    }

    /// @notice Test feed decimals = 18, token decimals > 18
    function testGetCollateralTokenPrice_FeedEq18_TokenGt18() public {
        // Feed: 18 decimals, Token: 24 decimals
        // Answer: $1.00 in 18 decimals = 1e18
        ChainlinkOEVWrapperHarness _harness = _createHarness(18, 1e18);

        uint256 price = _harness.exposed_getCollateralTokenPrice(
            1e18,
            address(token24)
        );

        // Expected: 1e18 / 1e6 (adjust for 24 decimal token) = 1e12
        assertEq(
            price,
            1e12,
            "Price should be 1e12 for $1 with 24 decimal token"
        );
    }

    /// @notice Test feed decimals > 18, token decimals < 18
    function testGetCollateralTokenPrice_FeedGt18_TokenLt18() public {
        // Feed: 24 decimals, Token: 6 decimals
        // Answer: $1.00 in 24 decimals = 1e24
        ChainlinkOEVWrapperHarness _harness = _createHarness(24, 1e24);

        uint256 price = _harness.exposed_getCollateralTokenPrice(
            1e24,
            address(token6)
        );

        // Expected: 1e24 / 1e6 (scale to 18) * 1e12 (adjust for 6 decimal token) = 1e30
        assertEq(
            price,
            1e30,
            "Price should be 1e30 for $1 with 6 decimal token"
        );
    }

    /// @notice Test feed decimals > 18, token decimals = 18
    function testGetCollateralTokenPrice_FeedGt18_TokenEq18() public {
        // Feed: 24 decimals, Token: 18 decimals
        // Answer: $1.00 in 24 decimals = 1e24
        ChainlinkOEVWrapperHarness _harness = _createHarness(24, 1e24);

        uint256 price = _harness.exposed_getCollateralTokenPrice(
            1e24,
            address(token18)
        );

        // Expected: 1e24 / 1e6 (scale to 18) = 1e18
        assertEq(
            price,
            1e18,
            "Price should be 1e18 for $1 with 18 decimal token"
        );
    }

    /// @notice Test feed decimals > 18, token decimals > 18
    function testGetCollateralTokenPrice_FeedGt18_TokenGt18() public {
        // Feed: 24 decimals, Token: 24 decimals
        // Answer: $1.00 in 24 decimals = 1e24
        ChainlinkOEVWrapperHarness _harness = _createHarness(24, 1e24);

        uint256 price = _harness.exposed_getCollateralTokenPrice(
            1e24,
            address(token24)
        );

        // Expected: 1e24 / 1e6 (scale to 18) / 1e6 (adjust for 24 decimal token) = 1e12
        assertEq(
            price,
            1e12,
            "Price should be 1e12 for $1 with 24 decimal token"
        );
    }

    /// @notice Verify that feed decimals > 18 does NOT revert (regression test for underflow fix)
    function testGetCollateralTokenPrice_NoUnderflowFeedDecimals() public {
        // This test would have reverted before the fix due to underflow
        ChainlinkOEVWrapperHarness _harness = _createHarness(20, 1e20);

        // Should not revert
        uint256 price = _harness.exposed_getCollateralTokenPrice(
            1e20,
            address(token18)
        );

        // Expected: 1e20 / 1e2 = 1e18
        assertEq(price, 1e18, "Price should be correctly calculated");
    }

    /// @notice Verify that token decimals > 18 does NOT revert (regression test for underflow fix)
    function testGetCollateralTokenPrice_NoUnderflowTokenDecimals() public {
        // This test would have reverted before the fix due to underflow
        ChainlinkOEVWrapperHarness _harness = _createHarness(8, 1e8);

        // Should not revert
        uint256 price = _harness.exposed_getCollateralTokenPrice(
            1e8,
            address(token24)
        );

        // Expected: 1e8 * 1e10 / 1e6 = 1e12
        assertEq(price, 1e12, "Price should be correctly calculated");
    }

    /// @notice Fuzz test to ensure no reverts for any valid decimal combination
    /// forge-config: default.fuzz.runs = 100
    function testFuzz_GetCollateralTokenPrice_NoRevert(
        uint8 feedDecimals,
        uint8 tokenDecimals,
        uint128 answer
    ) public {
        // Bound decimals to reasonable ranges (0-30)
        feedDecimals = uint8(bound(feedDecimals, 0, 30));
        tokenDecimals = uint8(bound(tokenDecimals, 0, 30));
        // Ensure answer is positive and non-zero
        vm.assume(answer > 0);

        MockAggregatorV3 mockFeed = new MockAggregatorV3(
            feedDecimals,
            int256(uint256(answer))
        );
        ChainlinkOEVWrapperHarness _harness = new ChainlinkOEVWrapperHarness(
            address(mockFeed),
            address(1), // owner
            address(1), // chainlinkOracle
            address(1), // feeRecipient
            5000, // liquidatorFeeBps
            3600, // maxRoundDelay
            10 // maxDecrements
        );

        MockERC20Decimals token = new MockERC20Decimals(
            "Test",
            "TST",
            tokenDecimals
        );

        _harness.exposed_getCollateralTokenPrice(
            int256(uint256(answer)),
            address(token)
        );
    }

    function testCalculateCollateralSplitWithExchangeRate() public {
        uint256 exchangeRate = 2e18;
        mTokenCollateral = new MockMToken(exchangeRate);

        uint256 collateralSeized = 100e18;
        uint256 repayAmount = 50e18;
        int256 collateralAnswer = 1e8;

        // Mock the loan token price feed
        address mockLoanFeed = address(0x9999);
        _mockRegistryGetFeed(address(1), loanToken.symbol(), mockLoanFeed);
        vm.mockCall(
            mockLoanFeed,
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(
                uint80(1),
                int256(1e8),
                uint256(0),
                uint256(block.timestamp),
                uint80(1)
            )
        );
        vm.mockCall(
            mockLoanFeed,
            abi.encodeWithSignature("decimals()"),
            abi.encode(uint8(8))
        );

        (uint256 liquidatorFee, uint256 protocolFee) = harness
            .exposed_calculateCollateralSplit(
                repayAmount,
                collateralAnswer,
                collateralSeized,
                address(loanToken),
                address(mTokenCollateral),
                address(collateralToken)
            );

        uint256 expectedUnderlyingValue = (collateralSeized * exchangeRate) /
            1e18;
        assertEq(
            expectedUnderlyingValue,
            200e18,
            "Should convert 100 mTokens to 200 underlying"
        );

        uint256 surplus = expectedUnderlyingValue - repayAmount;
        uint256 expectedLiquidatorBonus = (surplus * 500) / 10000;
        uint256 expectedLiquidatorUnderlying = repayAmount +
            expectedLiquidatorBonus;
        uint256 expectedLiquidatorMTokens = (expectedLiquidatorUnderlying *
            1e18) / exchangeRate;

        assertEq(
            liquidatorFee,
            expectedLiquidatorMTokens,
            "Liquidator fee incorrect with 2x exchange rate"
        );
        assertEq(
            protocolFee,
            collateralSeized - liquidatorFee,
            "Protocol fee should be remainder"
        );

        uint256 liquidatorValueUnderlying = (liquidatorFee * exchangeRate) /
            1e18;
        uint256 protocolValueUnderlying = (protocolFee * exchangeRate) / 1e18;

        assertEq(
            liquidatorValueUnderlying + protocolValueUnderlying,
            expectedUnderlyingValue,
            "Total value should match seized collateral"
        );
    }

    function testCalculateCollateralSplitWithHighExchangeRate() public {
        uint256 exchangeRate = 5e18;
        mTokenCollateral = new MockMToken(exchangeRate);

        uint256 collateralSeized = 20e18;
        uint256 repayAmount = 50e18;
        int256 collateralAnswer = 1e8;

        // Mock the loan token price feed
        address mockLoanFeed = address(0x9999);
        _mockRegistryGetFeed(address(1), loanToken.symbol(), mockLoanFeed);
        vm.mockCall(
            mockLoanFeed,
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(
                uint80(1),
                int256(1e8),
                uint256(0),
                uint256(block.timestamp),
                uint80(1)
            )
        );
        vm.mockCall(
            mockLoanFeed,
            abi.encodeWithSignature("decimals()"),
            abi.encode(uint8(8))
        );

        (uint256 liquidatorFee, uint256 protocolFee) = harness
            .exposed_calculateCollateralSplit(
                repayAmount,
                collateralAnswer,
                collateralSeized,
                address(loanToken),
                address(mTokenCollateral),
                address(collateralToken)
            );

        uint256 expectedUnderlyingValue = (collateralSeized * exchangeRate) /
            1e18;
        assertEq(
            expectedUnderlyingValue,
            100e18,
            "Should convert 20 mTokens to 100 underlying"
        );

        uint256 surplus = expectedUnderlyingValue - repayAmount;
        uint256 expectedLiquidatorBonus = (surplus * 500) / 10000;
        uint256 expectedLiquidatorUnderlying = repayAmount +
            expectedLiquidatorBonus;
        uint256 expectedLiquidatorMTokens = (expectedLiquidatorUnderlying *
            1e18) / exchangeRate;

        assertApproxEqAbs(
            liquidatorFee,
            expectedLiquidatorMTokens,
            1,
            "Liquidator fee incorrect with 5x exchange rate"
        );
        assertEq(
            protocolFee,
            collateralSeized - liquidatorFee,
            "Protocol fee should be remainder"
        );
    }

    function testCalculateCollateralSplitExampleFromDescription() public {
        uint256 exchangeRate = 2e18;
        mTokenCollateral = new MockMToken(exchangeRate);

        uint256 collateralSeized = 100e18;
        uint256 repayAmount = 50e18;
        int256 collateralAnswer = 1e8;

        // Mock the loan token price feed
        address mockLoanFeed = address(0x9999);
        _mockRegistryGetFeed(address(1), loanToken.symbol(), mockLoanFeed);
        vm.mockCall(
            mockLoanFeed,
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(
                uint80(1),
                int256(1e8),
                uint256(0),
                uint256(block.timestamp),
                uint80(1)
            )
        );
        vm.mockCall(
            mockLoanFeed,
            abi.encodeWithSignature("decimals()"),
            abi.encode(uint8(8))
        );

        (uint256 liquidatorFee, uint256 protocolFee) = harness
            .exposed_calculateCollateralSplit(
                repayAmount,
                collateralAnswer,
                collateralSeized,
                address(loanToken),
                address(mTokenCollateral),
                address(collateralToken)
            );

        uint256 underlyingValue = (collateralSeized * exchangeRate) / 1e18;
        assertEq(underlyingValue, 200e18, "100 mTokens * 2 = 200 underlying");

        uint256 surplus = underlyingValue - repayAmount;
        assertEq(
            surplus,
            150e18,
            "$200 collateral - $50 repayment = $150 surplus"
        );

        uint256 liquidatorBonus = (surplus * 500) / 10000;
        assertEq(liquidatorBonus, 7.5e18, "5% of $150 = $7.50");

        uint256 liquidatorValueUnderlying = repayAmount + liquidatorBonus;
        assertEq(liquidatorValueUnderlying, 57.5e18, "$50 + $7.50 = $57.50");

        uint256 expectedLiquidatorMTokens = (liquidatorValueUnderlying * 1e18) /
            exchangeRate;
        assertEq(
            expectedLiquidatorMTokens,
            28.75e18,
            "$57.50 / 2 per mToken = 28.75 mTokens"
        );

        assertEq(
            liquidatorFee,
            expectedLiquidatorMTokens,
            "Liquidator should receive 28.75 mTokens"
        );
        assertEq(
            protocolFee,
            71.25e18,
            "Protocol should receive 100 - 28.75 = 71.25 mTokens"
        );

        uint256 protocolValueUnderlying = (protocolFee * exchangeRate) / 1e18;
        assertEq(
            protocolValueUnderlying,
            142.5e18,
            "71.25 mTokens * 2 = $142.50"
        );
    }

    /// @notice Test that fresh loan prices prevent stale price exploitation
    /// @dev This test verifies the fix for the price staleness vulnerability where:
    ///      - Both collateral and loan assets could have OEV wrappers
    ///      - Liquidator updates collateral price (fresh) but loan price is stale
    function testFreshLoanPricePreventsStaleExploit() public {
        uint256 exchangeRate = 1e18;
        mTokenCollateral = new MockMToken(exchangeRate);

        uint256 repayAmount = 100e18;
        uint256 collateralSeized = 100e18;
        int256 collateralAnswer = 85e8;

        // Scenario: Both assets dropped in price from $100 to lower values
        // - Collateral: $100 -> $85 (fresh, updated by liquidator)
        // - Loan: $100 -> $80 (should be fetched fresh via our fix)

        address mockLoanFeed = address(0x9999);
        _mockRegistryGetFeed(address(1), loanToken.symbol(), mockLoanFeed);

        int256 freshLoanPrice = 80e8;
        vm.mockCall(
            mockLoanFeed,
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(
                uint80(2),
                freshLoanPrice,
                uint256(0),
                uint256(block.timestamp),
                uint80(2)
            )
        );
        vm.mockCall(
            mockLoanFeed,
            abi.encodeWithSignature("decimals()"),
            abi.encode(uint8(8))
        );

        (uint256 liquidatorFee, uint256 protocolFee) = harness
            .exposed_calculateCollateralSplit(
                repayAmount,
                collateralAnswer,
                collateralSeized,
                address(loanToken),
                address(mTokenCollateral),
                address(collateralToken)
            );

        uint256 repayUSD = (100e18 * 80e18) / 1e18;
        uint256 collateralUSD = (100e18 * 85e18) / 1e18;
        uint256 surplus = collateralUSD - repayUSD;
        assertEq(surplus, 500e18, "Surplus should be $500");

        uint256 liquidatorBonus = (surplus * 500) / 10000;
        uint256 expectedLiquidatorUSD = repayUSD + liquidatorBonus;
        uint256 expectedLiquidatorTokens = (expectedLiquidatorUSD * 1e18) /
            85e18;
        uint256 expectedProtocolTokens = collateralSeized -
            expectedLiquidatorTokens;
        assertApproxEqAbs(
            liquidatorFee,
            expectedLiquidatorTokens,
            1e15,
            "Liquidator should receive ~94.41 tokens (repayment + 5% bonus)"
        );

        assertApproxEqAbs(
            protocolFee,
            expectedProtocolTokens,
            1e15,
            "Protocol should receive ~5.58 tokens (95% of surplus)"
        );

        assertGt(protocolFee, 0, "Protocol fee must be > 0");

        assertLt(
            liquidatorFee,
            collateralSeized,
            "Liquidator should not receive 100% of collateral"
        );
    }

    function testRecoverETHSucceeds() public {
        MockChainlinkOracle mockFeed = new MockChainlinkOracle(100e8, 8);
        ChainlinkOEVWrapper wrapper = _deploy(address(mockFeed));

        // Fund the wrapper with some ETH
        uint256 ethAmount = 1 ether;
        vm.deal(address(wrapper), ethAmount);
        assertEq(
            address(wrapper).balance,
            ethAmount,
            "Wrapper should have ETH"
        );

        // Create recipient and record initial balance
        address payable recipient = payable(address(0xBEEF));
        uint256 recipientBalanceBefore = recipient.balance;

        // Withdraw ETH as owner
        vm.prank(owner);
        wrapper.recoverETH(recipient);

        // Verify ETH was transferred
        assertEq(
            address(wrapper).balance,
            0,
            "Wrapper should have 0 ETH after withdrawal"
        );
        assertEq(
            recipient.balance,
            recipientBalanceBefore + ethAmount,
            "Recipient should have received ETH"
        );
    }

    function testRecoverETHOnlyOwner() public {
        MockChainlinkOracle mockFeed = new MockChainlinkOracle(100e8, 8);
        ChainlinkOEVWrapper wrapper = _deploy(address(mockFeed));

        // Fund the wrapper with some ETH
        vm.deal(address(wrapper), 1 ether);

        address payable recipient = payable(address(0xBEEF));

        // Try to withdraw as non-owner
        vm.prank(address(0xDEAD));
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        wrapper.recoverETH(recipient);
    }

    function testRecoverERC20Succeeds() public {
        MockChainlinkOracle mockFeed = new MockChainlinkOracle(100e8, 8);
        ChainlinkOEVWrapper wrapper = _deploy(address(mockFeed));

        // Mint some tokens to the wrapper
        uint256 tokenAmount = 1000e18;
        token18.mint(address(wrapper), tokenAmount);
        assertEq(
            token18.balanceOf(address(wrapper)),
            tokenAmount,
            "Wrapper should have tokens"
        );

        // Create recipient
        address recipient = address(0xBEEF);
        uint256 recipientBalanceBefore = token18.balanceOf(recipient);

        // Withdraw tokens as owner
        vm.prank(owner);
        wrapper.recoverERC20(address(token18), recipient, tokenAmount);

        // Verify tokens were transferred
        assertEq(
            token18.balanceOf(address(wrapper)),
            0,
            "Wrapper should have 0 tokens after withdrawal"
        );
        assertEq(
            token18.balanceOf(recipient),
            recipientBalanceBefore + tokenAmount,
            "Recipient should have received tokens"
        );
    }

    function testRecoverERC20OnlyOwner() public {
        MockChainlinkOracle mockFeed = new MockChainlinkOracle(100e8, 8);
        ChainlinkOEVWrapper wrapper = _deploy(address(mockFeed));

        uint256 tokenAmount = 1000e18;

        // Mint some tokens to the wrapper
        token18.mint(address(wrapper), tokenAmount);

        address recipient = address(0xBEEF);

        // Try to withdraw as non-owner
        vm.prank(address(0xDEAD));
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        wrapper.recoverERC20(address(token18), recipient, tokenAmount);
    }

    function testLoanPriceValidationRevertsOnZeroAnswer() public {
        uint256 exchangeRate = 1e18;
        mTokenCollateral = new MockMToken(exchangeRate);

        address mockLoanFeed = address(0x9999);
        _mockRegistryGetFeed(address(1), loanToken.symbol(), mockLoanFeed);

        // Mock loan feed with zero answer
        vm.mockCall(
            mockLoanFeed,
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(
                uint80(1), // roundId
                int256(0), // answer = 0 (invalid)
                uint256(0), // startedAt
                uint256(block.timestamp), // updatedAt
                uint80(1) // answeredInRound
            )
        );
        vm.mockCall(
            mockLoanFeed,
            abi.encodeWithSignature("decimals()"),
            abi.encode(uint8(8))
        );

        vm.expectRevert(bytes("Chainlink price cannot be lower or equal to 0"));
        harness.exposed_calculateCollateralSplit(
            100e18, // repayAmount
            1e8, // collateralAnswer
            100e18, // collateralSeized
            address(loanToken),
            address(mTokenCollateral),
            address(collateralToken)
        );
    }

    function testLoanPriceValidationRevertsOnNegativeAnswer() public {
        uint256 exchangeRate = 1e18;
        mTokenCollateral = new MockMToken(exchangeRate);

        address mockLoanFeed = address(0x9999);
        _mockRegistryGetFeed(address(1), loanToken.symbol(), mockLoanFeed);

        // Mock loan feed with negative answer
        vm.mockCall(
            mockLoanFeed,
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(
                uint80(1), // roundId
                int256(-1e8), // answer = -1 (invalid)
                uint256(0), // startedAt
                uint256(block.timestamp), // updatedAt
                uint80(1) // answeredInRound
            )
        );
        vm.mockCall(
            mockLoanFeed,
            abi.encodeWithSignature("decimals()"),
            abi.encode(uint8(8))
        );

        vm.expectRevert(bytes("Chainlink price cannot be lower or equal to 0"));
        harness.exposed_calculateCollateralSplit(
            100e18,
            1e8,
            100e18,
            address(loanToken),
            address(mTokenCollateral),
            address(collateralToken)
        );
    }

    function testLoanPriceValidationRevertsOnIncompleteRound() public {
        uint256 exchangeRate = 1e18;
        mTokenCollateral = new MockMToken(exchangeRate);

        address mockLoanFeed = address(0x9999);
        _mockRegistryGetFeed(address(1), loanToken.symbol(), mockLoanFeed);

        // Mock loan feed with updatedAt = 0 (incomplete round)
        vm.mockCall(
            mockLoanFeed,
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(
                uint80(1), // roundId
                int256(1e8), // answer
                uint256(0), // startedAt
                uint256(0), // updatedAt = 0 (invalid - incomplete)
                uint80(1) // answeredInRound
            )
        );
        vm.mockCall(
            mockLoanFeed,
            abi.encodeWithSignature("decimals()"),
            abi.encode(uint8(8))
        );

        vm.expectRevert(bytes("Round is in incompleted state"));
        harness.exposed_calculateCollateralSplit(
            100e18,
            1e8,
            100e18,
            address(loanToken),
            address(mTokenCollateral),
            address(collateralToken)
        );
    }

    function testLoanPriceValidationRevertsOnStalePrice() public {
        uint256 exchangeRate = 1e18;
        mTokenCollateral = new MockMToken(exchangeRate);

        address mockLoanFeed = address(0x9999);
        _mockRegistryGetFeed(address(1), loanToken.symbol(), mockLoanFeed);

        // Mock loan feed with answeredInRound < roundId (stale price)
        vm.mockCall(
            mockLoanFeed,
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(
                uint80(5), // roundId = 5
                int256(1e8), // answer
                uint256(0), // startedAt
                uint256(block.timestamp), // updatedAt
                uint80(3) // answeredInRound = 3 (< roundId, stale)
            )
        );
        vm.mockCall(
            mockLoanFeed,
            abi.encodeWithSignature("decimals()"),
            abi.encode(uint8(8))
        );

        vm.expectRevert(bytes("Stale price"));
        harness.exposed_calculateCollateralSplit(
            100e18,
            1e8,
            100e18,
            address(loanToken),
            address(mTokenCollateral),
            address(collateralToken)
        );
    }

    function testLoanPriceValidationSucceedsWithValidData() public {
        uint256 exchangeRate = 1e18;
        mTokenCollateral = new MockMToken(exchangeRate);

        address mockLoanFeed = address(0x9999);
        _mockRegistryGetFeed(address(1), loanToken.symbol(), mockLoanFeed);

        // Mock loan feed with valid data
        vm.mockCall(
            mockLoanFeed,
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(
                uint80(5), // roundId
                int256(1e8), // answer > 0 (valid)
                uint256(0), // startedAt
                uint256(block.timestamp), // updatedAt != 0 (valid)
                uint80(5) // answeredInRound >= roundId (valid)
            )
        );
        vm.mockCall(
            mockLoanFeed,
            abi.encodeWithSignature("decimals()"),
            abi.encode(uint8(8))
        );

        // Should not revert with valid data
        (uint256 liquidatorFee, uint256 protocolFee) = harness
            .exposed_calculateCollateralSplit(
                50e18, // repayAmount
                1e8, // collateralAnswer ($1)
                100e18, // collateralSeized
                address(loanToken),
                address(mTokenCollateral),
                address(collateralToken)
            );

        // Verify calculation succeeded
        assertGt(liquidatorFee, 0, "Liquidator fee should be > 0");
        assertEq(
            liquidatorFee + protocolFee,
            100e18,
            "Total should equal collateralSeized"
        );
    }

    /// @notice When the registry entry under the loan-token symbol is itself an
    ///         OEV wrapper (exposes priceFeed() pointing at an inner raw
    ///         aggregator), `_getLoanTokenPrice` must single-hop-dereference to
    ///         the inner aggregator and read the fresh price from it. Regression
    ///         coverage for the bounty bug: without `_resolveRawFeed`, the outer
    ///         wrapper's own (potentially delayed) price would be used, skewing
    ///         the liquidator/protocol fee split.
    /// @dev Uses vm.mockCall on address(1) (the chainlinkOracle registry slot
    ///      in the harness) because MockChainlinkOracle is a feed mock that has
    ///      no getFeed(string) registry method.
    function testLoanPriceDerefsPriceFeedWhenRegistryEntryIsOEVWrapper()
        public
    {
        // Inner (raw) feed: the "fresh" price that the post-fix code must read.
        MockChainlinkOracle rawLoanFeed = new MockChainlinkOracle(2_000e8, 8);
        rawLoanFeed.set(1, 2_000e8, 1, block.timestamp, 1);

        // Outer OEV wrapper registered in ChainlinkOracle, with a stale/wrong
        // price on its own latestRoundData. The inner priceFeed() is the raw
        // feed above.  Current code reads the outer directly; post-fix code
        // dereferences to the inner.
        MockOEVWrapperFeed outerWrapper = new MockOEVWrapperFeed(
            address(rawLoanFeed),
            8,
            "MOCK_WRAPPER",
            1
        );
        outerWrapper.setLatestRound(1, 1_500e8, 1, block.timestamp, 1);

        // Stub the registry (address(1)) to return the outer wrapper for the
        // loan symbol. The harness was constructed with chainlinkOracle =
        // address(1).
        string memory loanSymbol = loanToken.symbol();
        vm.mockCall(
            address(1),
            abi.encodeWithSignature("getFeed(string)", loanSymbol),
            abi.encode(address(outerWrapper))
        );

        uint256 priceScaled = harness.exposed_getLoanTokenPrice(
            EIP20Interface(address(loanToken))
        );

        // Post-fix: _resolveRawFeed detects priceFeed() on the outer wrapper,
        // dereferences to rawLoanFeed, and returns its price: 2_000e18.
        // Pre-fix: reads outer latestRoundData() directly → 1_500e18.
        // This assertion FAILS today (pre-Task 4).
        assertEq(priceScaled, 2_000e18, "raw feed price not used");
    }

    /// @notice Regression: when the registry returns a raw aggregator (via
    ///         the DRY helper which stubs priceFeed() to address(0)),
    ///         _resolveRawFeed's zero-inner defensive fallback must fire
    ///         and _getLoanTokenPrice must read the raw feed directly.
    ///         (The genuine try/catch branch is covered by
    ///         testLoanPriceReadsRawFeedWhenRegistryEntryLacksPriceFeedSelector.)
    function testLoanPriceReadsRawFeedWhenRegistryEntryIsRaw() public {
        // Plain raw aggregator used as the registry's target for the loan symbol.
        MockChainlinkOracle rawLoanFeed = new MockChainlinkOracle(2_000e8, 8);
        rawLoanFeed.set(1, 2_000e8, 1, block.timestamp, 1);

        string memory loanSymbol = loanToken.symbol();
        // Use the DRY helper — it stubs getFeed(symbol) on the registry AND
        // stubs priceFeed() on the feed address to return address(0). The
        // address(0) stub activates _resolveRawFeed's defensive fallback branch
        // (not the try/catch path), but the observable behavior is identical:
        // _getLoanTokenPrice reads from rawLoanFeed directly.
        _mockRegistryGetFeed(address(1), loanSymbol, address(rawLoanFeed));

        uint256 priceScaled = harness.exposed_getLoanTokenPrice(
            EIP20Interface(address(loanToken))
        );

        // 2_000e8 feed @ 8 decimals → 2_000e18 after scaling to 18.
        // loanToken has 18 decimals so no further adjustment.
        assertEq(priceScaled, 2_000e18, "raw feed price not used");
    }

    /// @notice Regression: when the registry returns a contract that truly has
    ///         no priceFeed() selector (not mocked to return zero), the
    ///         try/catch in _resolveRawFeed must catch the revert and fall
    ///         through to return the input unchanged.
    function testLoanPriceReadsRawFeedWhenRegistryEntryLacksPriceFeedSelector()
        public
    {
        MockChainlinkOracle rawLoanFeed = new MockChainlinkOracle(2_500e8, 8);
        rawLoanFeed.set(1, 2_500e8, 1, block.timestamp, 1);

        string memory loanSymbol = loanToken.symbol();
        // Mock ONLY getFeed(symbol). Do NOT mock priceFeed() on rawLoanFeed —
        // that selector will hit the MockChainlinkOracle contract, which has
        // no such function, causing a revert that _resolveRawFeed's catch
        // clause must swallow.
        vm.mockCall(
            address(1),
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

    /// @notice Defense-in-depth: if the registry returns an address with no
    ///         contract code (e.g., the registry was misconfigured to point
    ///         at an EOA), `_resolveRawFeed`'s try/catch falls through and
    ///         the wrapper would otherwise call `latestRoundData()` on an EOA
    ///         (which silently returns empty data). The new code-length check
    ///         must trip first with a clear message.
    function testLoanPriceRevertsWhenResolvedFeedHasNoCode() public {
        // EOA with no code. Do NOT mock priceFeed() on it — that would make
        // _resolveRawFeed return a different (mock-etched) address. Leaving
        // it unmocked causes _resolveRawFeed's try/catch to fall through and
        // return the EOA itself.
        address eoaFeed = address(0xDEAD);

        string memory loanSymbol = loanToken.symbol();
        vm.mockCall(
            address(1),
            abi.encodeWithSignature("getFeed(string)", loanSymbol),
            abi.encode(eoaFeed)
        );

        // Sanity: confirm no code at the EOA address before invoking.
        assertEq(eoaFeed.code.length, 0, "EOA must have no code");

        vm.expectRevert("ChainlinkOEVWrapper: loan feed has no code");
        harness.exposed_getLoanTokenPrice(EIP20Interface(address(loanToken)));
    }

    function testUpdatePriceEarlyAndLiquidateRevertsOnLoanTokenTransferFailure()
        public
    {
        MockChainlinkOracle mockFeed = new MockChainlinkOracle(100e8, 8);
        mockFeed.set(1, 100e8, block.timestamp, block.timestamp, 1);

        address mockChainlinkOracleAddr = address(0x1111);

        ChainlinkOEVWrapper wrapper = new ChainlinkOEVWrapper(
            address(mockFeed),
            owner,
            mockChainlinkOracleAddr,
            feeRecipient,
            defaultFeeBps,
            defaultMaxRoundDelay,
            defaultMaxDecrements
        );

        address mockMTokenCollateral = address(0x2222);
        address mockMTokenLoan = address(0x3333);

        address mockUnderlyingCollateral = address(0x4444);
        address mockUnderlyingLoan = address(0x5555);

        vm.mockCall(
            mockMTokenCollateral,
            abi.encodeWithSignature("underlying()"),
            abi.encode(mockUnderlyingCollateral)
        );

        vm.mockCall(
            mockMTokenLoan,
            abi.encodeWithSignature("underlying()"),
            abi.encode(mockUnderlyingLoan)
        );

        vm.mockCall(
            mockUnderlyingCollateral,
            abi.encodeWithSignature("symbol()"),
            abi.encode("COLL")
        );

        vm.mockCall(
            mockChainlinkOracleAddr,
            abi.encodeWithSignature("getFeed(string)", "COLL"),
            abi.encode(address(wrapper))
        );

        vm.mockCall(
            mockUnderlyingLoan,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                address(this),
                address(wrapper),
                100e18
            ),
            abi.encode(false)
        );

        vm.expectRevert(bytes("SafeERC20: ERC20 operation did not succeed"));
        wrapper.updatePriceEarlyAndLiquidate(
            address(0xBEEF), // borrower
            100e18, // repayAmount
            mockMTokenCollateral,
            mockMTokenLoan
        );
    }

    /// @notice Defensive fallback: registry returns an OEV wrapper whose
    ///         priceFeed() resolves to address(0). _resolveRawFeed must
    ///         ignore the zero inner and return the outer registry feed, so
    ///         _getLoanTokenPrice reads the outer's own round data.
    function testLoanPriceFallsBackToOuterWhenInnerIsZero() public {
        MockOEVWrapperFeed outerWrapper = new MockOEVWrapperFeed(
            address(0),
            8,
            "MOCK_WRAPPER_ZERO_INNER",
            1
        );
        outerWrapper.setLatestRound(1, 1_500e8, 1, block.timestamp, 1);

        string memory loanSymbol = loanToken.symbol();
        // Only mock getFeed — the MockOEVWrapperFeed exposes its own
        // priceFeed() state var (returns address(0)), which is the scenario
        // under test.
        vm.mockCall(
            address(1),
            abi.encodeWithSignature("getFeed(string)", loanSymbol),
            abi.encode(address(outerWrapper))
        );

        uint256 priceScaled = harness.exposed_getLoanTokenPrice(
            EIP20Interface(address(loanToken))
        );

        // outer's price 1_500e8 @ 8 decimals → 1_500e18
        assertEq(priceScaled, 1_500e18, "defensive fallback not taken");
    }

    /// @notice Single-hop deref: _resolveRawFeed must dereference exactly once.
    ///         If outer.priceFeed() returns middle (which itself is a wrapper
    ///         with its own priceFeed() pointing at innerInner), we must stop
    ///         at middle and read middle's round data — not recurse to
    ///         innerInner.
    function testDerefIsSingleHop() public {
        // innerInner — should NEVER be reached.
        MockChainlinkOracle innerInner = new MockChainlinkOracle(9_999e8, 8);
        innerInner.set(1, 9_999e8, 1, block.timestamp, 1);

        // middle — the target of the single hop. Its OWN round data is what
        // we expect to read.
        MockOEVWrapperFeed middleWrapper = new MockOEVWrapperFeed(
            address(innerInner),
            8,
            "MIDDLE",
            1
        );
        middleWrapper.setLatestRound(1, 4_242e8, 1, block.timestamp, 1);

        // outer — registered in the registry. priceFeed() returns middle.
        MockOEVWrapperFeed outerWrapper = new MockOEVWrapperFeed(
            address(middleWrapper),
            8,
            "OUTER",
            1
        );
        outerWrapper.setLatestRound(1, 1e8, 1, block.timestamp, 1);

        string memory loanSymbol = loanToken.symbol();
        vm.mockCall(
            address(1),
            abi.encodeWithSignature("getFeed(string)", loanSymbol),
            abi.encode(address(outerWrapper))
        );

        uint256 priceScaled = harness.exposed_getLoanTokenPrice(
            EIP20Interface(address(loanToken))
        );

        // Must be middle's 4_242e18, NOT innerInner's 9_999e18 and NOT outer's 1e18.
        assertEq(priceScaled, 4_242e18, "deref took more than one hop");
    }

    /// @notice C4 #289 regression: a dust liquidation prices at the fresh round only during its own nested liquidation, then re-locks — never globally unlocking it for follow-on callers.
    function testDustLiquidationDoesNotGloballyUnlockFreshRound() public {
        vm.warp(1_000);

        // Collateral feed: round 1 = $100 (old), round 2 = $80 (fresh).
        MockRoundFeed collateralFeed = new MockRoundFeed(8);
        collateralFeed.setRound(1, 100e8, 900, 1);
        collateralFeed.setLatestRound(1);

        // Loan feed: $1, stable.
        MockRoundFeed loanFeed = new MockRoundFeed(8);
        loanFeed.setRound(1, 1e8, 900, 1);
        loanFeed.setLatestRound(1);

        address mockOracleAddr = address(0x1111);
        ChainlinkOEVWrapper wrapper = new ChainlinkOEVWrapper(
            address(collateralFeed),
            owner,
            mockOracleAddr,
            feeRecipient,
            defaultFeeBps,
            defaultMaxRoundDelay,
            defaultMaxDecrements
        );

        assertEq(wrapper.cachedRoundId(), 1, "constructor caches round 1");

        // A fresh Chainlink round arrives inside maxRoundDelay.
        collateralFeed.setRound(2, 80e8, block.timestamp, 2);
        collateralFeed.setLatestRound(2);

        // Before any OEV liquidation, the wrapper hides the fresh round.
        (, int256 delayedBefore, , , ) = wrapper.latestRoundData();
        assertEq(
            delayedBefore,
            100e8,
            "fresh round must be hidden pre-liquidation"
        );

        // Underlying tokens + mock markets.
        MockERC20Decimals underlyingCollateral = new MockERC20Decimals(
            "Collateral",
            "COLL",
            18
        );
        MockERC20Decimals underlyingLoan = new MockERC20Decimals(
            "Loan",
            "LOAN",
            18
        );
        MockLiquidationMToken collateralMarket = new MockLiquidationMToken(
            address(underlyingCollateral),
            1e18
        );
        MockLiquidationMToken mTokenLoan = new MockLiquidationMToken(
            address(underlyingLoan),
            1e18
        );
        mTokenLoan.setCollateralToSeize(address(collateralMarket), 2e6);
        // Record the price the wrapper exposes DURING its own liquidation.
        mTokenLoan.setPriceObserver(address(wrapper));

        vm.mockCall(
            mockOracleAddr,
            abi.encodeWithSignature("getFeed(string)", "COLL"),
            abi.encode(address(wrapper))
        );
        vm.mockCall(
            mockOracleAddr,
            abi.encodeWithSignature("getFeed(string)", "LOAN"),
            abi.encode(address(loanFeed))
        );

        address attacker = address(0xA11CE);
        underlyingLoan.mint(attacker, 1e6);
        vm.startPrank(attacker);
        underlyingLoan.approve(address(wrapper), 1e6);
        wrapper.updatePriceEarlyAndLiquidate(
            address(0xB0B),
            1e6,
            address(collateralMarket),
            address(mTokenLoan)
        );
        vm.stopPrank();

        // The legitimate liquidation executed at the FRESH price...
        assertEq(
            mTokenLoan.observedPrice(),
            80e8,
            "nested liquidation must see the fresh round"
        );
        assertGt(
            collateralMarket.balanceOf(attacker),
            0,
            "liquidator received its share"
        );
        assertGt(
            collateralMarket.balanceOf(feeRecipient),
            0,
            "protocol received the OEV split"
        );

        // ...but THE FIX: the unlock did not persist globally.
        assertEq(
            wrapper.cachedRoundId(),
            1,
            "cachedRoundId must NOT advance globally"
        );
        (, int256 delayedAfter, , , ) = wrapper.latestRoundData();
        assertEq(
            delayedAfter,
            100e8,
            "fresh round must be re-locked for ordinary consumers"
        );
    }
}

/// @notice Mock price feed with configurable decimals for testing
contract MockAggregatorV3 is AggregatorV3Interface {
    uint8 private _decimals;
    int256 private _answer;
    uint80 private _roundId;

    constructor(uint8 decimals_, int256 answer_) {
        _decimals = decimals_;
        _answer = answer_;
        _roundId = 1;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external pure override returns (string memory) {
        return "Mock Aggregator";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(
        uint80
    )
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (_roundId, _answer, block.timestamp, block.timestamp, _roundId);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (_roundId, _answer, block.timestamp, block.timestamp, _roundId);
    }

    function latestRound() external view override returns (uint256) {
        return _roundId;
    }
}

/// @notice Test harness to expose internal _getCollateralTokenPrice function
contract ChainlinkOEVWrapperHarness is ChainlinkOEVWrapper {
    constructor(
        address _priceFeed,
        address _owner,
        address _chainlinkOracle,
        address _feeRecipient,
        uint16 _liquidatorFeeBps,
        uint256 _maxRoundDelay,
        uint256 _maxDecrements
    )
        ChainlinkOEVWrapper(
            _priceFeed,
            _owner,
            _chainlinkOracle,
            _feeRecipient,
            _liquidatorFeeBps,
            _maxRoundDelay,
            _maxDecrements
        )
    {}

    /// @notice Expose the internal _getCollateralTokenPrice for testing
    function exposed_getCollateralTokenPrice(
        int256 collateralAnswer,
        address underlyingCollateral
    ) external view returns (uint256) {
        return
            _getCollateralTokenPrice(
                collateralAnswer,
                EIP20Interface(underlyingCollateral)
            );
    }

    /// @notice Expose the internal _getLoanTokenPrice for testing
    function exposed_getLoanTokenPrice(
        EIP20Interface underlyingLoan
    ) external view returns (uint256) {
        return _getLoanTokenPrice(underlyingLoan);
    }

    /// @notice Expose the internal _resolveRawFeed for testing
    function exposed_resolveRawFeed(
        AggregatorV3Interface registryFeed
    ) external view returns (AggregatorV3Interface) {
        return _resolveRawFeed(registryFeed);
    }

    /// @notice Expose the internal _calculateCollateralSplit for testing
    function exposed_calculateCollateralSplit(
        uint256 repayAmount,
        int256 collateralAnswer,
        uint256 collateralSeized,
        address underlyingLoan,
        address mTokenCollateral,
        address underlyingCollateral
    ) external view returns (uint256 liquidatorFee, uint256 protocolFee) {
        return
            _calculateCollateralSplit(
                repayAmount,
                collateralAnswer,
                collateralSeized,
                EIP20Interface(underlyingLoan),
                mTokenCollateral,
                EIP20Interface(underlyingCollateral)
            );
    }
}

/// @notice Mock MToken for testing exchange rate scenarios
contract MockMToken {
    uint256 private _exchangeRate;

    constructor(uint256 exchangeRate_) {
        _exchangeRate = exchangeRate_;
    }

    function exchangeRateStored() external view returns (uint256) {
        return _exchangeRate;
    }
}

/// @notice Chainlink aggregator mock with independent per-round data (unlike MockChainlinkOracle's single answer).
contract MockRoundFeed is AggregatorV3Interface {
    uint8 private immutable _decimals;
    uint80 private _latestRoundId;

    struct RoundData {
        int256 answer;
        uint256 updatedAt;
        uint80 answeredInRound;
        bool set;
    }

    mapping(uint80 => RoundData) private _rounds;

    constructor(uint8 decimals_) {
        _decimals = decimals_;
    }

    function setRound(
        uint80 roundId,
        int256 answer,
        uint256 updatedAt,
        uint80 answeredInRound
    ) external {
        _rounds[roundId] = RoundData(answer, updatedAt, answeredInRound, true);
    }

    function setLatestRound(uint80 roundId) external {
        _latestRoundId = roundId;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external pure override returns (string memory) {
        return "MockRoundFeed";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(
        uint80 roundId
    )
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        RoundData memory r = _rounds[roundId];
        // Revert on unset rounds so the wrapper's try/catch decrement works.
        require(r.set, "MockRoundFeed: round not set");
        return (roundId, r.answer, r.updatedAt, r.updatedAt, r.answeredInRound);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        RoundData memory r = _rounds[_latestRoundId];
        return (
            _latestRoundId,
            r.answer,
            r.updatedAt,
            r.updatedAt,
            r.answeredInRound
        );
    }

    function latestRound() external view override returns (uint256) {
        return _latestRoundId;
    }
}

/// @notice mToken mock whose liquidateBorrow() pulls the repay and credits configured collateral; also acts as the collateral market.
contract MockLiquidationMToken {
    address public underlying;
    uint256 private _exchangeRate;
    mapping(address => uint256) public balanceOf;

    address private _collateralMToken;
    uint256 private _collateralToSeize;

    // Optional: record the price exposed by a source oracle during liquidation.
    address private _priceObserver;
    int256 public observedPrice;

    constructor(address underlying_, uint256 exchangeRate_) {
        underlying = underlying_;
        _exchangeRate = exchangeRate_;
    }

    function exchangeRateStored() external view returns (uint256) {
        return _exchangeRate;
    }

    function setCollateralToSeize(
        address collateralMToken_,
        uint256 amount_
    ) external {
        _collateralMToken = collateralMToken_;
        _collateralToSeize = amount_;
    }

    function setPriceObserver(address source) external {
        _priceObserver = source;
    }

    /// @notice Called on the LOAN market by the wrapper.
    function liquidateBorrow(
        address,
        uint256 repayAmount,
        address mTokenCollateral
    ) external returns (uint256) {
        if (_priceObserver != address(0)) {
            (, observedPrice, , , ) = AggregatorV3Interface(_priceObserver)
                .latestRoundData();
        }
        // Pull the repaid loan underlying from the caller (the wrapper).
        IERC20(underlying).transferFrom(msg.sender, address(this), repayAmount);
        // Seize: credit collateral mTokens to the caller (the wrapper).
        MockLiquidationMToken(mTokenCollateral).creditMTokens(
            msg.sender,
            _collateralToSeize
        );
        return 0;
    }

    function creditMTokens(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}
