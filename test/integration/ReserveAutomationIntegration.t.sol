// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

import "@forge-std/Test.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MErc20Storage} from "@protocol/MTokenInterfaces.sol";
import {AutomationDeploy} from "@protocol/market/AutomationDeploy.sol";
import {MockERC20Decimals} from "@test/mock/MockERC20Decimals.sol";
import {ReserveAutomation} from "@protocol/market/ReserveAutomation.sol";
import {ERC20HoldingDeposit} from "@protocol/market/ERC20HoldingDeposit.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract ReserveAutomationLiveIntegrationTest is Test {
    event ERC20Withdrawn(
        address indexed tokenAddress,
        address indexed to,
        uint256 amount
    );

    ERC20 public underlying;
    ERC20 public well;

    ReserveAutomation public vault;
    MErc20 public mToken;

    ERC20HoldingDeposit public holder;

    Addresses private _addresses;

    address private _guardian;

    uint256 public constant SALE_WINDOW = 14 days;
    uint256 public constant MINI_AUCTION_PERIOD = 4 hours;
    uint256 public constant MAX_DISCOUNT = 9e17; // 90% == 10% discount
    uint256 public constant STARTING_PREMIUM = 11e17; // 110% == 10% premium

    function setUp() public {
        _addresses = new Addresses();
        _guardian = address(0x123);

        underlying = ERC20(_addresses.getAddress("USDC"));
        mToken = MErc20(_addresses.getAddress("MOONWELL_USDC"));

        uint256 mintAmount = 10 ** 6;

        deal(address(underlying), address(this), mintAmount);

        well = ERC20(_addresses.getAddress("xWELL_PROXY"));

        AutomationDeploy deployer = new AutomationDeploy();

        holder = ERC20HoldingDeposit(
            deployer.deployERC20HoldingDeposit(
                address(well),
                _addresses.getAddress("TEMPORAL_GOVERNOR")
            )
        );

        ReserveAutomation.InitParams memory params = ReserveAutomation
            .InitParams({
                recipientAddress: address(holder),
                wellToken: address(well),
                reserveAsset: address(underlying),
                wellChainlinkFeed: _addresses.getAddress("CHAINLINK_WELL_USD"),
                reserveChainlinkFeed: _addresses.getAddress("USDC_ORACLE"),
                owner: _addresses.getAddress("TEMPORAL_GOVERNOR"),
                mTokenMarket: address(mToken),
                guardian: _guardian
            });

        vault = ReserveAutomation(deployer.deployReserveAutomation(params));
    }

    function testSetup() public view {
        assertEq(
            vault.recipientAddress(),
            address(holder),
            "incorrect recipient address"
        );
        assertEq(
            vault.wellToken(),
            address(well),
            "incorrect well token address"
        );
        assertEq(
            vault.reserveAsset(),
            address(underlying),
            "incorrect reserve asset address"
        );
        assertEq(
            vault.wellChainlinkFeed(),
            _addresses.getAddress("CHAINLINK_WELL_USD"),
            "incorrect well chainlink feed"
        );
        assertEq(
            vault.reserveChainlinkFeed(),
            _addresses.getAddress("USDC_ORACLE"),
            "incorrect reserve chainlink feed"
        );
        assertEq(
            vault.reserveAssetDecimals(),
            ERC20(address(underlying)).decimals(),
            "incorrect reserve asset decimals"
        );
        assertEq(
            vault.mTokenMarket(),
            address(mToken),
            "incorrect mToken market"
        );
        assertEq(vault.guardian(), _guardian, "incorrect guardian");

        assertEq(vault.saleStartTime(), 0, "incorrect sale start time");
        assertEq(vault.periodSaleAmount(), 0, "incorrect period sale amount");

        assertEq(
            holder.token(),
            address(well),
            "incorrect holder token address"
        );
    }

    function testConstructionFailsReserveAssetDecimalsGt18() public {
        AutomationDeploy deployer = new AutomationDeploy();
        MockERC20Decimals mockUnderlying = new MockERC20Decimals(
            "USDC",
            "USDC",
            19
        );

        ReserveAutomation.InitParams memory params = ReserveAutomation
            .InitParams({
                recipientAddress: address(holder),
                wellToken: address(well),
                reserveAsset: address(mockUnderlying),
                wellChainlinkFeed: _addresses.getAddress("CHAINLINK_WELL_USD"),
                reserveChainlinkFeed: _addresses.getAddress("USDC_ORACLE"),
                owner: _addresses.getAddress("TEMPORAL_GOVERNOR"),
                mTokenMarket: address(mToken),
                guardian: _guardian
            });

        vm.mockCall(
            address(mToken),
            abi.encodeWithSignature("underlying()"),
            abi.encode(address(mockUnderlying))
        );
        vm.expectRevert(
            "ReserveAutomationModule: reserve asset has too many decimals"
        );
        ReserveAutomation(deployer.deployReserveAutomation(params));
    }

    function testSetGuardianRevertNonOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vault.setGuardian(address(0x456));
    }

    function testSetGuardianSucceedsOwner() public {
        address newGuardian = address(0x456);
        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.setGuardian(newGuardian);
        assertEq(vault.guardian(), newGuardian, "guardian not set correctly");
    }

    function testCancelAuctionRevertNonGuardian() public {
        vm.expectRevert("ReserveAutomationModule: only guardian");
        vault.cancelAuction();
    }

    function testCancelAuctionRevertAlreadyActive() public {
        uint256 usdcAmount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(
            1 days,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        vm.warp(block.timestamp + 43200);

        mToken.accrueInterest();

        uint256 totalReserves = mToken.totalReserves();

        vm.prank(_guardian);
        vault.cancelAuction();

        assertEq(vault.guardian(), _guardian, "guardian still active");
        assertEq(vault.saleStartTime(), 0, "sale start time not reset");
        assertEq(vault.periodSaleAmount(), 0, "period sale amount not reset");
        assertEq(
            underlying.balanceOf(address(vault)),
            0,
            "vault balance not 0 post auction cancel"
        );
        assertEq(
            mToken.totalReserves() - totalReserves,
            usdcAmount,
            "total reserves should increase post auction cancel"
        );
    }

    function testCancelAuctionFailedMarketReturn() public {
        uint256 usdcAmount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(
            1 days,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        vm.mockCall(
            address(mToken),
            abi.encodeWithSelector(MErc20._addReserves.selector, usdcAmount),
            abi.encode(1)
        );

        vm.prank(_guardian);
        vm.expectRevert("ReserveAutomationModule: add reserves failure");
        vault.cancelAuction();
    }

    function testInitiateSaleFailsAlreadyActive() public {
        uint256 usdcAmount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(
            1 days,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectRevert("ReserveAutomationModule: sale already active");
        vault.initiateSale(
            1 days,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );
    }

    function testInitiateSaleFailsNoReserves() public {
        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectRevert("ReserveAutomationModule: no reserves to sell");
        vault.initiateSale(
            1 days,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );
    }

    function testInitiateSaleFailsExceedsMaxDelay() public {
        uint256 usdcAmount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectRevert("ReserveAutomationModule: delay exceeds max");
        vault.initiateSale(
            14 days + 1,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );
    }

    function testPurchaseReservesFailsSaleNotActive() public {
        /// sale not started which causes failure
        vm.expectRevert("ReserveAutomationModule: sale not active");
        vault.getReserves(0, 0);

        uint256 usdcAmount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(
            1,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        vm.expectRevert("ReserveAutomationModule: sale not active");
        vault.getReserves(0, 0);

        deal(address(well), address(this), 1_000e18);
        well.approve(address(vault), 1_000e18);

        vm.warp(block.timestamp + 1);
        vault.getReserves(1, 0);

        vm.warp(block.timestamp + vault.saleWindow());

        /// sale is over which causes failure
        vm.expectRevert("ReserveAutomationModule: sale not active");
        vault.getReserves(0, 0);
    }

    function testPurchaseReservesFailsZeroAmount() public {
        uint256 usdcAmount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(
            1,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        vm.warp(block.timestamp + 1);

        vm.expectRevert("ReserveAutomationModule: amount in is 0");
        vault.getReserves(0, 0);
    }

    function testPurchaseReservesFailsInsufficientReserves() public {
        uint256 usdcAmount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(
            1,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        vm.warp(block.timestamp + 1);

        uint256 wellAmount = vault.getAmountWellOut((usdcAmount * 12) / 10);
        deal(address(well), address(this), wellAmount);
        well.approve(address(vault), wellAmount);

        vm.expectRevert(
            "ReserveAutomationModule: not enough reserves remaining"
        );
        vault.getReserves(wellAmount, 0);
    }

    function testPurchaseReservesFailsAmountOutNotGteMinAmtOut() public {
        uint256 usdcAmount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(
            1,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        vm.warp(block.timestamp + MINI_AUCTION_PERIOD / 2);

        uint256 wellAmount = vault.getAmountWellOut(
            vault.getCurrentPeriodRemainingReserves()
        );
        deal(address(well), address(this), wellAmount);
        well.approve(address(vault), wellAmount);

        vm.expectRevert("ReserveAutomationModule: not enough out");
        vault.getReserves(wellAmount, usdcAmount + 1);
    }

    function testPurchaseReservesFailsNoWellApproval() public {
        uint256 usdcAmount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(
            1,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        vm.warp(block.timestamp + MINI_AUCTION_PERIOD / 2);

        uint256 usdcPurchaseAmount = usdcAmount /
            (SALE_WINDOW / MINI_AUCTION_PERIOD);

        uint256 wellAmount = vault.getAmountWellOut(usdcPurchaseAmount);
        deal(address(well), address(this), wellAmount);

        vm.expectRevert("ERC20: insufficient allowance");
        vault.getReserves(wellAmount, 1);
    }

    /// we never expect this state to be reachable but test it anyway for completeness
    function testPurchaseReservesFailsNoAssets() public {
        uint256 usdcAmount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(
            1,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        vm.warp(block.timestamp + MINI_AUCTION_PERIOD / 2);

        uint256 usdcPurchaseAmount = usdcAmount /
            (SALE_WINDOW / MINI_AUCTION_PERIOD);

        uint256 wellAmount = vault.getAmountWellOut(usdcPurchaseAmount);
        deal(address(well), address(this), wellAmount);
        well.approve(address(vault), wellAmount);

        deal(address(underlying), address(vault), 0);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vault.getReserves(wellAmount, 1);
    }

    function testAmountInTolerance(uint256 amountWellIn) public view {
        amountWellIn = _bound(amountWellIn, 1e18, uint256(type(uint128).max));

        uint256 getAmountReservesOut = vault.getAmountReservesOut(amountWellIn);
        uint256 getAmountIn = vault.getAmountWellOut(getAmountReservesOut);

        /// must be within 1 basis point
        assertApproxEqRel(
            getAmountIn,
            amountWellIn,
            1e14,
            "amount in not within tolerance"
        );
    }

    function testAmountOutTolerance(uint256 amountReservesIn) public view {
        amountReservesIn = _bound(
            amountReservesIn,
            uint256(1e6),
            uint256(1_000_000_000e6)
        );

        uint256 getAmountWellOut = vault.getAmountWellOut(amountReservesIn);
        uint256 getAmountReservesOut = vault.getAmountReservesOut(
            getAmountWellOut
        );

        assertApproxEqRel(
            amountReservesIn,
            getAmountReservesOut,
            1.0001e12,
            "amount reserves out not within tolerance"
        );
    }

    function testSwapWellForUSDC() public {
        uint256 usdcAmount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        assertEq(
            vault.saleStartTime(),
            block.timestamp,
            "incorrect sale start time"
        );
        assertEq(
            vault.periodSaleAmount(),
            usdcAmount / (SALE_WINDOW / MINI_AUCTION_PERIOD),
            "incorrect period sale amount"
        );

        // Move to middle of mini auction period
        vm.warp(block.timestamp + MINI_AUCTION_PERIOD / 2);

        uint256 wellAmount = vault.getAmountWellOut(
            vault.getCurrentPeriodRemainingReserves()
        );
        deal(address(well), address(this), wellAmount);

        well.approve(address(vault), wellAmount);

        uint256 initialHolderWellBalance = well.balanceOf(address(holder));
        uint256 initialUSDCBalance = underlying.balanceOf(address(this));

        uint256 expectedOut = vault.getAmountReservesOut(wellAmount);

        uint256 actualAmountOut = vault.getReserves(wellAmount, expectedOut);

        assertEq(
            well.balanceOf(address(holder)) - initialHolderWellBalance,
            wellAmount,
            "holder well balance did not increase"
        );

        assertEq(
            underlying.balanceOf(address(this)) - initialUSDCBalance,
            actualAmountOut,
            "this contract usdc balance did not increase post swap"
        );
    }

    function testSwapWellForWETH() public {
        AutomationDeploy deployer = new AutomationDeploy();

        ERC20 weth = ERC20(_addresses.getAddress("WETH"));

        ReserveAutomation.InitParams memory params = ReserveAutomation
            .InitParams({
                recipientAddress: address(holder),
                wellToken: address(well),
                reserveAsset: address(weth),
                wellChainlinkFeed: _addresses.getAddress("CHAINLINK_WELL_USD"),
                reserveChainlinkFeed: _addresses.getAddress("ETH_ORACLE"),
                owner: _addresses.getAddress("TEMPORAL_GOVERNOR"),
                mTokenMarket: _addresses.getAddress("MOONWELL_WETH"),
                guardian: _guardian
            });

        ReserveAutomation wethVault = ReserveAutomation(
            deployer.deployReserveAutomation(params)
        );

        uint256 wethAmount = 10 * 10 ** ERC20(address(weth)).decimals();
        deal(address(weth), address(wethVault), wethAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        wethVault.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        assertEq(
            wethVault.saleStartTime(),
            block.timestamp,
            "incorrect sale start time"
        );
        assertEq(
            wethVault.periodSaleAmount(),
            wethAmount / (SALE_WINDOW / MINI_AUCTION_PERIOD),
            "incorrect period sale amount"
        );

        // Move to middle of mini auction period
        vm.warp(block.timestamp + MINI_AUCTION_PERIOD / 2);

        uint256 wellAmount = wethVault.getAmountWellOut(
            wethVault.getCurrentPeriodRemainingReserves()
        );
        deal(address(well), address(this), wellAmount);

        well.approve(address(wethVault), wellAmount);

        uint256 initialHolderWellBalance = well.balanceOf(address(holder));
        uint256 initialWETHBalance = weth.balanceOf(address(this));

        uint256 expectedOut = wethVault.getAmountReservesOut(wellAmount);

        uint256 actualAmountOut = wethVault.getReserves(
            wellAmount,
            expectedOut
        );

        assertEq(
            well.balanceOf(address(holder)) - initialHolderWellBalance,
            wellAmount,
            "holder well balance did not increase"
        );

        assertEq(
            weth.balanceOf(address(this)) - initialWETHBalance,
            actualAmountOut,
            "this contract weth balance did not increase post swap"
        );
    }

    function testFuzzDiscountCalculation(uint256 timeElapsed) public {
        uint256 usdcAmount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        assertEq(
            vault.saleStartTime(),
            block.timestamp,
            "incorrect sale start time"
        );

        timeElapsed = bound(timeElapsed, 1, MINI_AUCTION_PERIOD - 1);

        vm.warp(block.timestamp + timeElapsed);

        uint256 maxDecay = STARTING_PREMIUM - MAX_DISCOUNT;
        uint256 expectedDiscount = MAX_DISCOUNT +
            ((vault.getCurrentPeriodEndTime() - block.timestamp) * maxDecay) /
            (MINI_AUCTION_PERIOD - 1);

        assertEq(
            vault.currentDiscount(),
            expectedDiscount,
            "incorrect discount calculation"
        );
    }

    function testSetRecipientAddressRevertNonOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vault.setRecipientAddress(address(1));
    }

    function testSetRecipientAddress() public {
        address newRecipient = address(1);
        address oldRecipient = vault.recipientAddress();

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.setRecipientAddress(newRecipient);

        assertEq(
            vault.recipientAddress(),
            newRecipient,
            "recipient address not updated"
        );
        assertTrue(
            oldRecipient != newRecipient,
            "recipient address should have changed"
        );
    }

    function testWithdrawERC20TokenRevertNonOwner() public {
        uint256 amount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), amount);

        vm.expectRevert("Ownable: caller is not the owner");
        vault.withdrawERC20Token(address(underlying), address(this), amount);
    }

    function testWithdrawERC20TokenRevertZeroAddress() public {
        uint256 amount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), amount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectRevert("ERC20HoldingDeposit: to address cannot be 0");
        vault.withdrawERC20Token(address(underlying), address(0), amount);
    }

    function testWithdrawERC20TokenRevertZeroAmount() public {
        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectRevert("ERC20HoldingDeposit: amount must be greater than 0");
        vault.withdrawERC20Token(address(underlying), address(this), 0);
    }

    function testWithdrawERC20TokenSucceeds() public {
        uint256 amount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), amount);

        uint256 initialBalance = underlying.balanceOf(address(this));

        vm.expectEmit(true, true, false, true);
        emit ERC20Withdrawn(address(underlying), address(this), amount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.withdrawERC20Token(address(underlying), address(this), amount);

        assertEq(
            underlying.balanceOf(address(this)) - initialBalance,
            amount,
            "recipient balance did not increase correctly"
        );
        assertEq(
            underlying.balanceOf(address(vault)),
            0,
            "vault balance not zero after withdrawal"
        );
    }

    function testPeriodCyclingAndAssetManagement() public {
        uint256 usdcAmount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        // Calculate expected values
        uint256 totalPeriods = SALE_WINDOW / MINI_AUCTION_PERIOD;
        uint256 expectedPeriodAmount = usdcAmount / totalPeriods;

        // Initial state checks
        assertEq(
            vault.saleStartTime(),
            block.timestamp,
            "incorrect sale start time"
        );
        assertEq(
            vault.periodSaleAmount(),
            expectedPeriodAmount,
            "incorrect period sale amount"
        );
        assertEq(
            vault.getCurrentPeriodRemainingReserves(),
            expectedPeriodAmount,
            "incorrect initial period remaining reserves"
        );

        // Test each period
        for (uint256 i = 0; i < totalPeriods; i++) {
            uint256 periodStart = vault.getCurrentPeriodStartTime();
            uint256 periodEnd = vault.getCurrentPeriodEndTime();

            // Verify period boundaries
            if (i > 0) {
                assertEq(
                    periodStart,
                    vault.saleStartTime() + (i * MINI_AUCTION_PERIOD),
                    "incorrect period start time"
                );
                assertEq(
                    periodEnd,
                    periodStart + MINI_AUCTION_PERIOD - 1,
                    "incorrect period end time"
                );
            }

            // Test start of period
            assertEq(
                vault.getCurrentPeriodRemainingReserves(),
                expectedPeriodAmount,
                "incorrect remaining reserves at period start"
            );

            // Move to middle of period and perform a purchase
            vm.warp(periodStart + MINI_AUCTION_PERIOD / 2);

            uint256 purchaseAmount = expectedPeriodAmount / 2;
            uint256 wellAmount = vault.getAmountWellOut(purchaseAmount);

            deal(address(well), address(this), wellAmount);
            well.approve(address(vault), wellAmount);

            uint256 preVaultBalance = underlying.balanceOf(address(vault));
            uint256 preUserBalance = underlying.balanceOf(address(this));
            uint256 preHolderBalance = well.balanceOf(address(holder));

            uint256 expectedOut = vault.getAmountReservesOut(wellAmount);
            vault.getReserves(wellAmount, expectedOut);

            // Verify balances after purchase
            assertEq(
                preVaultBalance - underlying.balanceOf(address(vault)),
                expectedOut,
                "incorrect vault balance decrease"
            );
            assertEq(
                underlying.balanceOf(address(this)) - preUserBalance,
                expectedOut,
                "incorrect user balance increase"
            );
            assertEq(
                well.balanceOf(address(holder)) - preHolderBalance,
                wellAmount,
                "incorrect holder well balance increase"
            );
            assertEq(
                vault.getCurrentPeriodRemainingReserves(),
                expectedPeriodAmount - expectedOut,
                "incorrect remaining reserves after purchase"
            );

            // Move to end of period
            vm.warp(periodEnd);

            // Verify we can still purchase at the end of the period
            uint256 remainingAmount = vault.getCurrentPeriodRemainingReserves();
            wellAmount = vault.getAmountWellOut(remainingAmount);
            deal(address(well), address(this), wellAmount);
            well.approve(address(vault), wellAmount);
            expectedOut = vault.getAmountReservesOut(wellAmount);
            vault.getReserves(wellAmount, expectedOut);

            // Move to start of next period
            vm.warp(periodEnd + 1);

            // If not the last period, verify next period starts with full amount
            if (i < totalPeriods - 1) {
                assertEq(
                    vault.getCurrentPeriodRemainingReserves(),
                    expectedPeriodAmount,
                    "incorrect remaining reserves at start of next period"
                );

                // Verify no overlap between periods
                assertEq(
                    vault.getCurrentPeriodStartTime(),
                    periodEnd + 1,
                    "period start time overlaps with previous period"
                );
            }
        }

        // Verify sale is over after all periods
        vm.warp(block.timestamp + 1);
        vm.expectRevert("ReserveAutomationModule: sale not active");
        vault.getReserves(1e18, 0);
    }

    function testFuzzPurchaseAtExactPeriodStart(uint256 usdcAmount) public {
        usdcAmount = bound(
            usdcAmount,
            10 * 10 ** ERC20(address(underlying)).decimals(),
            1_000_000_000 * 10 ** ERC20(address(underlying)).decimals()
        );
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(
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
            vault.getCurrentPeriodStartTime(),
            "not at exact period start"
        );

        // Attempt purchase at exact start
        uint256 purchaseAmount = vault.getCurrentPeriodRemainingReserves();
        uint256 wellAmount = vault.getAmountWellOut(purchaseAmount);

        deal(address(well), address(this), wellAmount);
        well.approve(address(vault), wellAmount);

        uint256 preVaultBalance = underlying.balanceOf(address(vault));
        uint256 preUserBalance = underlying.balanceOf(address(this));
        uint256 preHolderBalance = well.balanceOf(address(holder));

        // Verify discount is at starting premium
        assertEq(
            vault.currentDiscount(),
            STARTING_PREMIUM,
            "incorrect starting discount"
        );

        uint256 expectedOut = vault.getAmountReservesOut(wellAmount);
        vault.getReserves(wellAmount, expectedOut);

        // Verify balances
        assertEq(
            preVaultBalance - underlying.balanceOf(address(vault)),
            expectedOut,
            "incorrect vault balance decrease"
        );
        assertEq(
            underlying.balanceOf(address(this)) - preUserBalance,
            expectedOut,
            "incorrect user balance increase"
        );
        assertEq(
            well.balanceOf(address(holder)) - preHolderBalance,
            wellAmount,
            "incorrect holder well balance increase"
        );
    }

    function testFuzzPurchaseAtExactPeriodEnd(uint256 usdcAmount) public {
        usdcAmount = bound(
            usdcAmount,
            10 * 10 ** ERC20(address(underlying)).decimals(),
            1_000_000_000 * 10 ** ERC20(address(underlying)).decimals()
        );
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        // Warp to exact end of first period
        uint256 periodEnd = vault.getCurrentPeriodEndTime();
        vm.warp(periodEnd);

        // Verify we're at exact period end
        assertEq(
            block.timestamp,
            vault.getCurrentPeriodEndTime(),
            "not at exact period end"
        );

        // Attempt purchase at exact end
        uint256 purchaseAmount = vault.getCurrentPeriodRemainingReserves();
        uint256 wellAmount = vault.getAmountWellOut(purchaseAmount);

        deal(address(well), address(this), wellAmount);
        well.approve(address(vault), wellAmount);

        uint256 preVaultBalance = underlying.balanceOf(address(vault));
        uint256 preUserBalance = underlying.balanceOf(address(this));
        uint256 preHolderBalance = well.balanceOf(address(holder));

        // Verify discount is at maximum discount
        assertEq(
            vault.currentDiscount(),
            MAX_DISCOUNT,
            "incorrect ending discount"
        );

        uint256 expectedOut = vault.getAmountReservesOut(wellAmount);
        vault.getReserves(wellAmount, expectedOut);

        // Verify balances
        assertEq(
            preVaultBalance - underlying.balanceOf(address(vault)),
            expectedOut,
            "incorrect vault balance decrease"
        );
        assertEq(
            underlying.balanceOf(address(this)) - preUserBalance,
            expectedOut,
            "incorrect user balance increase"
        );
        assertEq(
            well.balanceOf(address(holder)) - preHolderBalance,
            wellAmount,
            "incorrect holder well balance increase"
        );

        // Verify next period starts correctly
        vm.warp(periodEnd + 1);
        assertEq(
            vault.getCurrentPeriodStartTime(),
            periodEnd + 1,
            "incorrect next period start time"
        );
    }

    function testFuzzPurchaseAtExactSaleEnd(uint256 usdcAmount) public {
        usdcAmount = bound(
            usdcAmount,
            10 * 10 ** ERC20(address(underlying)).decimals(),
            1_000_000_000 * 10 ** ERC20(address(underlying)).decimals()
        );
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        // Warp to exact end of sale
        uint256 saleEnd = vault.saleStartTime() + vault.saleWindow();
        vm.warp(saleEnd - 1); // Last valid timestamp

        // Verify we're at last valid timestamp
        assertEq(block.timestamp, saleEnd - 1, "not at last valid timestamp");

        // Attempt purchase at last valid moment
        uint256 purchaseAmount = vault.getCurrentPeriodRemainingReserves();
        uint256 wellAmount = vault.getAmountWellOut(purchaseAmount);

        deal(address(well), address(this), wellAmount);
        well.approve(address(vault), wellAmount);

        uint256 preVaultBalance = underlying.balanceOf(address(vault));
        uint256 preUserBalance = underlying.balanceOf(address(this));
        uint256 preHolderBalance = well.balanceOf(address(holder));

        uint256 expectedOut = vault.getAmountReservesOut(wellAmount);
        vault.getReserves(wellAmount, expectedOut);

        // Verify balances
        assertEq(
            preVaultBalance - underlying.balanceOf(address(vault)),
            expectedOut,
            "incorrect vault balance decrease"
        );
        assertEq(
            underlying.balanceOf(address(this)) - preUserBalance,
            expectedOut,
            "incorrect user balance increase"
        );
        assertEq(
            well.balanceOf(address(holder)) - preHolderBalance,
            wellAmount,
            "incorrect holder well balance increase"
        );

        // Verify sale is over at next timestamp
        vm.warp(saleEnd);
        vm.expectRevert("ReserveAutomationModule: sale not active");
        vault.getReserves(1e18, 0);
    }
}
