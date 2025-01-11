// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {console} from "@forge-std/console.sol";

import {MockChainlinkOracle} from "@test/mock/MockChainlinkOracle.sol";
import {MockERC20Decimals} from "@test/mock/MockERC20Decimals.sol";
import {ReserveAutomation} from "@protocol/market/ReserveAutomation.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {AutomationDeploy} from "@protocol/market/AutomationDeploy.sol";
import {ERC20HoldingDeposit} from "@protocol/market/ERC20HoldingDeposit.sol";

contract ReserveAutomationUnitTest is Test {
    MockChainlinkOracle public wellOracle;
    MockChainlinkOracle public reserveOracle;
    MockERC20Decimals public wellToken;
    MockERC20Decimals public reserveToken;
    ReserveAutomation public automation;
    ERC20HoldingDeposit public holdingDeposit;
    MErc20 public mToken;

    address public constant OWNER = address(0x1);
    address public constant GUARDIAN = address(0x2);
    address public constant USER = address(0x3);

    uint256 public constant SALE_WINDOW = 14 days;
    uint256 public constant MAX_DISCOUNT = 1e17; // 10%
    uint256 public constant DISCOUNT_APPLICATION_PERIOD = 4 hours;
    uint256 public constant NON_DISCOUNT_PERIOD = 4 hours;

    function setUp() public {
        // Setup tokens with different decimals
        wellToken = new MockERC20Decimals("WELL", "WELL", 18);
        reserveToken = new MockERC20Decimals("USDC", "USDC", 6);

        // Setup oracles with different prices
        wellOracle = new MockChainlinkOracle(1e18, 18); // $1.00
        reserveOracle = new MockChainlinkOracle(1e8, 8); // $1.00

        // Deploy holding deposit
        AutomationDeploy deployer = new AutomationDeploy();
        holdingDeposit = ERC20HoldingDeposit(
            deployer.deployERC20HoldingDeposit(address(wellToken), OWNER)
        );

        // Deploy mock mToken
        mToken = new MErc20();

        // Deploy automation contract
        ReserveAutomation.InitParams memory params = ReserveAutomation
            .InitParams({
                maxDiscount: MAX_DISCOUNT,
                discountApplicationPeriod: DISCOUNT_APPLICATION_PERIOD,
                nonDiscountPeriod: NON_DISCOUNT_PERIOD,
                recipientAddress: address(holdingDeposit),
                wellToken: address(wellToken),
                reserveAsset: address(reserveToken),
                wellChainlinkFeed: address(wellOracle),
                reserveChainlinkFeed: address(reserveOracle),
                owner: OWNER,
                mTokenMarket: address(mToken),
                guardian: GUARDIAN
            });

        automation = ReserveAutomation(
            deployer.deployReserveAutomation(params)
        );
    }

    function testSetup() public {
        assertEq(automation.maxDiscount(), MAX_DISCOUNT);
        assertEq(
            automation.discountApplicationPeriod(),
            DISCOUNT_APPLICATION_PERIOD
        );
        assertEq(automation.nonDiscountPeriod(), NON_DISCOUNT_PERIOD);
        assertEq(automation.recipientAddress(), address(holdingDeposit));
        assertEq(automation.wellToken(), address(wellToken));
        assertEq(automation.reserveAsset(), address(reserveToken));
        assertEq(automation.wellChainlinkFeed(), address(wellOracle));
        assertEq(automation.reserveChainlinkFeed(), address(reserveOracle));
        assertEq(automation.owner(), OWNER);
        assertEq(automation.guardian(), GUARDIAN);
        assertEq(automation.mTokenMarket(), address(mToken));
    }

    function testExchangeRateWithDifferentDecimals() public {
        // Setup initial state
        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals(); // 1000 USDC
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.startPrank(OWNER);
        automation.initiateSale(0);
        vm.stopPrank();

        // Calculate expected WELL amount
        // Both assets are $1, so 1000 USDC should require 1000 WELL
        uint256 expectedWellAmount = 1000 * 10 ** wellToken.decimals();
        uint256 actualWellAmount = automation.getAmountWellOut(reserveAmount);

        assertEq(
            actualWellAmount,
            expectedWellAmount,
            "Exchange rate incorrect"
        );
    }

    function testExchangeRateWithPriceDifference() public {
        // Set WELL price to $2
        wellOracle.set(12, int256(2e18), block.timestamp, block.timestamp, 12);

        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals(); // 1000 USDC
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.startPrank(OWNER);
        automation.initiateSale(0);
        vm.stopPrank();

        // Calculate expected WELL amount
        // WELL is $2, USDC is $1, so 1000 USDC should require 500 WELL
        uint256 expectedWellAmount = 500 * 10 ** wellToken.decimals();
        uint256 actualWellAmount = automation.getAmountWellOut(reserveAmount);

        assertEq(
            actualWellAmount,
            expectedWellAmount,
            "Price adjusted exchange rate incorrect"
        );
    }

    function testExchangeRateWithDiscount() public {
        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals(); // 1000 USDC
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.startPrank(OWNER);
        automation.initiateSale(0);
        vm.stopPrank();

        // Move time past non-discount period and halfway through discount period
        vm.warp(
            block.timestamp +
                NON_DISCOUNT_PERIOD +
                (DISCOUNT_APPLICATION_PERIOD / 2)
        );

        // Expected discount should be 5% (half of MAX_DISCOUNT)
        uint256 expectedDiscount = MAX_DISCOUNT / 2;
        assertEq(
            automation.currentDiscount(),
            expectedDiscount,
            "Discount calculation incorrect"
        );

        // Calculate expected WELL amount with discount
        // 1000 USDC with 5% discount should require 950 WELL
        uint256 expectedWellAmount = 950 * 10 ** wellToken.decimals();
        uint256 actualWellAmount = automation.getAmountWellOut(reserveAmount);

        assertEq(
            actualWellAmount,
            expectedWellAmount,
            "Discounted exchange rate incorrect"
        );
    }

    function testCompleteSwap() public {
        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals(); // 1000 USDC
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(0);

        // Move time to get max discount
        vm.warp(
            block.timestamp + NON_DISCOUNT_PERIOD + DISCOUNT_APPLICATION_PERIOD
        );

        uint256 wellAmount = automation.getAmountWellOut(automation.buffer());
        deal(address(wellToken), USER, wellAmount);

        vm.prank(USER);
        wellToken.approve(address(automation), wellAmount);

        uint256 preUserWellBalance = wellToken.balanceOf(USER);
        uint256 preUserReserveBalance = reserveToken.balanceOf(USER);
        uint256 preHoldingDepositWellBalance = wellToken.balanceOf(
            address(holdingDeposit)
        );
        uint256 preAutomationReserveBalance = reserveToken.balanceOf(
            address(automation)
        );

        vm.prank(USER);
        uint256 amountOut = automation.getReserves(wellAmount, 0);

        uint256 postUserWellBalance = wellToken.balanceOf(USER);
        uint256 postUserReserveBalance = reserveToken.balanceOf(USER);
        uint256 postHoldingDepositWellBalance = wellToken.balanceOf(
            address(holdingDeposit)
        );
        uint256 postAutomationReserveBalance = reserveToken.balanceOf(
            address(automation)
        );

        assertEq(
            preUserWellBalance - postUserWellBalance,
            wellAmount,
            "User WELL balance decrease incorrect"
        );
        assertEq(
            postUserReserveBalance - preUserReserveBalance,
            amountOut,
            "User reserve balance increase incorrect"
        );
        assertEq(
            postHoldingDepositWellBalance - preHoldingDepositWellBalance,
            wellAmount,
            "Holding deposit WELL balance increase incorrect"
        );
        assertEq(
            preAutomationReserveBalance - postAutomationReserveBalance,
            amountOut,
            "Automation reserve balance decrease incorrect"
        );
    }

    function testLastBidTimePartialBuffer() public {
        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals(); // 1000 USDC
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.startPrank(OWNER);
        automation.initiateSale(0);
        vm.stopPrank();

        /// move time 1/4 of the way through the sale window, this is multiple sale periods
        /// so the lastBidTime should increase to the current block timestamp because we are
        /// buying more than what would unlock in a single sale period
        vm.warp(automation.SALE_WINDOW() / 4 + block.timestamp);

        // Use 25% of buffer
        uint256 partialReserveAmount = automation.buffer() / 4;
        uint256 wellAmount = automation.getAmountWellOut(partialReserveAmount);
        deal(address(wellToken), USER, wellAmount);

        vm.startPrank(USER);
        wellToken.approve(address(automation), wellAmount);

        uint256 preLastBidTime = automation.lastBidTime();
        automation.getReserves(wellAmount, 0);
        vm.stopPrank();
        uint256 postLastBidTime = automation.lastBidTime();

        // LastBidTime should increase to the current block timestamp
        uint256 expectedIncrease = block.timestamp - preLastBidTime;
        assertEq(
            postLastBidTime - preLastBidTime,
            expectedIncrease,
            "Last bid time update incorrect"
        );
    }

    function testFuzzLastBidTimeUpdate(
        uint256 bufferPercentage,
        uint256 warpPercentage
    ) public {
        bufferPercentage = bound(bufferPercentage, 1, 100);
        warpPercentage = bound(warpPercentage, 1, 99);

        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals(); // 1000 USDC
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(0);

        vm.warp(
            block.timestamp + (automation.SALE_WINDOW() * warpPercentage) / 100
        );

        uint256 partialReserveAmount = (automation.buffer() *
            bufferPercentage) / 100;
        uint256 wellAmount = automation.getAmountWellOut(partialReserveAmount);
        deal(address(wellToken), USER, wellAmount);
        uint256 startingBuffer = automation.buffer();

        vm.startPrank(USER);
        wellToken.approve(address(automation), wellAmount);

        uint256 preLastBidTime = automation.lastBidTime();
        uint256 amountOut = automation.getReserves(wellAmount, 0);
        vm.stopPrank();

        uint256 expectedIncrease;
        if (
            amountOut >=
            (NON_DISCOUNT_PERIOD + DISCOUNT_APPLICATION_PERIOD) *
                automation.rateLimitPerSecond()
        ) {
            expectedIncrease = automation.lastBidTime() - preLastBidTime;
        } else {
            uint256 maxTimeDiff = NON_DISCOUNT_PERIOD +
                DISCOUNT_APPLICATION_PERIOD;
            uint256 actualTimeDiff = block.timestamp - preLastBidTime;
            uint256 effectiveTimeDiff = maxTimeDiff > actualTimeDiff
                ? actualTimeDiff
                : maxTimeDiff;

            expectedIncrease =
                ((effectiveTimeDiff) * amountOut) /
                startingBuffer;
        }

        assertEq(
            automation.lastBidTime() - preLastBidTime,
            expectedIncrease,
            "Last bid time update incorrect"
        );
    }

    function testFuzzExchangeRate(
        uint256 reserveAmount,
        uint256 wellPrice,
        uint256 reservePrice
    ) public {
        // Bound inputs to reasonable values
        reserveAmount = bound(
            reserveAmount,
            1e6,
            1e12 * 10 ** reserveToken.decimals()
        );
        wellPrice = bound(wellPrice, 1e17, 1e19); // $0.1 to $10
        reservePrice = bound(reservePrice, 1e7, 1e9); // $0.1 to $10

        wellOracle.set(
            12,
            int256(wellPrice),
            block.timestamp,
            block.timestamp,
            12
        );

        reserveOracle.set(
            12,
            int256(reservePrice),
            block.timestamp,
            block.timestamp,
            12
        );

        uint256 wellAmount = automation.getAmountWellOut(reserveAmount);

        // Calculate expected rate manually
        uint256 expectedWellAmount = (reserveAmount *
            uint256(automation.scalePrice(int256(reservePrice), 8, 18)) *
            (10 ** uint256(18 - reserveToken.decimals()))) / wellPrice;

        assertApproxEqRel(
            wellAmount,
            expectedWellAmount,
            1e15,
            "Exchange rate calculation incorrect"
        );
    }

    function testFuzzDiscountCalculation(uint256 timeElapsed) public {
        timeElapsed = bound(timeElapsed, 0, SALE_WINDOW);

        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals();
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.startPrank(OWNER);
        automation.initiateSale(0);
        vm.stopPrank();

        vm.warp(block.timestamp + timeElapsed);

        uint256 expectedDiscount;
        if (timeElapsed <= NON_DISCOUNT_PERIOD) {
            expectedDiscount = 0;
        } else {
            uint256 discountTime = timeElapsed - NON_DISCOUNT_PERIOD;
            if (discountTime >= DISCOUNT_APPLICATION_PERIOD) {
                expectedDiscount = MAX_DISCOUNT;
            } else {
                expectedDiscount =
                    (MAX_DISCOUNT * discountTime) /
                    DISCOUNT_APPLICATION_PERIOD;
            }
        }

        assertEq(
            automation.currentDiscount(),
            expectedDiscount,
            "Discount calculation incorrect"
        );
    }
}
