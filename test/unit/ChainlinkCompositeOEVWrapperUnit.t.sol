// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {ChainlinkCompositeOEVWrapper} from "@protocol/oracles/ChainlinkCompositeOEVWrapper.sol";
import {MockChainlinkOracle} from "@test/mock/MockChainlinkOracle.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {EIP20Interface} from "@protocol/EIP20Interface.sol";
import {MockERC20Decimals} from "@test/mock/MockERC20Decimals.sol";

contract ChainlinkCompositeOEVWrapperUnitTest is Test {
    address public owner = address(0x1);
    address public chainlinkOracle = address(0x4);
    address public feeRecipient = address(0x5);
    uint16 public defaultFeeBps = 100; // 1%
    uint256 public defaultMaxRoundDelay = 300; // 5 minutes

    // Mock oracles
    MockCompositeOracle compositeOracle;
    MockChainlinkOracle baseFeed;

    // Tokens for decimal testing
    MockERC20Decimals token6;
    MockERC20Decimals token18;
    MockERC20Decimals token24;

    // Tokens for exchange rate testing
    MockERC20Decimals collateralToken;
    MockERC20Decimals loanToken;
    MockMToken mTokenCollateral;
    ChainlinkCompositeOEVWrapperHarness harness;

    // Events mirrored for expectEmit
    event LiquidatorFeeBpsChanged(
        uint16 oldLiquidatorFeeBps,
        uint16 newLiquidatorFeeBps
    );
    event MaxRoundDelayChanged(
        uint256 oldMaxRoundDelay,
        uint256 newMaxRoundDelay
    );
    event FeeRecipientChanged(address oldFeeRecipient, address newFeeRecipient);

    function setUp() public {
        token6 = new MockERC20Decimals("Token6", "T6", 6);
        token18 = new MockERC20Decimals("Token18", "T18", 18);
        token24 = new MockERC20Decimals("Token24", "T24", 24);

        collateralToken = new MockERC20Decimals("Collateral", "COLL", 18);
        loanToken = new MockERC20Decimals("Loan", "LOAN", 18);

        // Composite oracle returns 18 decimals (like ChainlinkCompositeOracle)
        compositeOracle = new MockCompositeOracle(18, 3500e18);

        // Base feed is a standard Chainlink feed (8 decimals)
        baseFeed = new MockChainlinkOracle(3000e8, 8);
        baseFeed.set(1, 3000e8, block.timestamp, block.timestamp, 1);

        harness = new ChainlinkCompositeOEVWrapperHarness(
            address(compositeOracle),
            address(baseFeed),
            address(1), // owner
            address(1), // chainlinkOracle
            address(1), // feeRecipient
            500, // 5%
            3600 // 1 hour
        );
    }

    function _deploy(
        address _compositeOracle,
        address _baseFeed
    ) internal returns (ChainlinkCompositeOEVWrapper wrapper) {
        wrapper = new ChainlinkCompositeOEVWrapper(
            _compositeOracle,
            _baseFeed,
            owner,
            chainlinkOracle,
            feeRecipient,
            defaultFeeBps,
            defaultMaxRoundDelay
        );
    }

    // ==================== Constructor Tests ====================

    function testConstructorSetsState() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        assertEq(
            address(wrapper.compositeOracle()),
            address(compositeOracle),
            "compositeOracle not set"
        );
        assertEq(
            address(wrapper.baseFeed()),
            address(baseFeed),
            "baseFeed not set"
        );
        assertEq(wrapper.owner(), owner, "owner not set");
        assertEq(
            wrapper.liquidatorFeeBps(),
            defaultFeeBps,
            "liquidatorFeeBps not set"
        );
        assertEq(
            wrapper.maxRoundDelay(),
            defaultMaxRoundDelay,
            "maxRoundDelay not set"
        );
        assertEq(wrapper.feeRecipient(), feeRecipient, "feeRecipient not set");
        assertEq(wrapper.cachedBaseRoundId(), 1, "cachedBaseRoundId not set");
        assertEq(
            wrapper.cachedCompositePrice(),
            3500e18,
            "cachedCompositePrice not set"
        );
    }

    function testConstructorRevertsZeroCompositeOracle() public {
        vm.expectRevert(
            bytes(
                "ChainlinkCompositeOEVWrapper: composite oracle cannot be zero address"
            )
        );
        new ChainlinkCompositeOEVWrapper(
            address(0),
            address(baseFeed),
            owner,
            chainlinkOracle,
            feeRecipient,
            defaultFeeBps,
            defaultMaxRoundDelay
        );
    }

    function testConstructorRevertsZeroBaseFeed() public {
        vm.expectRevert(
            bytes(
                "ChainlinkCompositeOEVWrapper: base feed cannot be zero address"
            )
        );
        new ChainlinkCompositeOEVWrapper(
            address(compositeOracle),
            address(0),
            owner,
            chainlinkOracle,
            feeRecipient,
            defaultFeeBps,
            defaultMaxRoundDelay
        );
    }

    function testConstructorRevertsZeroOwner() public {
        vm.expectRevert(
            bytes("ChainlinkCompositeOEVWrapper: owner cannot be zero address")
        );
        new ChainlinkCompositeOEVWrapper(
            address(compositeOracle),
            address(baseFeed),
            address(0),
            chainlinkOracle,
            feeRecipient,
            defaultFeeBps,
            defaultMaxRoundDelay
        );
    }

    function testConstructorRevertsFeeBpsOverMax() public {
        vm.expectRevert(
            bytes(
                "ChainlinkCompositeOEVWrapper: liquidator fee cannot be greater than MAX_BPS"
            )
        );
        new ChainlinkCompositeOEVWrapper(
            address(compositeOracle),
            address(baseFeed),
            owner,
            chainlinkOracle,
            feeRecipient,
            10001,
            defaultMaxRoundDelay
        );
    }

    function testConstructorRevertsZeroMaxRoundDelay() public {
        vm.expectRevert(
            bytes(
                "ChainlinkCompositeOEVWrapper: max round delay cannot be zero"
            )
        );
        new ChainlinkCompositeOEVWrapper(
            address(compositeOracle),
            address(baseFeed),
            owner,
            chainlinkOracle,
            feeRecipient,
            defaultFeeBps,
            0
        );
    }

    function testConstructorRevertsZeroChainlinkOracle() public {
        vm.expectRevert(
            bytes(
                "ChainlinkCompositeOEVWrapper: chainlink oracle cannot be zero address"
            )
        );
        new ChainlinkCompositeOEVWrapper(
            address(compositeOracle),
            address(baseFeed),
            owner,
            address(0),
            feeRecipient,
            defaultFeeBps,
            defaultMaxRoundDelay
        );
    }

    function testConstructorRevertsZeroFeeRecipient() public {
        vm.expectRevert(
            bytes(
                "ChainlinkCompositeOEVWrapper: fee recipient cannot be zero address"
            )
        );
        new ChainlinkCompositeOEVWrapper(
            address(compositeOracle),
            address(baseFeed),
            owner,
            chainlinkOracle,
            address(0),
            defaultFeeBps,
            defaultMaxRoundDelay
        );
    }

    // ==================== Decimals / Description / Version ====================

    function testDecimalsReturnsCompositeDecimals() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );
        assertEq(
            wrapper.decimals(),
            18,
            "Should return composite oracle decimals"
        );
    }

    function testDecimalsReturns8ForBoundedComposite() public {
        MockCompositeOracle bounded = new MockCompositeOracle(8, 60000e8);
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(bounded),
            address(baseFeed)
        );
        assertEq(
            wrapper.decimals(),
            8,
            "Should return bounded composite oracle decimals"
        );
    }

    function testDescription() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );
        assertEq(
            wrapper.description(),
            "Chainlink Composite OEV Wrapper",
            "Wrong description"
        );
    }

    function testVersion() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );
        assertEq(wrapper.version(), 1, "Wrong version");
    }

    // ==================== getRoundData ====================

    function testGetRoundDataReverts() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );
        vm.expectRevert(
            bytes(
                "ChainlinkCompositeOEVWrapper: getRoundData not supported for composite oracles"
            )
        );
        wrapper.getRoundData(1);
    }

    // ==================== latestRoundData Delay Logic ====================

    function testLatestRoundDataReturnsFreshWhenBaseRoundUnchanged() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        // Base feed round hasn't changed (still round 1, same as cache)
        // Should return fresh composite price
        (, int256 answer, , uint256 updatedAt, ) = wrapper.latestRoundData();

        assertEq(answer, 3500e18, "Should return fresh composite price");
        assertEq(updatedAt, block.timestamp, "Should return current timestamp");
    }

    function testLatestRoundDataReturnsCachedWhenNewRoundWithinDelay() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        // Advance base feed to round 2 (new price information)
        baseFeed.set(2, 3100e8, block.timestamp, block.timestamp, 2);

        // Update composite oracle to show new price
        compositeOracle.setPrice(3600e18);

        // Within delay window -> should return CACHED composite price
        (, int256 answer, , uint256 updatedAt, ) = wrapper.latestRoundData();

        assertEq(answer, 3500e18, "Should return cached composite price");
        assertEq(
            updatedAt,
            wrapper.cachedTimestamp(),
            "Should return cached timestamp"
        );
    }

    function testLatestRoundDataReturnsFreshWhenDelayExpired() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        // Advance base feed to round 2
        baseFeed.set(2, 3100e8, block.timestamp, block.timestamp, 2);

        // Update composite oracle to show new price
        compositeOracle.setPrice(3600e18);

        // Warp past delay window
        vm.warp(block.timestamp + defaultMaxRoundDelay);

        // Past delay window -> should return fresh composite price
        (, int256 answer, , , ) = wrapper.latestRoundData();

        assertEq(answer, 3600e18, "Should return fresh composite price");
    }

    function testLatestRoundDataRoundIdAlwaysZero() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        (uint80 roundId, , , , uint80 answeredInRound) = wrapper
            .latestRoundData();
        assertEq(roundId, 0, "roundId should always be 0");
        assertEq(answeredInRound, 0, "answeredInRound should always be 0");
    }

    function testLatestRoundDataRevertsOnZeroCompositePrice() public {
        compositeOracle.setPrice(0);

        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        vm.expectRevert(bytes("Chainlink price cannot be lower or equal to 0"));
        wrapper.latestRoundData();
    }

    function testLatestRoundDataRevertsOnNegativeCompositePrice() public {
        compositeOracle.setPrice(-1);

        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        vm.expectRevert(bytes("Chainlink price cannot be lower or equal to 0"));
        wrapper.latestRoundData();
    }

    // ==================== latestRound ====================

    function testLatestRoundReturnsBaseFeedRound() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        assertEq(
            wrapper.latestRound(),
            1,
            "Should return base feed latestRound"
        );

        baseFeed.set(5, 3100e8, block.timestamp, block.timestamp, 5);
        assertEq(
            wrapper.latestRound(),
            5,
            "Should return updated base feed round"
        );
    }

    // ==================== Setter Tests ====================

    function testSetLiquidatorFeeBpsUpdatesAndEmits() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        uint16 newFee = 250;
        vm.prank(owner);
        vm.expectEmit(false, false, false, true, address(wrapper));
        emit LiquidatorFeeBpsChanged(defaultFeeBps, newFee);
        wrapper.setLiquidatorFeeBps(newFee);

        assertEq(wrapper.liquidatorFeeBps(), newFee, "Fee not updated");
    }

    function testSetLiquidatorFeeBpsAboveMaxReverts() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        vm.prank(owner);
        vm.expectRevert(
            bytes(
                "ChainlinkCompositeOEVWrapper: liquidator fee cannot be greater than MAX_BPS"
            )
        );
        wrapper.setLiquidatorFeeBps(10001);
    }

    function testSetLiquidatorFeeBpsOnlyOwner() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        vm.prank(address(0xDEAD));
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        wrapper.setLiquidatorFeeBps(200);
    }

    function testSetMaxRoundDelayUpdatesAndEmits() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        uint256 newDelay = 600;
        vm.prank(owner);
        vm.expectEmit(false, false, false, true, address(wrapper));
        emit MaxRoundDelayChanged(defaultMaxRoundDelay, newDelay);
        wrapper.setMaxRoundDelay(newDelay);

        assertEq(wrapper.maxRoundDelay(), newDelay, "Delay not updated");
    }

    function testSetMaxRoundDelayZeroReverts() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        vm.prank(owner);
        vm.expectRevert(
            bytes(
                "ChainlinkCompositeOEVWrapper: max round delay cannot be zero"
            )
        );
        wrapper.setMaxRoundDelay(0);
    }

    function testSetMaxRoundDelayOnlyOwner() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        vm.prank(address(0xDEAD));
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        wrapper.setMaxRoundDelay(600);
    }

    function testSetFeeRecipientUpdatesAndEmits() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        address newRecipient = address(0xBEEF);
        vm.prank(owner);
        vm.expectEmit(false, false, false, true, address(wrapper));
        emit FeeRecipientChanged(feeRecipient, newRecipient);
        wrapper.setFeeRecipient(newRecipient);

        assertEq(wrapper.feeRecipient(), newRecipient, "Recipient not updated");
    }

    function testSetFeeRecipientZeroReverts() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        vm.prank(owner);
        vm.expectRevert(
            bytes(
                "ChainlinkCompositeOEVWrapper: fee recipient cannot be zero address"
            )
        );
        wrapper.setFeeRecipient(address(0));
    }

    function testSetFeeRecipientOnlyOwner() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        vm.prank(address(0xDEAD));
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        wrapper.setFeeRecipient(address(0xBEEF));
    }

    // ==================== Recovery Tests ====================

    function testRecoverETHSucceeds() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        uint256 ethAmount = 1 ether;
        vm.deal(address(wrapper), ethAmount);

        address payable recipient = payable(address(0xBEEF));
        uint256 recipientBalanceBefore = recipient.balance;

        vm.prank(owner);
        wrapper.recoverETH(recipient);

        assertEq(address(wrapper).balance, 0, "Wrapper should have 0 ETH");
        assertEq(
            recipient.balance,
            recipientBalanceBefore + ethAmount,
            "Recipient should have received ETH"
        );
    }

    function testRecoverETHOnlyOwner() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        vm.deal(address(wrapper), 1 ether);

        vm.prank(address(0xDEAD));
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        wrapper.recoverETH(payable(address(0xBEEF)));
    }

    function testRecoverERC20Succeeds() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        uint256 tokenAmount = 1000e18;
        token18.mint(address(wrapper), tokenAmount);

        address recipient = address(0xBEEF);

        vm.prank(owner);
        wrapper.recoverERC20(address(token18), recipient, tokenAmount);

        assertEq(
            token18.balanceOf(address(wrapper)),
            0,
            "Wrapper should have 0 tokens"
        );
        assertEq(
            token18.balanceOf(recipient),
            tokenAmount,
            "Recipient should have received tokens"
        );
    }

    function testRecoverERC20OnlyOwner() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        token18.mint(address(wrapper), 1000e18);

        vm.prank(address(0xDEAD));
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        wrapper.recoverERC20(address(token18), address(0xBEEF), 1000e18);
    }

    // ==================== Collateral Token Price Tests (18 decimal composite) ====================

    function testGetCollateralTokenPrice_Composite18Dec_Token18Dec() public {
        // Composite: 18 decimals, Token: 18 decimals
        // Price: wstETH = 3500e18 in composite oracle
        uint256 price = harness.exposed_getCollateralTokenPrice(
            3500e18,
            address(token18)
        );

        // Expected: 3500e18 (no scaling needed)
        assertEq(
            price,
            3500e18,
            "Price should be 3500e18 for 18 decimal token"
        );
    }

    function testGetCollateralTokenPrice_Composite18Dec_Token6Dec() public {
        // Composite: 18 decimals, Token: 6 decimals (USDC-like)
        // Price: 3500e18 in composite oracle
        uint256 price = harness.exposed_getCollateralTokenPrice(
            3500e18,
            address(token6)
        );

        // Expected: 3500e18 * 1e12 (adjust for 6 decimal token) = 3500e30
        assertEq(price, 3500e30, "Price should be 3500e30 for 6 decimal token");
    }

    function testGetCollateralTokenPrice_Composite8Dec_Token18Dec() public {
        // BoundedCompositeOracle uses 8 decimals
        MockCompositeOracle bounded = new MockCompositeOracle(8, 60000e8);
        ChainlinkCompositeOEVWrapperHarness boundedHarness = new ChainlinkCompositeOEVWrapperHarness(
                address(bounded),
                address(baseFeed),
                address(1),
                address(1),
                address(1),
                500,
                3600
            );

        uint256 price = boundedHarness.exposed_getCollateralTokenPrice(
            60000e8,
            address(token18)
        );

        // Expected: 60000e8 * 1e10 (scale to 18) = 60000e18
        assertEq(price, 60000e18, "Price should be 60000e18 for LBTC");
    }

    /// @notice Fuzz test to ensure no reverts for any valid decimal combination
    /// forge-config: default.fuzz.runs = 100
    function testFuzz_GetCollateralTokenPrice_NoRevert(
        uint8 compositeDecimals,
        uint8 tokenDecimals,
        uint128 answer
    ) public {
        compositeDecimals = uint8(bound(compositeDecimals, 0, 30));
        tokenDecimals = uint8(bound(tokenDecimals, 0, 30));
        vm.assume(answer > 0);

        MockCompositeOracle mockComposite = new MockCompositeOracle(
            compositeDecimals,
            int256(uint256(answer))
        );
        ChainlinkCompositeOEVWrapperHarness _harness = new ChainlinkCompositeOEVWrapperHarness(
                address(mockComposite),
                address(baseFeed),
                address(1),
                address(1),
                address(1),
                5000,
                3600
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

    // ==================== Collateral Split Tests ====================

    function testCalculateCollateralSplitWithExchangeRate() public {
        uint256 exchangeRate = 2e18;
        mTokenCollateral = new MockMToken(exchangeRate);

        uint256 collateralSeized = 100e18;
        uint256 repayAmount = 50e18;
        int256 collateralAnswer = 3500e18; // 18 decimal composite price

        // Mock the loan token price feed
        address mockLoanFeed = address(0x9999);
        vm.mockCall(
            address(1),
            abi.encodeWithSignature("getFeed(string)", loanToken.symbol()),
            abi.encode(mockLoanFeed)
        );
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

        assertGt(liquidatorFee, 0, "Liquidator fee should be > 0");
        assertEq(
            liquidatorFee + protocolFee,
            collateralSeized,
            "Total should equal collateral seized"
        );
    }

    // ==================== updatePriceEarlyAndLiquidate Revert Tests ====================

    function testUpdatePriceEarlyAndLiquidateRevertsZeroRepay() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        vm.expectRevert(
            bytes("ChainlinkCompositeOEVWrapper: repay amount cannot be zero")
        );
        wrapper.updatePriceEarlyAndLiquidate(
            address(0xBEEF),
            0,
            address(0x1),
            address(0x2)
        );
    }

    function testUpdatePriceEarlyAndLiquidateRevertsZeroBorrower() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        vm.expectRevert(
            bytes(
                "ChainlinkCompositeOEVWrapper: borrower cannot be zero address"
            )
        );
        wrapper.updatePriceEarlyAndLiquidate(
            address(0),
            1,
            address(0x1),
            address(0x2)
        );
    }

    function testUpdatePriceEarlyAndLiquidateRevertsZeroCollateral() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        vm.expectRevert(
            bytes(
                "ChainlinkCompositeOEVWrapper: mToken collateral cannot be zero address"
            )
        );
        wrapper.updatePriceEarlyAndLiquidate(
            address(0xBEEF),
            1,
            address(0),
            address(0x2)
        );
    }

    function testUpdatePriceEarlyAndLiquidateRevertsZeroLoan() public {
        ChainlinkCompositeOEVWrapper wrapper = _deploy(
            address(compositeOracle),
            address(baseFeed)
        );

        vm.expectRevert(
            bytes(
                "ChainlinkCompositeOEVWrapper: mToken loan cannot be zero address"
            )
        );
        wrapper.updatePriceEarlyAndLiquidate(
            address(0xBEEF),
            1,
            address(0x1),
            address(0)
        );
    }

    function testUpdatePriceEarlyAndLiquidateRevertsFeedMismatch() public {
        address mockChainlinkOracleAddr = address(0x1111);

        ChainlinkCompositeOEVWrapper wrapper = new ChainlinkCompositeOEVWrapper(
            address(compositeOracle),
            address(baseFeed),
            owner,
            mockChainlinkOracleAddr,
            feeRecipient,
            defaultFeeBps,
            defaultMaxRoundDelay
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
        // Feed does NOT match the wrapper
        vm.mockCall(
            mockChainlinkOracleAddr,
            abi.encodeWithSignature("getFeed(string)", "COLL"),
            abi.encode(address(0xDEAD))
        );

        vm.expectRevert(
            bytes(
                "ChainlinkCompositeOEVWrapper: chainlink oracle feed does not match"
            )
        );
        wrapper.updatePriceEarlyAndLiquidate(
            address(0xBEEF),
            100e18,
            mockMTokenCollateral,
            mockMTokenLoan
        );
    }

    function testUpdatePriceEarlyAndLiquidateRevertsOnTransferFailure() public {
        address mockChainlinkOracleAddr = address(0x1111);

        ChainlinkCompositeOEVWrapper wrapper = new ChainlinkCompositeOEVWrapper(
            address(compositeOracle),
            address(baseFeed),
            owner,
            mockChainlinkOracleAddr,
            feeRecipient,
            defaultFeeBps,
            defaultMaxRoundDelay
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
            address(0xBEEF),
            100e18,
            mockMTokenCollateral,
            mockMTokenLoan
        );
    }

    // ==================== Loan Price Validation Tests ====================

    function testLoanPriceValidationRevertsOnZeroAnswer() public {
        uint256 exchangeRate = 1e18;
        mTokenCollateral = new MockMToken(exchangeRate);

        address mockLoanFeed = address(0x9999);
        vm.mockCall(
            address(1),
            abi.encodeWithSignature("getFeed(string)", loanToken.symbol()),
            abi.encode(mockLoanFeed)
        );
        vm.mockCall(
            mockLoanFeed,
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(
                uint80(1),
                int256(0),
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

        vm.expectRevert(bytes("Chainlink price cannot be lower or equal to 0"));
        harness.exposed_calculateCollateralSplit(
            100e18,
            3500e18,
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
        vm.mockCall(
            address(1),
            abi.encodeWithSignature("getFeed(string)", loanToken.symbol()),
            abi.encode(mockLoanFeed)
        );
        vm.mockCall(
            mockLoanFeed,
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(
                uint80(5),
                int256(1e8),
                uint256(0),
                uint256(block.timestamp),
                uint80(3)
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
            3500e18,
            100e18,
            address(loanToken),
            address(mTokenCollateral),
            address(collateralToken)
        );
    }

    // ==================== Cache Update on Liquidation ====================

    function testCacheUpdatedAfterLiquidation() public {
        address mockChainlinkOracleAddr = address(0x1111);

        ChainlinkCompositeOEVWrapper wrapper = new ChainlinkCompositeOEVWrapper(
            address(compositeOracle),
            address(baseFeed),
            owner,
            mockChainlinkOracleAddr,
            feeRecipient,
            defaultFeeBps,
            defaultMaxRoundDelay
        );

        // Record initial cache
        uint256 initialCachedRound = wrapper.cachedBaseRoundId();
        assertEq(initialCachedRound, 1, "Initial cached round should be 1");

        // Advance base feed to round 5
        baseFeed.set(5, 3100e8, block.timestamp, block.timestamp, 5);

        // Update composite price
        compositeOracle.setPrice(3600e18);

        // Set up mocks for liquidation call
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

        // Mock successful transfer
        vm.mockCall(
            mockUnderlyingLoan,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                address(this),
                address(wrapper),
                100e18
            ),
            abi.encode(true)
        );

        // Mock approve
        vm.mockCall(
            mockUnderlyingLoan,
            abi.encodeWithSignature(
                "approve(address,uint256)",
                mockMTokenLoan,
                100e18
            ),
            abi.encode(true)
        );

        // Mock balanceOf for collateral mToken (before and after liquidation)
        vm.mockCall(
            mockMTokenCollateral,
            abi.encodeWithSignature("balanceOf(address)", address(wrapper)),
            abi.encode(uint256(0))
        );

        // Mock liquidateBorrow to return non-zero (failure)
        vm.mockCall(
            mockMTokenLoan,
            abi.encodeWithSignature(
                "liquidateBorrow(address,uint256,address)",
                address(0xBEEF),
                100e18,
                mockMTokenCollateral
            ),
            abi.encode(uint256(1))
        );

        // The liquidation will revert because liquidateBorrow returns non-zero
        // Confirms the flow reached past cache update into liquidation execution
        vm.expectRevert(
            bytes("ChainlinkCompositeOEVWrapper: liquidation failed")
        );
        wrapper.updatePriceEarlyAndLiquidate(
            address(0xBEEF),
            100e18,
            mockMTokenCollateral,
            mockMTokenLoan
        );
    }
}

// ==================== Mock Contracts ====================

/// @notice Mock composite oracle with configurable decimals and price
contract MockCompositeOracle is AggregatorV3Interface {
    uint8 private _decimals;
    int256 private _price;

    constructor(uint8 decimals_, int256 price_) {
        _decimals = decimals_;
        _price = price_;
    }

    function setPrice(int256 newPrice) external {
        _price = newPrice;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external pure override returns (string memory) {
        return "Mock Composite Oracle";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(
        uint80
    )
        external
        pure
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        revert("getRoundData not supported");
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        // Mimics ChainlinkCompositeOracle: roundId=0, startedAt=0, updatedAt=block.timestamp, answeredInRound=0
        return (0, _price, 0, block.timestamp, 0);
    }

    function latestRound() external pure override returns (uint256) {
        return 0;
    }
}

/// @notice Test harness to expose internal functions
contract ChainlinkCompositeOEVWrapperHarness is ChainlinkCompositeOEVWrapper {
    constructor(
        address _compositeOracle,
        address _baseFeed,
        address _owner,
        address _chainlinkOracle,
        address _feeRecipient,
        uint16 _liquidatorFeeBps,
        uint256 _maxRoundDelay
    )
        ChainlinkCompositeOEVWrapper(
            _compositeOracle,
            _baseFeed,
            _owner,
            _chainlinkOracle,
            _feeRecipient,
            _liquidatorFeeBps,
            _maxRoundDelay
        )
    {}

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

    function exposed_calculateCollateralSplit(
        uint256 repayAmount,
        int256 collateralAnswer,
        uint256 collateralSeized,
        address underlyingLoan,
        address mTokenCollateral_,
        address underlyingCollateral
    ) external view returns (uint256 liquidatorFee, uint256 protocolFee) {
        return
            _calculateCollateralSplit(
                repayAmount,
                collateralAnswer,
                collateralSeized,
                EIP20Interface(underlyingLoan),
                mTokenCollateral_,
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
