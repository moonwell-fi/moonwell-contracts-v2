// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Test} from "@forge-std/Test.sol";
import {console} from "@forge-std/console.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {AutomationDeploy} from "@protocol/market/AutomationDeploy.sol";
import {ReserveAutomation} from "@protocol/market/ReserveAutomation.sol";
import {ERC20HoldingDeposit} from "@protocol/market/ERC20HoldingDeposit.sol";
import {ReserveAutomationDeploy} from "@proposals/mips/mip-reserve-automation/reserveAutomationDeploy.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract ReserveAutomationDeployIntegrationTest is ReserveAutomationDeploy {
    event ERC20Withdrawn(
        address indexed tokenAddress,
        address indexed to,
        uint256 amount
    );

    ERC20HoldingDeposit public holder;
    ERC20 public well;
    address public guardian;

    uint256 public constant SALE_WINDOW = 14 days;

    function setUp() public override {
        super.setUp();

        // Deploy all contracts
        deploy(addresses);

        // Set up common variables
        well = ERC20(addresses.getAddress("xWELL_PROXY"));
        guardian = addresses.getAddress("PAUSE_GUARDIAN");
        holder = ERC20HoldingDeposit(
            addresses.getAddress("RESERVE_WELL_HOLDING_DEPOSIT")
        );
    }

    function testValidate() public view {
        validate(addresses);
    }

    function _runTestForAllAutomations(
        function(ReserveAutomation, ERC20) internal fn
    ) internal {
        string[] memory mTokens = _getMTokens();
        for (uint256 i = 0; i < mTokens.length; i++) {
            string memory mTokenName = mTokens[i];
            string memory underlyingName = _getUnderlyingName(mTokenName);

            ReserveAutomation automation = ReserveAutomation(
                addresses.getAddress(
                    string.concat(
                        "RESERVE_AUTOMATION_",
                        _stripMoonwellPrefix(mTokenName)
                    )
                )
            );

            ERC20 underlying = ERC20(addresses.getAddress(underlyingName));

            fn(automation, underlying);
        }
    }

    function testSetGuardianRevertNonOwner() public {
        _runTestForAllAutomations(_testSetGuardianRevertNonOwner);
    }

    function _testSetGuardianRevertNonOwner(
        ReserveAutomation vault,
        ERC20
    ) internal {
        vm.expectRevert("Ownable: caller is not the owner");
        vault.setGuardian(address(0x456));
    }

    function testSetGuardianSucceedsOwner() public {
        _runTestForAllAutomations(_testSetGuardianSucceedsOwner);
    }

    function _testSetGuardianSucceedsOwner(
        ReserveAutomation vault,
        ERC20
    ) internal {
        address newGuardian = address(0x456);
        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.setGuardian(newGuardian);
        assertEq(vault.guardian(), newGuardian, "guardian not set correctly");
    }

    function testCancelAuctionRevertNonGuardian() public {
        _runTestForAllAutomations(_testCancelAuctionRevertNonGuardian);
    }

    function _testCancelAuctionRevertNonGuardian(
        ReserveAutomation vault,
        ERC20
    ) internal {
        vm.expectRevert("ReserveAutomationModule: only guardian");
        vault.cancelAuction();
    }

    function testCancelAuctionRevertNoAuction() public {
        _runTestForAllAutomations(_testCancelAuctionRevertNoAuction);
    }

    function _testCancelAuctionRevertNoAuction(
        ReserveAutomation vault,
        ERC20
    ) internal {
        vm.prank(guardian);
        vm.expectRevert(
            "ReserveAutomationModule: auction already active or not initiated"
        );
        vault.cancelAuction();
    }

    function testCancelAuctionRevertAlreadyActive() public {
        _runTestForAllAutomations(_testCancelAuctionRevertAlreadyActive);
    }

    function _testCancelAuctionRevertAlreadyActive(
        ReserveAutomation vault,
        ERC20 underlying
    ) internal {
        uint256 usdcAmount = 1000 * 10 ** underlying.decimals();
        deal(address(underlying), address(vault), usdcAmount);

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(0);

        vm.warp(block.timestamp + 14 days + 1);

        vm.prank(guardian);
        vm.expectRevert(
            "ReserveAutomationModule: auction already active or not initiated"
        );
        vault.cancelAuction();
    }

    function testCancelAuction() public {
        _runTestForAllAutomations(_testCancelAuction);
    }

    function _testCancelAuction(
        ReserveAutomation vault,
        ERC20 underlying
    ) internal {
        uint256 amount = 1000 * 10 ** underlying.decimals();
        deal(address(underlying), address(vault), amount);

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(1 days);

        /// warp forward to prevent interest accrue intermittent failures
        vm.warp(block.timestamp + 1);

        MErc20(vault.mTokenMarket()).accrueInterest();

        uint256 totalReserves = MErc20(vault.mTokenMarket()).totalReserves();

        vm.prank(guardian);
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
            MErc20(vault.mTokenMarket()).totalReserves() - totalReserves,
            amount,
            "total reserves should increase post auction cancel"
        );
    }

    function testInitiateSaleFailsAlreadyActive() public {
        _runTestForAllAutomations(_testInitiateSaleFailsAlreadyActive);
    }

    function _testInitiateSaleFailsAlreadyActive(
        ReserveAutomation vault,
        ERC20 underlying
    ) internal {
        uint256 amount = 1000 * 10 ** underlying.decimals();
        deal(address(underlying), address(vault), amount);

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(1 days);

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectRevert("ReserveAutomationModule: sale already active");
        vault.initiateSale(1 days);
    }

    function testInitiateSaleFailsNoReserves() public {
        _runTestForAllAutomations(_testInitiateSaleFailsNoReserves);
    }

    function _testInitiateSaleFailsNoReserves(
        ReserveAutomation vault,
        ERC20 // solhint-disable-line no-unused-vars
    ) internal {
        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectRevert("ReserveAutomationModule: no reserves to sell");
        vault.initiateSale(1 days);
    }

    function testInitiateSaleFailsExceedsMaxDelay() public {
        _runTestForAllAutomations(_testInitiateSaleFailsExceedsMaxDelay);
    }

    function _testInitiateSaleFailsExceedsMaxDelay(
        ReserveAutomation vault,
        ERC20 underlying
    ) internal {
        uint256 amount = 1000 * 10 ** underlying.decimals();
        deal(address(underlying), address(vault), amount);

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectRevert("ReserveAutomationModule: delay exceeds max");
        vault.initiateSale(14 days + 1);
    }

    function testPurchaseReservesFailsSaleNotActive() public {
        _runTestForAllAutomations(_testPurchaseReservesFailsSaleNotActive);
    }

    function _testPurchaseReservesFailsSaleNotActive(
        ReserveAutomation vault,
        ERC20 underlying
    ) internal {
        vm.expectRevert("ReserveAutomationModule: sale not active");
        vault.getReserves(0, 0);

        uint256 amount = 1000 * 10 ** underlying.decimals();
        deal(address(underlying), address(vault), amount);

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
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
        _runTestForAllAutomations(_testPurchaseReservesFailsZeroAmount);
    }

    function _testPurchaseReservesFailsZeroAmount(
        ReserveAutomation vault,
        ERC20 underlying
    ) internal {
        uint256 amount = 1000 * 10 ** underlying.decimals();
        deal(address(underlying), address(vault), amount);

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(1);

        vm.warp(block.timestamp + 1);

        vm.expectRevert("ReserveAutomationModule: amount in is 0");
        vault.getReserves(0, 0);
    }

    function testPurchaseReservesFailsInsufficientBuffer() public {
        _runTestForAllAutomations(_testPurchaseReservesFailsInsufficientBuffer);
    }

    function _testPurchaseReservesFailsInsufficientBuffer(
        ReserveAutomation vault,
        ERC20 underlying
    ) internal {
        uint256 amount = 1000 * 10 ** underlying.decimals();
        deal(address(underlying), address(vault), amount);

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(1);

        deal(address(well), address(this), 1_000e18);
        well.approve(address(vault), 1_000e18);

        vm.warp(block.timestamp + 1);

        uint256 buyAmount = vault.getAmountWellOut((vault.buffer() * 2));
        vm.expectRevert(
            "ReserveAutomationModule: amount bought exceeds buffer"
        );
        vault.getReserves(buyAmount, 0);

        vm.warp(block.timestamp + 7 days);

        buyAmount = vault.getAmountWellOut(vault.buffer() * 2);
        vm.expectRevert(
            "ReserveAutomationModule: amount bought exceeds buffer"
        );
        vault.getReserves(buyAmount, 0);
    }

    function testPurchaseReservesFailsAmountOutNotGteMinAmtOut() public {
        _runTestForAllAutomations(
            _testPurchaseReservesFailsAmountOutNotGteMinAmtOut
        );
    }

    function _testPurchaseReservesFailsAmountOutNotGteMinAmtOut(
        ReserveAutomation vault,
        ERC20 underlying
    ) internal {
        uint256 amount = 1000 * 10 ** underlying.decimals();
        deal(address(underlying), address(vault), amount);

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(1);

        vm.warp(block.timestamp + 1 days);

        uint256 wellBuyAmount = vault.getAmountWellOut(vault.buffer());

        deal(address(well), address(this), wellBuyAmount);
        well.approve(address(vault), wellBuyAmount);

        uint256 currBuffer = vault.buffer();

        vm.expectRevert("ReserveAutomationModule: not enough out");
        vault.getReserves(wellBuyAmount, currBuffer + 1);
    }

    function testPurchaseReservesFailsNoWellApproval() public {
        _runTestForAllAutomations(_testPurchaseReservesFailsNoWellApproval);
    }

    function _testPurchaseReservesFailsNoWellApproval(
        ReserveAutomation vault,
        ERC20 underlying
    ) internal {
        uint256 amount = 1000 * 10 ** underlying.decimals();
        deal(address(underlying), address(vault), amount);

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(1);

        vm.warp(block.timestamp + 1 days);

        uint256 wellBuyAmount = vault.getAmountWellOut(vault.buffer());

        deal(address(well), address(this), wellBuyAmount);

        vm.expectRevert("ERC20: insufficient allowance");
        vault.getReserves(wellBuyAmount, 1);
    }

    function testSwapWellForReserves() public {
        _runTestForAllAutomations(_testSwapWellForReserves);
    }

    function _testSwapWellForReserves(
        ReserveAutomation vault,
        ERC20 underlying
    ) internal {
        uint256 amount = 1000 * 10 ** underlying.decimals();
        deal(address(underlying), address(vault), amount);

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(0);

        assertEq(
            vault.saleStartTime(),
            block.timestamp,
            "incorrect sale start time"
        );
        assertEq(
            vault.periodSaleAmount(),
            amount,
            "incorrect period sale amount"
        );
        assertEq(vault.bufferCap(), amount, "incorrect buffer cap");
        assertEq(
            vault.rateLimitPerSecond(),
            amount / SALE_WINDOW,
            "incorrect rate limit per second"
        );
        assertEq(vault.buffer(), 0, "incorrect initial buffer");

        assertEq(
            vault.currentDiscount(),
            0,
            "incorrect discount post discount decay period"
        );

        vm.warp(block.timestamp + SALE_WINDOW - 1);

        uint256 wellAmount = vault.getAmountWellOut(vault.buffer());
        deal(address(well), address(this), wellAmount);

        well.approve(address(vault), wellAmount);

        uint256 initialHolderWellBalance = well.balanceOf(address(holder));
        uint256 initialUnderlyingBalance = underlying.balanceOf(address(this));

        uint256 expectedOut = vault.getAmountReservesOut(wellAmount);

        uint256 actualAmountOut = vault.getReserves(wellAmount, expectedOut);

        assertEq(
            well.balanceOf(address(holder)) - initialHolderWellBalance,
            wellAmount,
            "holder well balance did not increase"
        );

        assertEq(
            underlying.balanceOf(address(this)) - initialUnderlyingBalance,
            actualAmountOut,
            "this contract underlying balance did not increase post swap"
        );

        assertEq(
            vault.lastBidTime(),
            block.timestamp,
            "incorrect last bid time"
        );
    }

    function testAmountInTolerance(uint256 amountWellIn) public view {
        string[] memory mTokens = _getMTokens();
        for (uint256 i = 0; i < mTokens.length; i++) {
            string memory mTokenName = mTokens[i];

            ReserveAutomation automation = ReserveAutomation(
                addresses.getAddress(
                    string.concat(
                        "RESERVE_AUTOMATION_",
                        _stripMoonwellPrefix(mTokenName)
                    )
                )
            );

            amountWellIn = bound(
                amountWellIn,
                100e18,
                uint256(type(uint128).max)
            );

            uint256 getAmountReservesOut = automation.getAmountReservesOut(
                amountWellIn
            );
            uint256 getAmountIn = automation.getAmountWellOut(
                getAmountReservesOut
            );

            assertApproxEqRel(
                getAmountIn,
                amountWellIn,
                1.75e14,
                "amount in not within tolerance"
            );
        }
    }

    function testAmountOutTolerance(uint256 amountReservesIn) public view {
        string[] memory mTokens = _getMTokens();
        for (uint256 i = 0; i < mTokens.length; i++) {
            string memory mTokenName = mTokens[i];

            ReserveAutomation vault = ReserveAutomation(
                addresses.getAddress(
                    string.concat(
                        "RESERVE_AUTOMATION_",
                        _stripMoonwellPrefix(mTokenName)
                    )
                )
            );

            amountReservesIn = bound(
                amountReservesIn,
                uint256(1e8),
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
    }
}
