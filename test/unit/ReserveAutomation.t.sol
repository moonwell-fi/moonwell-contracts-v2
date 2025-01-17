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
        assertEq(automation.recipientAddress(), address(holdingDeposit));
        assertEq(automation.wellToken(), address(wellToken));
        assertEq(automation.reserveAsset(), address(reserveToken));
        assertEq(automation.wellChainlinkFeed(), address(wellOracle));
        assertEq(automation.reserveChainlinkFeed(), address(reserveOracle));
        assertEq(automation.owner(), OWNER);
        assertEq(automation.guardian(), GUARDIAN);
        assertEq(automation.mTokenMarket(), address(mToken));
    }

    function testInitiateSale() public {
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

        assertEq(automation.saleWindow(), SALE_WINDOW);
        assertEq(automation.miniAuctionPeriod(), MINI_AUCTION_PERIOD);
        assertEq(automation.maxDiscount(), MAX_DISCOUNT);
        assertEq(automation.startingPremium(), STARTING_PREMIUM);
        assertEq(automation.periodSaleAmount(), reserveAmount / (SALE_WINDOW / MINI_AUCTION_PERIOD));
        assertEq(automation.saleStartTime(), block.timestamp);
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

        assertEq(automation.saleStartTime(), block.timestamp + delay);
    }

    function testInitiateSaleFailsWithInvalidDelay() public {
        uint256 delay = 7 days + 1; // 1 second greater than MAXIMUM_AUCTION_DELAY
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

        uint256 wellAmount = automation.getAmountWellOut(reserveAmount / (SALE_WINDOW / MINI_AUCTION_PERIOD));
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

        assertEq(automation.recipientAddress(), newRecipient);
    }

    function testSetGuardian() public {
        address newGuardian = address(0x123);

        vm.prank(OWNER);
        automation.setGuardian(newGuardian);

        assertEq(automation.guardian(), newGuardian);
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

        assertEq(automation.saleStartTime(), 0);
        assertEq(automation.periodSaleAmount(), 0);
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

        assertEq(automation.getCurrentPeriodStartTime(), block.timestamp, "start time incorrect");

        uint256 periodStartTime = automation.getCurrentPeriodStartTime();

        /// Move to middle of first period
        vm.warp(block.timestamp + MINI_AUCTION_PERIOD / 2);
        assertEq(
            automation.getCurrentPeriodStartTime(),
            periodStartTime,
            "Current period start time incorrect after warping"
        );

        /// Move to middle of second period
        vm.warp(block.timestamp + MINI_AUCTION_PERIOD);
        assertEq(
            automation.getCurrentPeriodStartTime(),
            automation.saleStartTime() + MINI_AUCTION_PERIOD,
            "Current period start time incorrect"
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
            block.timestamp + MINI_AUCTION_PERIOD - 1
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

        uint256 expectedReservesRemaining = reserveAmount / (SALE_WINDOW / MINI_AUCTION_PERIOD);

        assertEq(automation.getCurrentPeriodRemainingReserves(), expectedReservesRemaining, "Current period remaining reserves incorrect 1");

        // Perform a swap for half the reserves available for sale during this period
        uint256 wellAmount = automation.getAmountWellOut(expectedReservesRemaining / 2);
        deal(address(wellToken), USER, wellAmount);

        vm.startPrank(USER);
        wellToken.approve(address(automation), wellAmount);
        uint256 amountOut = automation.getReserves(wellAmount, 0);
        vm.stopPrank();

        assertEq(
            automation.getCurrentPeriodRemainingReserves(),
            expectedReservesRemaining - amountOut,
            "Current period remaining reserves incorrect 2"
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
                price * int256(10 ** (expectedDecimals - priceDecimals))
            );
        } else if (priceDecimals > expectedDecimals) {
            assertEq(
                scaledPrice,
                price / int256(10 ** (priceDecimals - expectedDecimals))
            );
        } else {
            assertEq(scaledPrice, price);
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

        uint256 reserveAmountOut = reserveAmount / (SALE_WINDOW / MINI_AUCTION_PERIOD);

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

        vm.startPrank(USER);
        vm.expectRevert("ReserveAutomationModule: sale not active");
        automation.getReserves(wellAmount, 0);
        vm.stopPrank();

        // Test with sale ended
        vm.warp(block.timestamp + SALE_WINDOW + 2 days);
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
        uint256 wellAmount = automation.getAmountWellOut(reserveAmount * 12 / 10);
        deal(address(wellToken), USER, wellAmount);

        vm.startPrank(USER);
        wellToken.approve(address(automation), wellAmount);
        vm.expectRevert(
            "ReserveAutomationModule: not enough reserves remaining"
        );
        automation.getReserves(wellAmount, 0);
        vm.stopPrank();
    }
}
