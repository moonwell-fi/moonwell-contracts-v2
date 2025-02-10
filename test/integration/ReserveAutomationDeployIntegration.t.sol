// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {console} from "@forge-std/console.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Test} from "@forge-std/Test.sol";

import "@utils/ChainIds.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {AutomationDeploy} from "@protocol/market/AutomationDeploy.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {ReserveAutomation} from "@protocol/market/ReserveAutomation.sol";
import {ERC20HoldingDeposit} from "@protocol/market/ERC20HoldingDeposit.sol";
import {ReserveAutomationDeploy} from "@proposals/mips/mip-reserve-automation/reserveAutomationDeploy.sol";
import {MockRedstoneMultiFeedAdapter} from "@test/mock/MockRedstoneMultiFeedAdapter.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract ReserveAutomationLiveSystemIntegrationTest is
    ReserveAutomationDeploy,
    PostProposalCheck
{
    event ERC20Withdrawn(
        address indexed tokenAddress,
        address indexed to,
        uint256 amount
    );

    ERC20HoldingDeposit public holder;
    ERC20 public well;
    address public guardian;

    uint256 public constant SALE_WINDOW = 14 days;
    uint256 public constant MINI_AUCTION_PERIOD = 4 hours;
    uint256 public constant MAX_DISCOUNT = 9e17; // 90% == 10% discount
    uint256 public constant STARTING_PREMIUM = 11e17; // 110% == 10% premium

    function setUp()
        public
        override(PostProposalCheck, ReserveAutomationDeploy)
    {
        PostProposalCheck.setUp();

        vm.selectFork(BASE_FORK_ID);

        // warp forward 100 seconds for good measure
        vm.warp(proposalStartTime + 100);

        // mock redstone internal call to avoid stale price error (we cannot warp more than 30 hours to the future)
        MockRedstoneMultiFeedAdapter redstoneMock = new MockRedstoneMultiFeedAdapter();

        vm.etch(
            0xf030a9ad2707c6C628f58372Fa3B355264417f56,
            address(redstoneMock).code
        );

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
        string[] memory mTokens = _getMTokens(block.chainid);

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

            ERC20 underlying = ERC20(
                MErc20(addresses.getAddress(mTokenName)).underlying()
            );

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
        vm.warp(block.timestamp + 30 days);

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

    function testCancelAuction() public {
        vm.warp(block.timestamp + 30 days);

        _runTestForAllAutomations(_testCancelAuction);
    }

    function _testCancelAuction(
        ReserveAutomation vault,
        ERC20 underlying
    ) internal {
        uint256 amount = 1000 * 10 ** underlying.decimals();
        deal(address(underlying), address(vault), amount);

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(
            1 days,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        /// warp forward to prevent interest accrue intermittent failures
        vm.warp(block.timestamp + 100);

        MErc20(vault.mTokenMarket()).accrueInterest();

        uint256 totalReserves = MErc20(vault.mTokenMarket()).totalReserves();

        vm.prank(guardian);
        vault.cancelAuction();

        assertEq(vault.saleStartTime(), 0, "sale start time not reset");
        assertEq(vault.periodSaleAmount(), 0, "period sale amount not reset");
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
        vm.warp(block.timestamp + 30 days);

        _runTestForAllAutomations(_testInitiateSaleFailsAlreadyActive);
    }

    function _testInitiateSaleFailsAlreadyActive(
        ReserveAutomation vault,
        ERC20 underlying
    ) internal {
        uint256 amount = 1000 * 10 ** underlying.decimals();
        deal(address(underlying), address(vault), amount);

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(
            1 days,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
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
        vm.warp(block.timestamp + 30 days);

        _runTestForAllAutomations(_testInitiateSaleFailsNoReserves);
    }

    function _testInitiateSaleFailsNoReserves(
        ReserveAutomation vault,
        ERC20 underlying
    ) internal {
        deal(address(underlying), address(vault), 0);
        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
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
        vm.warp(block.timestamp + 30 days);
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
        vault.initiateSale(
            28 days + 1,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );
    }

    function testPurchaseReservesFailsSaleNotActive() public {
        vm.warp(block.timestamp + 30 days);
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

        vm.warp(block.timestamp + SALE_WINDOW);

        vm.expectRevert("ReserveAutomationModule: sale not active");
        vault.getReserves(0, 0);
    }

    function testPurchaseReservesFailsZeroAmount() public {
        vm.warp(block.timestamp + 30 days);
        _runTestForAllAutomations(_testPurchaseReservesFailsZeroAmount);
    }

    function _testPurchaseReservesFailsZeroAmount(
        ReserveAutomation vault,
        ERC20 underlying
    ) internal {
        uint256 amount = 1000 * 10 ** underlying.decimals();
        deal(address(underlying), address(vault), amount);

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
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

    function testPurchaseReservesFailsInsufficientBuffer() public {
        vm.warp(block.timestamp + 30 days);
        _runTestForAllAutomations(_testPurchaseReservesFailsInsufficientBuffer);
    }

    function _testPurchaseReservesFailsInsufficientBuffer(
        ReserveAutomation vault,
        ERC20 underlying
    ) internal {
        uint256 amount = 1000 * 10 ** underlying.decimals();
        deal(address(underlying), address(vault), amount);

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(
            1,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        deal(address(well), address(this), 1_000e18);
        well.approve(address(vault), 1_000e18);

        vm.warp(block.timestamp + 1);

        uint256 remainingReserves = vault.getCurrentPeriodRemainingReserves();
        uint256 buyAmount = vault.getAmountWellOut(remainingReserves * 2);
        vm.expectRevert(
            "ReserveAutomationModule: not enough reserves remaining"
        );
        vault.getReserves(buyAmount, 0);

        vm.warp(block.timestamp + 7 days);

        remainingReserves = vault.getCurrentPeriodRemainingReserves();
        buyAmount = vault.getAmountWellOut(remainingReserves * 2);
        vm.expectRevert(
            "ReserveAutomationModule: not enough reserves remaining"
        );
        vault.getReserves(buyAmount, 0);
    }

    function testPurchaseReservesFailsAmountOutNotGteMinAmtOut() public {
        vm.warp(block.timestamp + 30 days);
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
        vault.initiateSale(
            1,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        vm.warp(block.timestamp + 1 days);

        uint256 remainingReserves = vault.getCurrentPeriodRemainingReserves();
        uint256 wellBuyAmount = vault.getAmountWellOut(remainingReserves);

        deal(address(well), address(this), wellBuyAmount);
        well.approve(address(vault), wellBuyAmount);

        vm.expectRevert("ReserveAutomationModule: not enough out");
        vault.getReserves(wellBuyAmount, remainingReserves + 1);
    }

    function testPurchaseReservesFailsNoWellApproval() public {
        vm.warp(block.timestamp + 30 days);
        _runTestForAllAutomations(_testPurchaseReservesFailsNoWellApproval);
    }

    function _testPurchaseReservesFailsNoWellApproval(
        ReserveAutomation vault,
        ERC20 underlying
    ) internal {
        uint256 amount = 1000 * 10 ** underlying.decimals();
        deal(address(underlying), address(vault), amount);

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(
            1,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        vm.warp(block.timestamp + 1 days);

        uint256 remainingReserves = vault.getCurrentPeriodRemainingReserves();
        uint256 wellBuyAmount = vault.getAmountWellOut(remainingReserves);

        deal(address(well), address(this), wellBuyAmount);

        vm.expectRevert("ERC20: insufficient allowance");
        vault.getReserves(wellBuyAmount, 1);
    }

    function testSwapWellForReserves() public {
        vm.warp(block.timestamp + 30 days);
        _runTestForAllAutomations(_testSwapWellForReserves);
    }

    function _testSwapWellForReserves(
        ReserveAutomation vault,
        ERC20 underlying
    ) internal {
        uint256 amount = 1000 * 10 ** underlying.decimals();
        deal(address(underlying), address(vault), amount);

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
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
            amount / (SALE_WINDOW / MINI_AUCTION_PERIOD),
            "incorrect period sale amount"
        );

        // Move to middle of period to test discount
        vm.warp(block.timestamp + MINI_AUCTION_PERIOD / 2);

        uint256 wellAmount = vault.getAmountWellOut(
            vault.getCurrentPeriodRemainingReserves()
        );
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
    }

    function testAmountInTolerance(uint256 amountWellIn) public view {
        string[] memory mTokens = _getMTokens(block.chainid);
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
                3e14,
                "amount in not within tolerance"
            );
        }
    }

    function testAmountOutTolerance(uint256 amountReservesIn) public view {
        string[] memory mTokens = _getMTokens(block.chainid);
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

    uint8 private _cacheCallCount = 0;

    function _testPriceCachingBehavior(
        ReserveAutomation vault,
        ERC20 underlying
    ) internal {
        uint256 amount = 1000 * 10 ** underlying.decimals();
        deal(address(underlying), address(vault), amount);

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vault.initiateSale(
            0,
            SALE_WINDOW,
            MINI_AUCTION_PERIOD,
            MAX_DISCOUNT,
            STARTING_PREMIUM
        );

        // Move to middle of first period
        vm.warp(block.timestamp + MINI_AUCTION_PERIOD / 2);

        uint256 startingReserves = vault.getCurrentPeriodRemainingReserves();
        // Get initial prices
        uint256 initialWellAmount = vault.getAmountWellOut(startingReserves);

        deal(address(well), address(this), initialWellAmount);
        well.approve(address(vault), initialWellAmount);
        vault.getReserves(initialWellAmount, 0);

        AggregatorV3Interface oracle = AggregatorV3Interface(
            vault.reserveChainlinkFeed()
        );

        uint8 decimals = oracle.decimals();
        vm.mockCall(
            vault.reserveChainlinkFeed(),
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(
                1,
                (3 + _cacheCallCount++) * 10 ** decimals,
                block.timestamp,
                block.timestamp,
                1
            )
        );

        // Get amount after price change - should be same since prices are cached
        uint256 wellAmountAfterPriceChange = vault.getAmountWellOut(
            startingReserves
        );
        assertEq(
            initialWellAmount,
            wellAmountAfterPriceChange,
            "WELL amount changed after oracle price update"
        );

        // Move to next period
        vm.warp(block.timestamp + MINI_AUCTION_PERIOD);

        // Get amount in new period - should reflect new prices
        uint256 wellAmountNewPeriod = vault.getAmountWellOut(
            vault.getCurrentPeriodRemainingReserves()
        );
        assertNotEq(
            wellAmountNewPeriod,
            initialWellAmount,
            "WELL amount should not be the same in the new period as prices should have changed drastically"
        );
    }

    function testPriceCachingBehavior() public {
        vm.warp(block.timestamp + 30 days);
        _runTestForAllAutomations(_testPriceCachingBehavior);
    }

    function _testUpperLowerBoundsPremiumDiscount(
        ReserveAutomation vault,
        ERC20
    ) internal view {
        /// no checks to run if the sale has not started or not scheduled to start
        if (vault.saleStartTime() == 0) {
            return;
        }

        assertTrue(vault.maxDiscount() >= 0.8e18, "max discount under 80%");
        assertTrue(
            vault.startingPremium() <= 1.2e18,
            "starting premium over 120%"
        );
        assertTrue(
            vault.startingPremium() - vault.maxDiscount() <= 0.5e18,
            "decay delta gt 50%"
        );
    }

    function testUpperLowerBoundsPremiumDiscount() public {
        _runTestForAllAutomations(_testUpperLowerBoundsPremiumDiscount);
    }
}
