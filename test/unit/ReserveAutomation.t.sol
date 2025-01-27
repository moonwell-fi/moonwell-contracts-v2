// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {console} from "@forge-std/console.sol";
import {Test} from "@forge-std/Test.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MockCToken} from "@test/mock/MockCToken.sol";
import {AutomationDeploy} from "@protocol/market/AutomationDeploy.sol";
import {MockERC20Decimals} from "@test/mock/MockERC20Decimals.sol";
import {ReserveAutomation} from "@protocol/market/ReserveAutomation.sol";
import {MockChainlinkOracle} from "@test/mock/MockChainlinkOracle.sol";
import {ERC20HoldingDeposit} from "@protocol/market/ERC20HoldingDeposit.sol";

contract ReserveAutomationUnitTest is Test {
    MockChainlinkOracle public wellOracle;
    MockChainlinkOracle public reserveOracle;
    MockERC20Decimals public wellToken;
    MockERC20Decimals public reserveToken;
    ReserveAutomation public automation;
    ERC20HoldingDeposit public holdingDeposit;
    MockCToken public mToken;

    address public constant OWNER = address(0x1);
    address public constant GUARDIAN = address(0x2);
    address public constant USER = address(0x3);

    uint256 public constant SALE_WINDOW = 14 days;
    uint256 public constant MINI_AUCTION_PERIOD = 4 hours;
    uint256 public constant MAX_DISCOUNT = 9e17; // 90% == 10%
    uint256 public constant STARTING_PREMIUM = 11e17; // 110% == 10% premium

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
        mToken = new MockCToken(IERC20(address(reserveToken)), false);

        // Deploy automation contract
        ReserveAutomation.InitParams memory params = ReserveAutomation
            .InitParams({
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

    function testSetup() public view {
        assertEq(
            automation.recipientAddress(),
            address(holdingDeposit),
            "Incorrect recipient address"
        );
        assertEq(
            automation.wellToken(),
            address(wellToken),
            "Incorrect well token address"
        );
        assertEq(
            automation.reserveAsset(),
            address(reserveToken),
            "Incorrect reserve asset address"
        );
        assertEq(
            automation.wellChainlinkFeed(),
            address(wellOracle),
            "Incorrect well oracle address"
        );
        assertEq(
            automation.reserveChainlinkFeed(),
            address(reserveOracle),
            "Incorrect reserve oracle address"
        );
        assertEq(automation.owner(), OWNER, "Incorrect owner address");
        assertEq(automation.guardian(), GUARDIAN, "Incorrect guardian address");
        assertEq(
            automation.mTokenMarket(),
            address(mToken),
            "Incorrect mToken market address"
        );
        assertEq(
            automation.MAXIMUM_AUCTION_DELAY(),
            28 days,
            "incorrect max auction delay"
        );
    }

    function testInitiateSale(uint256 reserveAmount) public {
        reserveAmount =
            bound(reserveAmount, 1, 1_000_000_000) *
            10 ** reserveToken.decimals();

        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        assertTrue(automation.isSaleActive(), "sale not active");
        assertEq(automation.saleWindow(), SALE_WINDOW, "Incorrect sale window");
        assertEq(
            automation.miniAuctionPeriod(),
            MINI_AUCTION_PERIOD,
            "Incorrect mini auction period"
        );
        assertEq(
            automation.maxDiscount(),
            MAX_DISCOUNT,
            "Incorrect max discount"
        );
        assertEq(
            automation.startingPremium(),
            STARTING_PREMIUM,
            "Incorrect starting premium"
        );
        assertEq(
            automation.periodSaleAmount(),
            reserveAmount / (SALE_WINDOW / MINI_AUCTION_PERIOD),
            "Incorrect period sale amount"
        );
        assertEq(
            automation.saleStartTime(),
            block.timestamp,
            "Incorrect sale start time"
        );

        /// test that saleStartTime + saleWindow is not inclusive and is not active
        vm.warp(block.timestamp + SALE_WINDOW);
        assertFalse(automation.isSaleActive(), "sale inactive");
        assertEq(
            automation.currentDiscount(),
            1e18,
            "discount/premium not zero"
        );

        /// warp backwards to the final second of the sale and check that it is still active
        vm.warp(block.timestamp - 1);
        assertTrue(automation.isSaleActive(), "sale not active");
        assertEq(
            automation.currentDiscount(),
            MAX_DISCOUNT,
            "discount not final value"
        );
    }

    function testInitiateSaleWithDelay() public {
        uint256 delay = 1 days;
        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals();
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(
            delay,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        assertEq(
            automation.saleStartTime(),
            block.timestamp + delay,
            "Incorrect delayed sale start time"
        );
    }

    function testInitiateSaleFailsWithInvalidDelay() public {
        uint256 delay = 28 days + 1; // 1 second greater than MAXIMUM_AUCTION_DELAY
        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals();
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        vm.expectRevert("ReserveAutomationModule: delay exceeds max");
        automation.initiateSale(
            delay,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );
    }

    function testInitiateSaleFailsWithInvalidDiscount() public {
        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals();
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        vm.expectRevert(
            "ReserveAutomationModule: ending discount must be less than 1"
        );
        automation.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            1e18,
            STARTING_PREMIUM
        );
    }

    function testInitiateSaleFailsWithInvalidPremium() public {
        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals();
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        vm.expectRevert(
            "ReserveAutomationModule: starting premium must be greater than 1"
        );
        automation.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            1e18
        );
    }

    function testInitiateSaleFailsWithInvalidPeriods() public {
        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals();
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        vm.expectRevert(
            "ReserveAutomationModule: auction period not divisible by mini auction period"
        );
        automation.initiateSale(
            0,
            15 days,
            4 hours - 1,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        vm.prank(OWNER);
        vm.expectRevert(
            "ReserveAutomationModule: auction period not greater than mini auction period"
        );
        automation.initiateSale(
            0,
            4 hours,
            4 hours,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );
    }

    function testExchangeRateWithDifferentDecimals() public {
        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals();
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        uint256 expectedWellAmount = (1000 *
            10 ** wellToken.decimals() *
            automation.currentDiscount()) / 1e18;
        uint256 actualWellAmount = automation.getAmountWellOut(reserveAmount);

        assertEq(
            actualWellAmount,
            expectedWellAmount,
            "Exchange rate incorrect"
        );
    }

    function testPremiumAndDiscountAppliedFuzz(uint256 warpAmount) public {
        uint256 reserveAmount = 500 * 10 ** reserveToken.decimals();
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        vm.warp(
            block.timestamp + bound(warpAmount, 1, MINI_AUCTION_PERIOD - 1)
        );

        uint256 maxDecay = STARTING_PREMIUM - MAX_DISCOUNT;

        uint256 expectedDiscount = MAX_DISCOUNT +
            ((automation.getCurrentPeriodEndTime() - block.timestamp) *
                maxDecay) /
            (MINI_AUCTION_PERIOD - 1);

        assertEq(
            expectedDiscount,
            automation.currentDiscount(),
            "Current discount incorrect"
        );
    }

    function testPremiumAndDiscountAppliedOverMiniAuctionDuration() public {
        uint256 wellAmount = 500e18;
        wellOracle.set(12, int256(1e18), block.timestamp, block.timestamp, 12);

        uint256 reserveAmount = 500 * 10 ** reserveToken.decimals();
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        uint256 expectedWellAmount = (wellAmount *
            automation.currentDiscount()) / 1e18;
        uint256 actualWellAmount = automation.getAmountWellOut(reserveAmount);

        assertEq(
            actualWellAmount,
            expectedWellAmount,
            "Exchange rate incorrect with premium"
        );

        // Move to middle of mini auction period
        vm.warp(block.timestamp + MINI_AUCTION_PERIOD / 2);

        expectedWellAmount = (wellAmount * automation.currentDiscount()) / 1e18;
        actualWellAmount = automation.getAmountWellOut(reserveAmount);

        assertEq(
            actualWellAmount,
            expectedWellAmount,
            "Exchange rate incorrect"
        );

        // Move to end of mini auction period
        vm.warp(block.timestamp + MINI_AUCTION_PERIOD - 1);

        expectedWellAmount = (wellAmount * automation.currentDiscount()) / 1e18;
        actualWellAmount = automation.getAmountWellOut(reserveAmount);

        assertEq(
            actualWellAmount,
            expectedWellAmount,
            "Exchange rate incorrect"
        );
    }

    function testExchangeRateWithPriceDifference() public {
        wellOracle.set(12, int256(2e18), block.timestamp, block.timestamp, 12);

        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals();
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        uint256 expectedWellAmount = (500 *
            10 ** wellToken.decimals() *
            automation.currentDiscount()) / 1e18;
        uint256 actualWellAmount = automation.getAmountWellOut(reserveAmount);

        assertEq(
            actualWellAmount,
            expectedWellAmount,
            "Price adjusted exchange rate incorrect"
        );
    }

    function testCompleteSwap() public {
        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals();
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        uint256 wellAmount = automation.getAmountWellOut(
            reserveAmount / (SALE_WINDOW / MINI_AUCTION_PERIOD)
        );
        deal(address(wellToken), USER, wellAmount);

        vm.startPrank(USER);
        wellToken.approve(address(automation), wellAmount);

        uint256 preUserWellBalance = wellToken.balanceOf(USER);
        uint256 preUserReserveBalance = reserveToken.balanceOf(USER);
        uint256 preHoldingDepositWellBalance = wellToken.balanceOf(
            address(holdingDeposit)
        );
        uint256 preAutomationReserveBalance = reserveToken.balanceOf(
            address(automation)
        );

        uint256 amountOut = automation.getReserves(wellAmount, 0);
        vm.stopPrank();

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

    function testSetRecipientAddress() public {
        address newRecipient = address(0x123);

        vm.prank(OWNER);
        automation.setRecipientAddress(newRecipient);

        assertEq(
            automation.recipientAddress(),
            newRecipient,
            "Recipient address not updated correctly"
        );
    }

    function testSetGuardian() public {
        address newGuardian = address(0x123);

        vm.prank(OWNER);
        automation.setGuardian(newGuardian);

        assertEq(
            automation.guardian(),
            newGuardian,
            "Guardian address not updated correctly"
        );
    }

    function testCancelAuction() public {
        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals();
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(
            1 days,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        vm.prank(GUARDIAN);
        automation.cancelAuction();

        assertEq(
            automation.saleStartTime(),
            0,
            "Sale start time not reset to 0"
        );
        assertEq(
            automation.periodSaleAmount(),
            0,
            "Period sale amount not reset to 0"
        );
    }

    function testGetCurrentPeriodStartTime() public {
        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals();
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        assertEq(
            automation.getCurrentPeriodStartTime(),
            block.timestamp,
            "Initial period start time incorrect"
        );

        uint256 periodStartTime = automation.getCurrentPeriodStartTime();

        /// Move to middle of first period
        vm.warp(block.timestamp + MINI_AUCTION_PERIOD / 2);
        assertEq(
            automation.getCurrentPeriodStartTime(),
            periodStartTime,
            "Period start time changed during period"
        );

        /// Move to middle of second period
        vm.warp(block.timestamp + MINI_AUCTION_PERIOD);
        assertEq(
            automation.getCurrentPeriodStartTime(),
            automation.saleStartTime() + MINI_AUCTION_PERIOD,
            "Second period start time incorrect"
        );
    }

    function testGetCurrentPeriodEndTime() public {
        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals();
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        assertEq(
            automation.getCurrentPeriodEndTime(),
            block.timestamp + MINI_AUCTION_PERIOD - 1,
            "Period end time incorrect"
        );
    }

    function testGetCurrentPeriodRemainingReserves() public {
        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals();
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        uint256 expectedReservesRemaining = reserveAmount /
            (SALE_WINDOW / MINI_AUCTION_PERIOD);

        assertEq(
            automation.getCurrentPeriodRemainingReserves(),
            expectedReservesRemaining,
            "Initial period remaining reserves incorrect"
        );

        // Perform a swap for half the reserves available for sale during this period
        uint256 wellAmount = automation.getAmountWellOut(
            expectedReservesRemaining / 2
        );
        deal(address(wellToken), USER, wellAmount);

        vm.startPrank(USER);
        wellToken.approve(address(automation), wellAmount);
        uint256 amountOut = automation.getReserves(wellAmount, 0);
        vm.stopPrank();

        assertEq(
            automation.getCurrentPeriodRemainingReserves(),
            expectedReservesRemaining - amountOut,
            "Remaining reserves after swap incorrect"
        );
    }

    function testFuzzScalePrice(
        int256 price,
        uint8 priceDecimals,
        uint8 expectedDecimals
    ) public view {
        price = bound(price, 1, 1e18);
        priceDecimals = uint8(bound(priceDecimals, 1, 18));
        expectedDecimals = uint8(bound(expectedDecimals, 1, 18));

        int256 scaledPrice = automation.scalePrice(
            price,
            priceDecimals,
            expectedDecimals
        );

        if (priceDecimals < expectedDecimals) {
            assertEq(
                scaledPrice,
                price * int256(10 ** (expectedDecimals - priceDecimals)),
                "Incorrect price scaling when target decimals greater"
            );
        } else if (priceDecimals > expectedDecimals) {
            assertEq(
                scaledPrice,
                price / int256(10 ** (priceDecimals - expectedDecimals)),
                "Incorrect price scaling when target decimals smaller"
            );
        } else {
            assertEq(
                scaledPrice,
                price,
                "Price should not change when decimals match"
            );
        }
    }

    function testGetPriceAndDecimalsFailsWithInvalidOracleData() public {
        // Create a mock oracle that returns invalid data
        MockChainlinkOracle invalidOracle = new MockChainlinkOracle(0, 18);

        vm.expectRevert("ReserveAutomationModule: Oracle data is invalid");
        automation.getPriceAndDecimals(address(invalidOracle));

        // Test negative price
        invalidOracle.set(1, -1, block.timestamp, block.timestamp, 1);
        vm.expectRevert("ReserveAutomationModule: Oracle data is invalid");
        automation.getPriceAndDecimals(address(invalidOracle));
    }

    function testInitiateSaleFailsWithActiveSale() public {
        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals();
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        vm.prank(OWNER);
        vm.expectRevert("ReserveAutomationModule: sale already active");
        automation.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );
    }

    function testInitiateSaleFailsWithZeroReserves() public {
        vm.prank(OWNER);
        vm.expectRevert("ReserveAutomationModule: no reserves to sell");
        automation.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );
    }

    function testGetReservesFailsWithMinimumAmountOut() public {
        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals();
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        uint256 reserveAmountOut = reserveAmount /
            (SALE_WINDOW / MINI_AUCTION_PERIOD);

        uint256 wellAmount = automation.getAmountWellOut(reserveAmountOut);
        deal(address(wellToken), USER, wellAmount);

        vm.startPrank(USER);
        wellToken.approve(address(automation), wellAmount);

        uint256 minAmountOut = reserveAmountOut + 1; // More than possible amount out sold during a period
        vm.expectRevert("ReserveAutomationModule: not enough out");
        automation.getReserves(wellAmount, minAmountOut);
        vm.stopPrank();
    }

    function testGetReservesFailsWhenSaleNotActive() public {
        uint256 wellAmount = 1000 * 10 ** wellToken.decimals();
        deal(address(wellToken), USER, wellAmount);

        assertFalse(automation.isSaleActive(), "sale should not be active");
        vm.startPrank(USER);
        wellToken.approve(address(automation), wellAmount);

        vm.expectRevert("ReserveAutomationModule: sale not active");
        automation.getReserves(wellAmount, 0);
        vm.stopPrank();

        // Test with sale not started yet
        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals();
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(
            1 days,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );
        assertFalse(automation.isSaleActive(), "sale should not be active");

        vm.startPrank(USER);
        vm.expectRevert("ReserveAutomationModule: sale not active");
        automation.getReserves(wellAmount, 0);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        assertTrue(
            automation.isSaleActive(),
            "sale should be active at start timestamp"
        );

        // Test with sale ended
        vm.warp(block.timestamp + SALE_WINDOW + 2 days);
        assertFalse(
            automation.isSaleActive(),
            "sale should not be active post end timestamp"
        );

        vm.startPrank(USER);
        vm.expectRevert("ReserveAutomationModule: sale not active");
        automation.getReserves(wellAmount, 0);
        vm.stopPrank();
    }

    function testGetReservesFailsWithZeroAmountIn() public {
        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals();
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        vm.startPrank(USER);
        vm.expectRevert("ReserveAutomationModule: amount in is 0");
        automation.getReserves(0, 0);
        vm.stopPrank();
    }

    function testCancelAuctionFailsWithNonGuardian() public {
        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals();
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(
            1 days,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        vm.prank(USER);
        vm.expectRevert("ReserveAutomationModule: only guardian");
        automation.cancelAuction();
    }

    function testGetReservesFailsWithInsufficientReserves() public {
        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals();
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        automation.currentDiscount();

        // Try to buy more than available by ~10%
        uint256 wellAmount = automation.getAmountWellOut(
            (reserveAmount * 12) / 10
        );
        deal(address(wellToken), USER, wellAmount);

        vm.startPrank(USER);
        wellToken.approve(address(automation), wellAmount);
        vm.expectRevert(
            "ReserveAutomationModule: not enough reserves remaining"
        );
        automation.getReserves(wellAmount, 0);
        vm.stopPrank();
    }

    function testPeriodCyclingAndAssetManagement() public {
        uint256 reserveAmount = 1000 * 10 ** reserveToken.decimals();
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        // Calculate expected values
        uint256 totalPeriods = SALE_WINDOW / MINI_AUCTION_PERIOD;
        uint256 expectedPeriodAmount = reserveAmount / totalPeriods;

        // Initial state checks
        assertEq(
            automation.saleStartTime(),
            block.timestamp,
            "Sale start time not set correctly"
        );
        assertEq(
            automation.periodSaleAmount(),
            expectedPeriodAmount,
            "Initial period sale amount incorrect"
        );
        assertEq(
            automation.getCurrentPeriodRemainingReserves(),
            expectedPeriodAmount,
            "Initial period remaining reserves incorrect"
        );

        // Test each period
        for (uint256 i = 0; i < totalPeriods; i++) {
            uint256 periodStart = automation.getCurrentPeriodStartTime();
            uint256 periodEnd = automation.getCurrentPeriodEndTime();

            // Verify period boundaries
            assertEq(
                periodStart,
                automation.saleStartTime() + (i * MINI_AUCTION_PERIOD),
                "Period start time incorrect"
            );
            assertEq(
                periodEnd,
                periodStart + MINI_AUCTION_PERIOD - 1,
                "Period end time incorrect"
            );

            assertEq(
                MINI_AUCTION_PERIOD - 1,
                periodEnd - periodStart,
                "Period duration incorrect"
            );

            // Test start of period
            assertEq(
                automation.getCurrentPeriodRemainingReserves(),
                expectedPeriodAmount,
                "Remaining reserves incorrect at period start"
            );

            // Move to middle of period and perform a purchase
            vm.warp(periodStart + MINI_AUCTION_PERIOD / 2);

            uint256 purchaseAmount = expectedPeriodAmount / 2;
            uint256 wellAmount = automation.getAmountWellOut(purchaseAmount);

            deal(address(wellToken), USER, wellAmount);
            vm.startPrank(USER);
            wellToken.approve(address(automation), wellAmount);

            uint256 preVaultBalance = reserveToken.balanceOf(
                address(automation)
            );
            uint256 preUserBalance = reserveToken.balanceOf(USER);

            uint256 expectedOut = automation.getAmountReservesOut(wellAmount);
            automation.getReserves(wellAmount, expectedOut);
            vm.stopPrank();

            // Verify balances after purchase
            assertEq(
                preVaultBalance - reserveToken.balanceOf(address(automation)),
                expectedOut,
                "Vault balance decrease incorrect"
            );
            assertEq(
                reserveToken.balanceOf(USER) - preUserBalance,
                expectedOut,
                "User balance increase incorrect"
            );
            assertEq(
                automation.getCurrentPeriodRemainingReserves(),
                expectedPeriodAmount - expectedOut,
                "Remaining reserves incorrect after purchase"
            );

            // Move to end of period
            vm.warp(periodEnd);

            // Verify we can still purchase at the end of the period
            uint256 remainingAmount = automation
                .getCurrentPeriodRemainingReserves();
            wellAmount = automation.getAmountWellOut(remainingAmount);
            deal(address(wellToken), USER, wellAmount);

            vm.startPrank(USER);
            wellToken.approve(address(automation), wellAmount);
            expectedOut = automation.getAmountReservesOut(wellAmount);
            automation.getReserves(wellAmount, expectedOut);
            vm.stopPrank();

            // Move to start of next period
            vm.warp(periodEnd + 1);

            // If not the last period, verify next period starts with full amount
            if (i < totalPeriods - 1) {
                assertEq(
                    automation.getCurrentPeriodRemainingReserves(),
                    expectedPeriodAmount,
                    "Incorrect remaining reserves at period start"
                );

                // Verify no overlap between periods
                assertEq(
                    automation.getCurrentPeriodStartTime(),
                    periodEnd + 1,
                    "Period start time overlaps with previous period"
                );
            }
        }

        // Verify sale is over after all periods
        vm.warp(block.timestamp + 1);
        vm.expectRevert("ReserveAutomationModule: sale not active");
        automation.getReserves(1e18, 0);
    }

    function testFuzzPurchaseAtExactPeriodStart(uint256 reserveAmount) public {
        reserveAmount = bound(
            reserveAmount,
            10 * 10 ** reserveToken.decimals(),
            1_000_000_000 * 10 ** reserveToken.decimals()
        );
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(
            1 days, // Start in 1 day
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        // Warp to exact sale start time
        vm.warp(block.timestamp + 1 days);

        // Verify we're at exact period start
        assertEq(
            block.timestamp,
            automation.getCurrentPeriodStartTime(),
            "Not at exact period start time"
        );

        // Attempt purchase at exact start
        uint256 purchaseAmount = automation.getCurrentPeriodRemainingReserves();
        uint256 wellAmount = automation.getAmountWellOut(purchaseAmount);

        deal(address(wellToken), USER, wellAmount);
        vm.startPrank(USER);
        wellToken.approve(address(automation), wellAmount);

        uint256 preVaultBalance = reserveToken.balanceOf(address(automation));
        uint256 preUserBalance = reserveToken.balanceOf(USER);
        uint256 preHolderBalance = wellToken.balanceOf(address(holdingDeposit));

        // Verify discount is at starting premium
        assertEq(
            automation.currentDiscount(),
            STARTING_PREMIUM,
            "Discount not at starting premium at period start"
        );

        uint256 expectedOut = automation.getAmountReservesOut(wellAmount);
        automation.getReserves(wellAmount, expectedOut);
        vm.stopPrank();

        // Verify balances
        assertEq(
            preVaultBalance - reserveToken.balanceOf(address(automation)),
            expectedOut,
            "Incorrect vault balance decrease at period start"
        );
        assertEq(
            reserveToken.balanceOf(USER) - preUserBalance,
            expectedOut,
            "Incorrect user balance increase at period start"
        );
        assertEq(
            wellToken.balanceOf(address(holdingDeposit)) - preHolderBalance,
            wellAmount,
            "Incorrect holder WELL balance increase at period start"
        );
    }

    function testFuzzPurchaseAtExactPeriodEnd(uint256 reserveAmount) public {
        reserveAmount = bound(
            reserveAmount,
            10 * 10 ** reserveToken.decimals(),
            1_000_000_000 * 10 ** reserveToken.decimals()
        );
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        // Warp to exact end of first period
        uint256 periodEnd = automation.getCurrentPeriodEndTime();
        vm.warp(periodEnd);

        // Verify we're at exact period end
        assertEq(
            block.timestamp,
            automation.getCurrentPeriodEndTime(),
            "Not at exact period end time"
        );

        // Attempt purchase at exact end
        uint256 purchaseAmount = automation.getCurrentPeriodRemainingReserves();
        uint256 wellAmount = automation.getAmountWellOut(purchaseAmount);

        deal(address(wellToken), USER, wellAmount);
        vm.startPrank(USER);
        wellToken.approve(address(automation), wellAmount);

        uint256 preVaultBalance = reserveToken.balanceOf(address(automation));
        uint256 preUserBalance = reserveToken.balanceOf(USER);
        uint256 preHolderBalance = wellToken.balanceOf(address(holdingDeposit));

        // Verify discount is at maximum discount
        assertEq(
            automation.currentDiscount(),
            MAX_DISCOUNT,
            "Discount not at maximum at period end"
        );

        uint256 expectedOut = automation.getAmountReservesOut(wellAmount);
        automation.getReserves(wellAmount, expectedOut);
        vm.stopPrank();

        // Verify balances
        assertEq(
            preVaultBalance - reserveToken.balanceOf(address(automation)),
            expectedOut,
            "Incorrect vault balance decrease at period end"
        );
        assertEq(
            reserveToken.balanceOf(USER) - preUserBalance,
            expectedOut,
            "Incorrect user balance increase at period end"
        );
        assertEq(
            wellToken.balanceOf(address(holdingDeposit)) - preHolderBalance,
            wellAmount,
            "Incorrect holder WELL balance increase at period end"
        );

        // Verify next period starts correctly
        vm.warp(periodEnd + 1);
        assertEq(
            automation.getCurrentPeriodStartTime(),
            periodEnd + 1,
            "Next period start time incorrect after period end"
        );
    }

    function testFuzzPurchaseAtExactSaleEnd(uint256 reserveAmount) public {
        reserveAmount = bound(
            reserveAmount,
            10 * 10 ** reserveToken.decimals(),
            1_000_000_000 * 10 ** reserveToken.decimals()
        );
        deal(address(reserveToken), address(automation), reserveAmount);

        vm.prank(OWNER);
        automation.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        // Warp to exact end of sale
        uint256 saleEnd = automation.saleStartTime() + automation.saleWindow();
        vm.warp(saleEnd - 1); // Last valid timestamp

        // Verify we're at last valid timestamp
        assertEq(
            block.timestamp,
            saleEnd - 1,
            "Not at last valid sale timestamp"
        );

        // Attempt purchase at last valid moment
        uint256 purchaseAmount = automation.getCurrentPeriodRemainingReserves();
        uint256 wellAmount = automation.getAmountWellOut(purchaseAmount);

        deal(address(wellToken), USER, wellAmount);
        vm.startPrank(USER);
        wellToken.approve(address(automation), wellAmount);

        uint256 preVaultBalance = reserveToken.balanceOf(address(automation));
        uint256 preUserBalance = reserveToken.balanceOf(USER);
        uint256 preHolderBalance = wellToken.balanceOf(address(holdingDeposit));

        uint256 expectedOut = automation.getAmountReservesOut(wellAmount);
        automation.getReserves(wellAmount, expectedOut);
        vm.stopPrank();

        // Verify balances
        assertEq(
            preVaultBalance - reserveToken.balanceOf(address(automation)),
            expectedOut,
            "Incorrect vault balance decrease at sale end"
        );
        assertEq(
            reserveToken.balanceOf(USER) - preUserBalance,
            expectedOut,
            "Incorrect user balance increase at sale end"
        );
        assertEq(
            wellToken.balanceOf(address(holdingDeposit)) - preHolderBalance,
            wellAmount,
            "Incorrect holder WELL balance increase at sale end"
        );
    }

    function testGetPriceAndDecimalsFailsWithZeroPrice() public {
        // Set WELL price to 0
        wellOracle.set(1, 0, 0, block.timestamp, 1);

        vm.expectRevert("ReserveAutomationModule: Oracle data is invalid");
        automation.getAmountWellOut(1e6);

        // Reset WELL price and set reserve price to 0
        wellOracle.set(1, 1e8, 0, block.timestamp, 1);
        reserveOracle.set(1, 0, 0, block.timestamp, 1);

        vm.expectRevert("ReserveAutomationModule: Oracle data is invalid");
        automation.getAmountWellOut(1e6);
    }

    function testGetPriceAndDecimalsFailsWithNegativePrice() public {
        // Set WELL price to negative
        wellOracle.set(1, -1e8, 0, block.timestamp, 1);

        vm.expectRevert("ReserveAutomationModule: Oracle data is invalid");
        automation.getAmountWellOut(1e6);

        // Reset WELL price and set reserve price to negative
        wellOracle.set(1, 1e8, 0, block.timestamp, 1);
        reserveOracle.set(1, -1e8, 0, block.timestamp, 1);

        vm.expectRevert("ReserveAutomationModule: Oracle data is invalid");
        automation.getAmountWellOut(1e6);
    }

    function testGetPriceAndDecimalsFailsWithIncompleteRound() public {
        // Set WELL price with incomplete round (answeredInRound < roundId)
        wellOracle.set(2, 1e8, block.timestamp, block.timestamp, 1);

        vm.expectRevert("ReserveAutomationModule: Oracle data is invalid");
        automation.getAmountWellOut(1e6);

        // Reset WELL price and set reserve price with incomplete round
        wellOracle.set(1, 1e8, block.timestamp, block.timestamp, 1);
        reserveOracle.set(2, 1e8, block.timestamp, block.timestamp, 1);

        vm.expectRevert("ReserveAutomationModule: Oracle data is invalid");
        automation.getAmountWellOut(1e6);
    }

    function testGetPriceAndDecimalsWithDifferentDecimals() public {
        // Test with different oracle decimals
        MockChainlinkOracle wellOracleNew = new MockChainlinkOracle(1e6, 6); // $1.00 with 6 decimals
        MockChainlinkOracle reserveOracleNew = new MockChainlinkOracle(
            1e10,
            10
        ); // $1.00 with 10 decimals

        AutomationDeploy deployer = new AutomationDeploy();
        ReserveAutomation.InitParams memory params = ReserveAutomation
            .InitParams({
                recipientAddress: address(holdingDeposit),
                wellToken: address(wellToken),
                reserveAsset: address(reserveToken),
                wellChainlinkFeed: address(wellOracleNew),
                reserveChainlinkFeed: address(reserveOracleNew),
                owner: OWNER,
                mTokenMarket: address(mToken),
                guardian: GUARDIAN
            });

        ReserveAutomation automationNew = ReserveAutomation(
            deployer.deployReserveAutomation(params)
        );

        // Both assets should have the same USD value despite different oracle decimals
        uint256 wellAmount = automationNew.getAmountWellOut(1e6); // 1 USDC
        assertEq(
            wellAmount,
            1e18,
            "Incorrect WELL amount when oracles have different decimals"
        );
    }

    function testFuzzPriceScaling(
        uint8 wellOracleDecimals,
        uint8 reserveOracleDecimals,
        int256 wellPrice,
        int256 reservePrice
    ) public {
        // Bound decimals between 6 and 18
        wellOracleDecimals = uint8(bound(wellOracleDecimals, 6, 18));
        reserveOracleDecimals = uint8(bound(reserveOracleDecimals, 6, 18));

        // Bound prices to reasonable values (0.01 to 10000 USD)
        wellPrice = int256(bound(uint256(wellPrice), 1e4, 1e22));
        reservePrice = int256(bound(uint256(reservePrice), 1e4, 1e22));

        // Create new oracles with fuzzed decimals
        MockChainlinkOracle wellOracleNew = new MockChainlinkOracle(
            wellPrice,
            wellOracleDecimals
        );
        MockChainlinkOracle reserveOracleNew = new MockChainlinkOracle(
            reservePrice,
            reserveOracleDecimals
        );

        AutomationDeploy deployer = new AutomationDeploy();
        ReserveAutomation.InitParams memory params = ReserveAutomation
            .InitParams({
                recipientAddress: address(holdingDeposit),
                wellToken: address(wellToken),
                reserveAsset: address(reserveToken),
                wellChainlinkFeed: address(wellOracleNew),
                reserveChainlinkFeed: address(reserveOracleNew),
                owner: OWNER,
                mTokenMarket: address(mToken),
                guardian: GUARDIAN
            });

        ReserveAutomation automationNew = ReserveAutomation(
            deployer.deployReserveAutomation(params)
        );

        // Get amount of WELL for 1 unit of reserve asset
        uint256 oneReserveUnit = 10 ** reserveToken.decimals();
        uint256 wellAmount = automationNew.getAmountWellOut(oneReserveUnit);

        // Calculate expected amount based on oracle prices and decimals
        uint256 expectedWellAmount = (oneReserveUnit *
            uint256(reservePrice) *
            10 ** (wellToken.decimals() + wellOracleDecimals)) /
            (uint256(wellPrice) *
                10 ** (reserveToken.decimals() + reserveOracleDecimals));

        // Allow for some rounding error due to different decimal scaling
        assertApproxEqRel(
            wellAmount,
            expectedWellAmount,
            1e16, // 1% tolerance
            "Incorrect WELL amount with fuzzed oracle decimals"
        );
    }

    function testOraclePriceSynchronization() public {
        // Initial prices: WELL = $1.00, Reserve = $1.00
        // Set oracle prices with correct decimals
        wellOracle = new MockChainlinkOracle(1e18, 18); // $1.00 with 18 decimals
        reserveOracle = new MockChainlinkOracle(1e8, 8); // $1.00 with 8 decimals

        AutomationDeploy deployer = new AutomationDeploy();
        ReserveAutomation.InitParams memory params = ReserveAutomation
            .InitParams({
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

        uint256 initialWellAmount = automation.getAmountWellOut(1e6);
        assertEq(
            initialWellAmount,
            1e18,
            "Initial exchange rate incorrect for equal prices"
        );

        // Change WELL price to $2.00
        wellOracle.set(1, 2e18, 0, block.timestamp, 1);
        uint256 wellAmount = automation.getAmountWellOut(1e6);
        assertEq(
            wellAmount,
            5e17,
            "Exchange rate incorrect after WELL price increase"
        );

        // Change reserve price to $2.00
        reserveOracle.set(1, 2e8, 0, block.timestamp, 1);
        wellAmount = automation.getAmountWellOut(1e6);
        assertEq(
            wellAmount,
            1e18,
            "Exchange rate incorrect when prices are equal again"
        );
    }

    function testFuzzPriceCachingWithinPeriod(
        uint256 warpAmount,
        uint256 reserveAmount,
        uint256 numBids
    ) public {
        // Bound inputs to reasonable values
        reserveAmount = bound(
            reserveAmount,
            10 * 10 ** reserveToken.decimals(),
            1_000_000 * 10 ** reserveToken.decimals()
        );
        numBids = bound(numBids, 2, 10);
        // Ensure there's enough time left in period for all bids
        warpAmount = bound(warpAmount, 1, MINI_AUCTION_PERIOD - numBids * 100);

        deal(address(reserveToken), address(automation), reserveAmount);
        // Set initial prices
        int256 wellPrice = 1e18;
        int256 reservePrice = 1e8;
        wellOracle.set(1, wellPrice, 0, block.timestamp, 1);
        reserveOracle.set(1, reservePrice, 0, block.timestamp, 1);

        vm.prank(OWNER);
        automation.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        {
            // Get initial prices
            ReserveAutomation.CachedChainlinkPrices
                memory initialPrices = automation.getCachedChainlinkPrices();
            assertEq(
                initialPrices.wellPrice,
                0,
                "Initial WELL price incorrect"
            );
            assertEq(
                initialPrices.reservePrice,
                0,
                "Initial reserve price incorrect"
            );
        }

        uint256 amountPerBid = automation.getCurrentPeriodRemainingReserves() /
            numBids;

        // Record initial exchange rate and prices
        uint256 initialWellAmount = automation.getAmountWellOut(amountPerBid);
        uint256 initialReserveAmount = automation.getAmountReservesOut(
            initialWellAmount
        );

        // Make first bid
        deal(address(wellToken), USER, initialWellAmount);
        vm.startPrank(USER);
        wellToken.approve(address(automation), initialWellAmount);
        automation.getReserves(initialWellAmount, initialReserveAmount);
        vm.stopPrank();

        // Verify that the exchange rate is still using the cached prices
        ReserveAutomation.CachedChainlinkPrices
            memory currentPrices = automation.getCachedChainlinkPrices();

        // Calculate expected amounts based on initial prices
        uint256 remainingReserves = automation
            .getCurrentPeriodRemainingReserves();
        assertGt(remainingReserves, 0, "No reserves remaining");

        // Make remaining bids and verify exchange rate remains the same
        for (uint256 i = 1; i < numBids; i++) {
            // Move time forward but stay within period
            vm.warp(block.timestamp + 50);

            uint256 wellAmount = automation.getAmountWellOut(amountPerBid);
            uint256 reserveAmountOut = automation.getAmountReservesOut(
                wellAmount
            );

            // Verify cached prices remain unchanged
            ReserveAutomation.CachedChainlinkPrices
                memory cachedPrices = automation.getCachedChainlinkPrices();
            assertEq(
                cachedPrices.wellPrice,
                currentPrices.wellPrice,
                "Cached WELL price changed"
            );
            assertEq(
                cachedPrices.reservePrice,
                currentPrices.reservePrice,
                "Cached reserve price changed"
            );

            {
                // Calculate expected amounts based on initial prices and current discount
                uint256 currentDiscount = automation.currentDiscount();

                // First normalize the reserve amount to 18 decimals if needed
                uint256 normalizedReserveAmount = amountPerBid;
                if (reserveToken.decimals() != 18) {
                    normalizedReserveAmount =
                        amountPerBid *
                        (10 ** (18 - reserveToken.decimals()));
                }

                // Calculate reserve asset value in USD (both prices are already normalized by getNormalizedPrice)
                uint256 reserveAssetValue = normalizedReserveAmount *
                    uint256(currentPrices.reservePrice);

                // Get WELL amount by dividing by WELL price
                uint256 expectedWellAmount = (reserveAssetValue *
                    currentDiscount *
                    10 ** 10) / (uint256(currentPrices.wellPrice) * 1e18);

                // Expected reserve amount should match input amount since we're calculating based on the reserve input
                uint256 expectedReserveAmount = amountPerBid;

                // Verify exchange rate matches expected values
                assertApproxEqAbs(
                    wellAmount,
                    expectedWellAmount,
                    1e8,
                    "WELL amount changed after oracle price update"
                );
                assertApproxEqAbs(
                    reserveAmountOut,
                    expectedReserveAmount,
                    1e8,
                    "Reserve amount changed after oracle price update"
                );
            }

            // Change prices does not impact sale price
            wellOracle.set(
                1,
                currentPrices.wellPrice * 2,
                0,
                block.timestamp,
                1
            );
            reserveOracle.set(
                1,
                currentPrices.reservePrice * 6,
                0,
                block.timestamp,
                1
            );

            // Execute bid
            deal(address(wellToken), USER, wellAmount);
            vm.startPrank(USER);
            wellToken.approve(address(automation), wellAmount);
            automation.getReserves(wellAmount, reserveAmountOut);
            vm.stopPrank();
        }

        // Move to next period and verify new prices are used
        vm.warp(automation.getCurrentPeriodEndTime() + 1);

        uint256 newWellAmount = automation.getAmountWellOut(amountPerBid);
        assertNotEq(
            newWellAmount,
            initialWellAmount,
            "Exchange rate should change in new period"
        );
    }
}
