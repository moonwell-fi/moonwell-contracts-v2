// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {CreditLoan} from "@protocol/marketplace/CreditLoan.sol";
import {InitParams, LoanStatus, PaymentSchedule} from "@protocol/marketplace/CreditTypes.sol";

import {Fixture} from "./Fixture.t.sol";

/// Unit tests for CreditLoan.makePayment and the accompanying view helpers
/// (nextPaymentDueAt, remainingPayments, totalOwedNow, collateralRemaining).
/// Stands up a CreditLoan directly (bypassing the factory + Clones.clone
/// path already covered by PR5) so we control schedule fields precisely
/// and mock Moonwell's enterMarkets / borrow as we did in PR4.
contract MakePaymentTest is Fixture {
    event InterestPaid(uint32 indexed cursor, uint256 amount);

    bytes4 internal constant ENTER_MARKETS_SEL =
        bytes4(keccak256("enterMarkets(address[])"));
    bytes4 internal constant BORROW_SEL = bytes4(keccak256("borrow(uint256)"));

    uint32 internal constant NUM_INTEREST = 4;
    uint32 internal constant INTERVAL = 7 days;
    uint256 internal constant PRINCIPAL = 400e6;
    uint256 internal constant INTEREST_AMT = 10e6;
    uint256 internal constant FINAL_AMT = PRINCIPAL + INTEREST_AMT;
    uint32 internal constant GRACE = 1 days;

    CreditLoan internal clone;
    uint64 internal firstDueAt;
    uint64 internal principalDueAt;

    function setUp() public override {
        super.setUp();
        clone = new CreditLoan();
        firstDueAt = uint64(block.timestamp + INTERVAL);
        principalDueAt =
            firstDueAt +
            uint64(INTERVAL) *
            (NUM_INTEREST - 1) +
            uint64(INTERVAL);

        InitParams memory p = _defaultParams();
        vm.prank(address(factory));
        clone.initialize(p);

        _mockMoonwellSuccess();

        vm.prank(address(factory));
        clone.activate();

        // Borrower funding + approval.
        deal(usdc, borrower, 10_000e6);
        vm.prank(borrower);
        IERC20(usdc).approve(address(clone), type(uint256).max);
    }

    // ─── helpers ─────────────────────────────────────────────────────

    function _defaultParams() internal view returns (InitParams memory p) {
        p.lender = lender;
        p.borrower = borrower;
        p.mToken = mUsdc;
        p.mTokenAmount = 1_000e6;
        p.principalToken = usdc;
        p.principal = PRINCIPAL;
        p.collateralToken = cbbtc;
        p.collateralAmount = 1e7;
        p.apr = 800;
        p.term = 30 days;
        p.schedule = PaymentSchedule({
            numInterestPayments: NUM_INTEREST,
            intervalSeconds: INTERVAL,
            firstInterestDueAt: firstDueAt,
            principalDueAt: principalDueAt,
            interestAmountPerPayment: INTEREST_AMT,
            finalPaymentAmount: FINAL_AMT
        });
        p.gracePeriod = GRACE;
        p.overSeizureBps = 2_000;
        p.consecutiveMissesForDefault = 2;
        p.marketplaceFeeBps = 500;
        p.feeRecipient = feeRecipient;
        p.comptrollerAddr = unitroller;
        p.stalenessWindow = 3_600;
    }

    function _mockMoonwellSuccess() internal {
        uint256[] memory errs = new uint256[](1);
        vm.mockCall(
            unitroller,
            abi.encodeWithSelector(ENTER_MARKETS_SEL),
            abi.encode(errs)
        );
        vm.mockCall(
            mUsdc,
            abi.encodeWithSelector(BORROW_SEL, PRINCIPAL),
            abi.encode(uint256(0))
        );
        deal(usdc, address(clone), PRINCIPAL);
    }

    // ─── tests ────────────────────────────────────────────────────────

    function test_makePayment_interestHappy() public {
        uint256 borrowerBefore = IERC20(usdc).balanceOf(borrower);
        uint256 cloneBefore = IERC20(usdc).balanceOf(address(clone));

        vm.expectEmit(true, true, true, true, address(clone));
        emit InterestPaid(0, INTEREST_AMT);

        vm.prank(borrower);
        clone.makePayment();

        assertEq(clone.paymentCursor(), 1);
        assertEq(clone.totalInterestPaid(), INTEREST_AMT);
        assertEq(clone.missedCount(), 0);
        assertTrue(clone.status() == LoanStatus.Active);
        assertEq(
            borrowerBefore - IERC20(usdc).balanceOf(borrower),
            INTEREST_AMT
        );
        assertEq(
            IERC20(usdc).balanceOf(address(clone)) - cloneBefore,
            INTEREST_AMT
        );
    }

    function test_makePayment_wrongCallerReverts() public {
        vm.prank(lender);
        vm.expectRevert(CreditLoan.OnlyBorrower.selector);
        clone.makePayment();
    }

    function test_makePayment_beforeActiveReverts() public {
        // Deploy a fresh, unactivated clone.
        CreditLoan fresh = new CreditLoan();
        InitParams memory p = _defaultParams();
        vm.prank(address(factory));
        fresh.initialize(p);

        vm.prank(borrower);
        vm.expectRevert(CreditLoan.LoanNotActive.selector);
        fresh.makePayment();
    }

    function test_makePayment_pastGraceReverts() public {
        // Warp well past the first interest payment's grace period.
        vm.warp(firstDueAt + GRACE + 1);

        vm.prank(borrower);
        vm.expectRevert(CreditLoan.PaymentGraceElapsed.selector);
        clone.makePayment();
    }

    function test_makePayment_withinGraceStillWorks() public {
        // Warp to just after dueAt but within grace.
        vm.warp(firstDueAt + (GRACE - 1));

        vm.prank(borrower);
        clone.makePayment();
        assertEq(clone.paymentCursor(), 1);
    }

    function test_makePayment_multipleSequential() public {
        // Pay cursor 0, 1, 2 in sequence. Warp to each window so we're
        // within grace of each due date.
        for (uint32 i = 0; i < 3; i++) {
            vm.warp(firstDueAt + uint64(i) * INTERVAL);
            vm.prank(borrower);
            clone.makePayment();
        }
        assertEq(clone.paymentCursor(), 3);
        assertEq(clone.totalInterestPaid(), 3 * INTEREST_AMT);
    }

    function test_makePayment_finalPaymentRevertsNotImplementedInPR6() public {
        // Walk through all interest payments first.
        for (uint32 i = 0; i < NUM_INTEREST; i++) {
            vm.warp(firstDueAt + uint64(i) * INTERVAL);
            vm.prank(borrower);
            clone.makePayment();
        }
        assertEq(clone.paymentCursor(), NUM_INTEREST);

        // Now the principal-payment path — _settle is stubbed to revert.
        vm.warp(principalDueAt);
        vm.prank(borrower);
        vm.expectRevert(CreditLoan.NotImplemented.selector);
        clone.makePayment();

        // The whole call rolled back, including the safeTransferFrom —
        // borrower's USDC balance should be untouched by the failed
        // final payment.
        assertEq(clone.paymentCursor(), NUM_INTEREST);
        assertEq(clone.totalPrincipalPaid(), 0);
    }

    function test_makePayment_insufficientAllowanceReverts() public {
        // Revoke allowance.
        vm.prank(borrower);
        IERC20(usdc).approve(address(clone), 0);

        vm.prank(borrower);
        vm.expectRevert(); // SafeERC20 bubbles an allowance revert
        clone.makePayment();
    }

    // ─── view helpers ────────────────────────────────────────────────

    function test_nextPaymentDueAt_interestPhase() public view {
        assertEq(clone.nextPaymentDueAt(), firstDueAt);
    }

    function test_nextPaymentDueAt_returnsPrincipalDueOnFinalStep() public {
        for (uint32 i = 0; i < NUM_INTEREST; i++) {
            vm.warp(firstDueAt + uint64(i) * INTERVAL);
            vm.prank(borrower);
            clone.makePayment();
        }
        assertEq(clone.nextPaymentDueAt(), principalDueAt);
    }

    function test_nextPaymentDueAt_zeroWhenNotActive() public {
        CreditLoan fresh = new CreditLoan();
        InitParams memory p = _defaultParams();
        vm.prank(address(factory));
        fresh.initialize(p);
        assertEq(fresh.nextPaymentDueAt(), 0);
    }

    function test_remainingPayments_countsDownCorrectly() public {
        assertEq(clone.remainingPayments(), NUM_INTEREST + 1);
        vm.prank(borrower);
        clone.makePayment();
        assertEq(clone.remainingPayments(), NUM_INTEREST);
    }

    function test_totalOwedNow_reflectsProgress() public {
        (uint256 pDue, uint256 iDue) = clone.totalOwedNow();
        assertEq(pDue, FINAL_AMT);
        assertEq(iDue, NUM_INTEREST * INTEREST_AMT);

        vm.prank(borrower);
        clone.makePayment();
        (pDue, iDue) = clone.totalOwedNow();
        assertEq(pDue, FINAL_AMT);
        assertEq(iDue, (NUM_INTEREST - 1) * INTEREST_AMT);
    }

    function test_collateralRemaining_equalsInitiallyFull() public view {
        assertEq(clone.collateralRemaining(), 1e7);
    }
}
