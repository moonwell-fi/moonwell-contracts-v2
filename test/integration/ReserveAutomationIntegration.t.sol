// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

import "@forge-std/Test.sol";

import {ReserveRegistry} from "@protocol/market/ReserveRegistry.sol";
import {AutomationDeploy} from "@protocol/market/AutomationDeploy.sol";
import {ReserveAutomation} from "@protocol/market/ReserveAutomation.sol";
import {ERC20HoldingDeposit} from "@protocol/market/ERC20HoldingDeposit.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract ReserveAutomationLiveIntegrationTest is Test {
    ERC20 public underlying;
    ERC20 public well;

    ReserveAutomation public vault;

    ERC20HoldingDeposit public holder;

    Addresses addresses;

    function setUp() public {
        addresses = new Addresses();

        underlying = ERC20(addresses.getAddress("USDC"));

        uint256 mintAmount = 10 ** 6;

        deal(address(underlying), address(this), mintAmount);

        well = ERC20(addresses.getAddress("xWELL_PROXY"));

        AutomationDeploy deployer = new AutomationDeploy();

        holder = ERC20HoldingDeposit(
            deployer.deployERC20HoldingDeposit(
                address(well),
                addresses.getAddress("TEMPORAL_GOVERNOR")
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
                addresses.getAddress("CHAINLINK_WELL_USD"),
                addresses.getAddress("USDC_ORACLE")
            );

        vault = ReserveAutomation(
            deployer.deployReserveAutomation(
                params,
                addresses.getAddress("TEMPORAL_GOVERNOR")
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
            addresses.getAddress("CHAINLINK_WELL_USD"),
            "incorrect well chainlink feed"
        );
        assertEq(
            vault.reserveChainlinkFeed(),
            addresses.getAddress("USDC_ORACLE"),
            "incorrect reserve chainlink feed"
        );
        assertEq(
            vault.reserveAssetDecimals(),
            ERC20(address(underlying)).decimals(),
            "incorrect reserve asset decimals"
        );

        assertEq(vault.lastBidTime(), 0, "incorrect last bid time");
        assertEq(vault.saleEndTime(), 0, "incorrect sale end time");
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

    function testSwapWellForUSDC() public {
        uint256 usdcAmount = 1000 * 10 ** ERC20(address(underlying)).decimals();
        deal(address(underlying), address(vault), usdcAmount);

        vault.initiateSale();

        assertEq(
            vault.saleEndTime(),
            block.timestamp + 14 days,
            "incorrect sale end time"
        );
        assertEq(
            vault.periodSaleAmount(),
            usdcAmount,
            "incorrect period sale amount"
        );
        assertEq(vault.bufferCap(), usdcAmount, "incorrect buffer cap");
        assertEq(
            vault.rateLimitPerSecond(),
            usdcAmount / 14 days,
            "incorrect rate limit per second"
        );
        assertEq(vault.buffer(), 0, "incorrect initial buffer");

        assertEq(
            vault.currentDiscount(),
            0,
            "incorrect discount post discount decay period"
        );

        vm.warp(block.timestamp + 14 days - 1);

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

        ERC20 weth = ERC20(addresses.getAddress("WETH"));

        ReserveAutomation.InitParams memory params = ReserveAutomation
            .InitParams(
                1e17,
                1 weeks,
                1 days,
                address(holder),
                address(well),
                address(weth),
                addresses.getAddress("CHAINLINK_WELL_USD"),
                addresses.getAddress("ETH_ORACLE")
            );

        ReserveAutomation wethVault = ReserveAutomation(
            deployer.deployReserveAutomation(
                params,
                addresses.getAddress("TEMPORAL_GOVERNOR")
            )
        );

        uint256 wethAmount = 10 * 10 ** ERC20(address(weth)).decimals();
        deal(address(weth), address(wethVault), wethAmount);

        wethVault.initiateSale();

        assertEq(
            wethVault.saleEndTime(),
            block.timestamp + 14 days,
            "incorrect sale end time"
        );
        assertEq(
            wethVault.periodSaleAmount(),
            wethAmount,
            "incorrect period sale amount"
        );
        assertEq(wethVault.bufferCap(), wethAmount, "incorrect buffer cap");
        assertEq(
            wethVault.rateLimitPerSecond(),
            wethAmount / 14 days,
            "incorrect rate limit per second"
        );
        assertEq(wethVault.buffer(), 0, "incorrect initial buffer");

        assertEq(
            wethVault.currentDiscount(),
            0,
            "incorrect discount post discount decay period"
        );

        vm.warp(block.timestamp + 14 days - 1);

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

        vault.initiateSale();

        assertEq(
            vault.saleEndTime(),
            block.timestamp + 14 days,
            "incorrect sale end time"
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

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
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

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
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

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
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

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
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
