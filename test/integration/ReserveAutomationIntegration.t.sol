// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

import "@forge-std/Test.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {AutomationDeploy} from "@protocol/market/AutomationDeploy.sol";
import {MockERC20Decimals} from "@test/mock/MockERC20Decimals.sol";
import {ReserveAutomation} from "@protocol/market/ReserveAutomation.sol";
import {ERC20HoldingDeposit} from "@protocol/market/ERC20HoldingDeposit.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract ReserveAutomationLiveIntegrationTest is Test {
    ERC20 public underlying;
    ERC20 public well;

    ReserveAutomation public vault;
    MErc20 public mToken;

    ERC20HoldingDeposit public holder;

    Addresses private _addresses;

    address private _guardian;

    uint256 public constant SALE_WINDOW = 14 days;

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
            .InitParams(
                1e17,
                /// 1 week discount decay period
                1 weeks,
                /// 1 day non-discount period
                1 days,
                address(holder),
                address(well),
                address(underlying),
                _addresses.getAddress("CHAINLINK_WELL_USD"),
                _addresses.getAddress("USDC_ORACLE")
            );

        vault = ReserveAutomation(
            deployer.deployReserveAutomation(
                params,
                _addresses.getAddress("TEMPORAL_GOVERNOR"),
                address(mToken),
                _guardian
            )
        );
    }

    function testSetup() public view {
        assertEq(vault.maxDiscount(), 1e17, "incorrect max discount");
        assertEq(
            vault.discountDecayPeriod(),
            1 weeks,
            "incorrect discount decay period"
        );
        assertEq(
            vault.nonDiscountPeriod(),
            1 days,
            "incorrect non discount period"
        );
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

        assertEq(vault.lastBidTime(), 0, "incorrect last bid time");
        assertEq(vault.saleStartTime(), 0, "incorrect sale start time");
        assertEq(vault.periodSaleAmount(), 0, "incorrect period sale amount");
        assertEq(vault.buffer(), 0, "incorrect buffer");
        assertEq(vault.bufferCap(), 0, "incorrect buffer cap");
        assertEq(
            vault.rateLimitPerSecond(),
            0,
            "incorrect rate limit per second"
        );

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
            .InitParams(
                1e17,
                1 weeks,
                1 days,
                address(holder),
                address(well),
                address(mockUnderlying),
                _addresses.getAddress("CHAINLINK_WELL_USD"),
                _addresses.getAddress("USDC_ORACLE")
            );

        address governor = _addresses.getAddress("TEMPORAL_GOVERNOR");

        vm.expectRevert(
            "ReserveAutomationModule: reserve asset has too many decimals"
        );
        ReserveAutomation(
            deployer.deployReserveAutomation(
                params,
                governor,
                address(mToken),
                _guardian
            )
        );
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

    function testCancelAuctionRevertNoAuction() public {
        vm.prank(_guardian);
        vm.expectRevert(
            "ReserveAutomationModule: auction already active or not initiated"
        );
        vault.cancelAuction();
    }

    function testCancelAuctionRevertAlreadyActive() public {
        uint256 usdcAmount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(0);

        vm.warp(block.timestamp + 14 days + 1);

        vm.prank(_guardian);
        vm.expectRevert(
            "ReserveAutomationModule: auction already active or not initiated"
        );
        vault.cancelAuction();
    }

    function testCancelAuction() public {
        uint256 usdcAmount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(1 days);

        mToken.accrueInterest();

        uint256 totalReserves = mToken.totalReserves();

        vm.prank(_guardian);
        vault.cancelAuction();

        assertEq(vault.guardian(), address(0), "guardian not revoked");
        assertEq(vault.saleStartTime(), 0, "sale start time not reset");
        assertEq(vault.periodSaleAmount(), 0, "period sale amount not reset");
        assertEq(vault.lastBidTime(), 0, "last bid time not reset");
        assertEq(vault.buffer(), 0, "buffer not reset");
        assertEq(vault.bufferCap(), 0, "buffer cap not reset");
        assertEq(vault.rateLimitPerSecond(), 0, "rate limit not reset");
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
        vault.initiateSale(1 days);

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
        vault.initiateSale(1 days);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectRevert("ReserveAutomationModule: sale already active");
        vault.initiateSale(1 days);
    }

    function testInitiateSaleFailsNoReserves() public {
        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectRevert("ReserveAutomationModule: no reserves to sell");
        vault.initiateSale(1 days);
    }

    function testInitiateSaleFailsExceedsMaxDelay() public {
        uint256 usdcAmount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectRevert("ReserveAutomationModule: delay exceeds max");
        vault.initiateSale(14 days + 1);
    }

    function testPurchaseReservesFailsSaleNotActive() public {
        vm.expectRevert("ReserveAutomationModule: sale not active");
        vault.getReserves(0, 0);

        uint256 usdcAmount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(1);

        vm.expectRevert("ReserveAutomationModule: sale not active");
        vault.getReserves(0, 0);

        deal(address(well), address(this), 1_000e18);
        well.approve(address(vault), 1_000e18);

        vm.warp(block.timestamp + 1);
        vault.getReserves(1, 0);

        vm.warp(block.timestamp + vault.SALE_WINDOW());

        vm.expectRevert("ReserveAutomationModule: sale not active");
        vault.getReserves(0, 0);
    }

    function testPurchaseReservesFailsZeroAmount() public {
        uint256 usdcAmount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(1);

        vm.warp(block.timestamp + 1);

        vm.expectRevert("ReserveAutomationModule: amount in is 0");
        vault.getReserves(0, 0);
    }

    function testSwapWellForUSDC() public {
        uint256 usdcAmount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(0);

        assertEq(
            vault.saleStartTime(),
            block.timestamp,
            "incorrect sale start time"
        );
        assertEq(
            vault.periodSaleAmount(),
            usdcAmount,
            "incorrect period sale amount"
        );
        assertEq(vault.bufferCap(), usdcAmount, "incorrect buffer cap");
        assertEq(
            vault.rateLimitPerSecond(),
            usdcAmount / SALE_WINDOW,
            "incorrect rate limit per second"
        );
        assertEq(vault.buffer(), 0, "incorrect initial buffer");

        assertEq(
            vault.currentDiscount(),
            0,
            "incorrect discount post discount decay period"
        );

        vm.warp(block.timestamp + SALE_WINDOW - 1);

        uint256 wellAmount = vault.getAmountWellIn(vault.buffer());
        deal(address(well), address(this), wellAmount);

        well.approve(address(vault), wellAmount);

        uint256 initialHolderWellBalance = well.balanceOf(address(holder));
        uint256 initialUSDCBalance = underlying.balanceOf(address(this));

        uint256 expectedOut = vault.getAmountOut(wellAmount);

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

        assertEq(
            vault.lastBidTime(),
            block.timestamp,
            "incorrect last bid time"
        );
    }

    function testSwapWellForWETH() public {
        AutomationDeploy deployer = new AutomationDeploy();

        ERC20 weth = ERC20(_addresses.getAddress("WETH"));

        ReserveAutomation.InitParams memory params = ReserveAutomation
            .InitParams(
                1e17,
                1 weeks,
                1 days,
                address(holder),
                address(well),
                address(weth),
                _addresses.getAddress("CHAINLINK_WELL_USD"),
                _addresses.getAddress("ETH_ORACLE")
            );

        ReserveAutomation wethVault = ReserveAutomation(
            deployer.deployReserveAutomation(
                params,
                _addresses.getAddress("TEMPORAL_GOVERNOR"),
                address(mToken),
                _guardian
            )
        );

        uint256 wethAmount = 10 * 10 ** ERC20(address(weth)).decimals();
        deal(address(weth), address(wethVault), wethAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        wethVault.initiateSale(0);

        assertEq(
            wethVault.saleStartTime(),
            block.timestamp,
            "incorrect sale start time"
        );
        assertEq(
            wethVault.periodSaleAmount(),
            wethAmount,
            "incorrect period sale amount"
        );
        assertEq(wethVault.bufferCap(), wethAmount, "incorrect buffer cap");
        assertEq(
            wethVault.rateLimitPerSecond(),
            wethAmount / SALE_WINDOW,
            "incorrect rate limit per second"
        );
        assertEq(wethVault.buffer(), 0, "incorrect initial buffer");

        assertEq(
            wethVault.currentDiscount(),
            0,
            "incorrect discount post discount decay period"
        );

        vm.warp(block.timestamp + SALE_WINDOW - 1);

        uint256 wellAmount = wethVault.getAmountWellIn(wethVault.buffer());
        deal(address(well), address(this), wellAmount);

        well.approve(address(wethVault), wellAmount);

        uint256 initialHolderWellBalance = holder.balance();
        uint256 initialWETHBalance = weth.balanceOf(address(this));

        uint256 expectedOut = wethVault.getAmountOut(wellAmount);

        uint256 actualAmountOut = wethVault.getReserves(
            wellAmount,
            expectedOut
        );

        assertEq(
            holder.balance() - initialHolderWellBalance,
            wellAmount,
            "holder well balance did not increase"
        );

        assertEq(
            weth.balanceOf(address(this)) - initialWETHBalance,
            actualAmountOut,
            "this contract weth balance did not increase post swap"
        );

        assertEq(
            wethVault.lastBidTime(),
            block.timestamp,
            "incorrect last bid time"
        );
    }

    function testFuzzDiscountCalculation(uint256 timeElapsed) public {
        uint256 usdcAmount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(0);

        assertEq(
            vault.saleStartTime(),
            block.timestamp,
            "incorrect sale start time"
        );
        assertEq(
            vault.lastBidTime(),
            block.timestamp,
            "incorrect last bid time"
        );

        timeElapsed = bound(timeElapsed, 1, 2 weeks - 1);

        vm.warp(block.timestamp + timeElapsed);

        uint256 expectedDiscount;
        uint256 nonDiscountPeriod = vault.nonDiscountPeriod();

        if (timeElapsed <= nonDiscountPeriod) {
            expectedDiscount = 0;
        } else {
            uint256 discountTime = timeElapsed - nonDiscountPeriod;
            if (discountTime >= vault.discountDecayPeriod()) {
                expectedDiscount = vault.maxDiscount();
            } else {
                expectedDiscount =
                    (vault.maxDiscount() * discountTime) /
                    vault.discountDecayPeriod();
            }
        }

        assertEq(
            vault.currentDiscount(),
            expectedDiscount,
            "incorrect discount calculation"
        );
    }

    function testSetMaxDiscountRevertNonOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vault.setMaxDiscount(5e16);
    }

    function testSetMaxDiscount() public {
        uint256 newMaxDiscount = 5e16;
        uint256 oldMaxDiscount = vault.maxDiscount();

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.setMaxDiscount(newMaxDiscount);

        assertEq(
            vault.maxDiscount(),
            newMaxDiscount,
            "max discount not updated"
        );
        assertTrue(
            oldMaxDiscount != newMaxDiscount,
            "max discount should have changed"
        );
    }

    function testSetNonDiscountPeriodRevertNonOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vault.setNonDiscountPeriod(2 days);
    }

    function testSetNonDiscountPeriod() public {
        uint256 newNonDiscountPeriod = 2 days;
        uint256 oldNonDiscountPeriod = vault.nonDiscountPeriod();

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.setNonDiscountPeriod(newNonDiscountPeriod);

        assertEq(
            vault.nonDiscountPeriod(),
            newNonDiscountPeriod,
            "non discount period not updated"
        );
        assertTrue(
            oldNonDiscountPeriod != newNonDiscountPeriod,
            "non discount period should have changed"
        );
    }

    function testSetDecayWindowRevertNonOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vault.setDecayWindow(2 weeks);
    }

    function testSetDecayWindow() public {
        uint256 newDecayWindow = 2 weeks;
        uint256 oldDecayWindow = vault.discountDecayPeriod();

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.setDecayWindow(newDecayWindow);

        assertEq(
            vault.discountDecayPeriod(),
            newDecayWindow,
            "decay window not updated"
        );
        assertTrue(
            oldDecayWindow != newDecayWindow,
            "decay window should have changed"
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
}
