// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

import {CreditLoan} from "@protocol/marketplace/CreditLoan.sol";
import {InitParams, LoanStatus, PaymentSchedule} from "@protocol/marketplace/CreditTypes.sol";

import {Fixture} from "./Fixture.t.sol";

/// Stateful MToken mock: behaves like an ERC20 mToken receipt token AND
/// tracks Moonwell borrow balance. borrow() and repayBorrowBehalf()
/// actually move underlying between caller and this contract's pool so
/// tests can verify accounting end-to-end.
contract MockSettleMToken is ERC20 {
    address public immutable underlying;
    mapping(address => uint256) public borrowOf;

    constructor(address _underlying) ERC20("MockSettle", "mSET") {
        underlying = _underlying;
    }

    function mintTo(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function borrow(uint256 amount) external returns (uint256) {
        borrowOf[msg.sender] += amount;
        IERC20(underlying).transfer(msg.sender, amount);
        return 0;
    }

    function borrowBalanceCurrent(
        address account
    ) external view returns (uint256) {
        return borrowOf[account];
    }

    function borrowBalanceStored(
        address account
    ) external view returns (uint256) {
        return borrowOf[account];
    }

    function borrowRatePerTimestamp() external pure returns (uint256) {
        return 0;
    }

    /// Honors Moonwell's type(uint).max full-repay sentinel.
    function repayBorrowBehalf(
        address borrower_,
        uint256 repayAmount
    ) external returns (uint256) {
        uint256 owed = borrowOf[borrower_];
        uint256 actual = repayAmount > owed ? owed : repayAmount;
        if (actual > 0) {
            IERC20(underlying).transferFrom(msg.sender, address(this), actual);
            borrowOf[borrower_] = owed - actual;
        }
        return 0;
    }
}

contract MockFeed {
    int256 public immutable answer;
    uint8 internal immutable _decimals;
    constructor(int256 _a, uint8 d) {
        answer = _a;
        _decimals = d;
    }
    function decimals() external view returns (uint8) {
        return _decimals;
    }
    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (0, answer, 0, block.timestamp, 0);
    }
}

contract SettleTest is Fixture {
    event LoanSettled();
    event DefaultSeized(uint256 amount);
    event LenderReimbursed(uint256 mTokenAmount);

    bytes4 internal constant ENTER_MARKETS_SEL =
        bytes4(keccak256("enterMarkets(address[])"));

    uint32 internal constant NUM_INTEREST = 4;
    uint32 internal constant INTERVAL = 7 days;
    uint256 internal constant PRINCIPAL = 400e6;
    uint256 internal constant INTEREST_AMT = 10e6;
    uint256 internal constant FINAL_AMT = PRINCIPAL + INTEREST_AMT;
    uint256 internal constant M_TOKEN_AMOUNT = 1_000e6;
    uint256 internal constant COLLATERAL_AMOUNT = 1e7;
    uint32 internal constant GRACE = 1 days;
    uint16 internal constant FEE_BPS = 500; // 5%
    uint16 internal constant CONSECUTIVE_MISSES_FOR_DEFAULT = 2;

    CreditLoan internal clone;
    MockSettleMToken internal mockMToken;
    MockFeed internal feed;
    uint64 internal firstDueAt;
    uint64 internal principalDueAt;

    function setUp() public override {
        super.setUp();

        mockMToken = new MockSettleMToken(usdc);
        feed = new MockFeed(1e13, 8);

        firstDueAt = uint64(block.timestamp + INTERVAL);
        principalDueAt = firstDueAt + uint64(INTERVAL) * NUM_INTEREST;

        clone = new CreditLoan();
        vm.prank(address(factory));
        clone.initialize(_defaultParams());

        // Mock comptroller.enterMarkets; the borrow call goes through
        // MockSettleMToken which handles borrowOf bookkeeping.
        uint256[] memory errs = new uint256[](1);
        vm.mockCall(
            unitroller,
            abi.encodeWithSelector(ENTER_MARKETS_SEL),
            abi.encode(errs)
        );

        // Fund the mToken's underlying pool so borrow() can transfer USDC.
        deal(usdc, address(mockMToken), PRINCIPAL * 10);

        // Seed lender's mTokens in the clone (simulates the
        // safeTransferFrom that PR5's factory does).
        mockMToken.mintTo(address(clone), M_TOKEN_AMOUNT);
        // Seed borrower collateral in the clone.
        deal(cbbtc, address(clone), COLLATERAL_AMOUNT);

        vm.prank(address(factory));
        clone.activate();

        // Borrower funding + approval for payments.
        deal(usdc, borrower, 10_000e6);
        vm.prank(borrower);
        IERC20(usdc).approve(address(clone), type(uint256).max);
    }

    function _defaultParams() internal view returns (InitParams memory p) {
        p.lender = lender;
        p.borrower = borrower;
        p.mToken = address(mockMToken);
        p.mTokenAmount = M_TOKEN_AMOUNT;
        p.principalToken = usdc;
        p.principal = PRINCIPAL;
        p.collateralToken = cbbtc;
        p.collateralChainlinkFeed = AggregatorV3Interface(address(feed));
        p.principalChainlinkFeed = AggregatorV3Interface(address(feed));
        p.collateralAmount = COLLATERAL_AMOUNT;
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
        p.consecutiveMissesForDefault = CONSECUTIVE_MISSES_FOR_DEFAULT;
        p.marketplaceFeeBps = FEE_BPS;
        p.feeRecipient = feeRecipient;
        p.comptrollerAddr = unitroller;
        p.collateralFeedStaleness = 3_600;
        p.principalFeedStaleness = 3_600;
    }

    function _payAllInterest() internal {
        for (uint32 i = 0; i < NUM_INTEREST; i++) {
            vm.warp(firstDueAt + uint64(i) * INTERVAL);
            vm.prank(borrower);
            clone.makePayment();
        }
    }

    function _warpPastGrace(uint32 cursor) internal {
        uint64 dueAt = firstDueAt + uint64(cursor) * INTERVAL;
        vm.warp(dueAt + GRACE + 1);
    }

    // ─── _settle (via makePayment final step) ────────────────────────

    function test_settle_happyPath() public {
        _payAllInterest();
        vm.warp(firstDueAt + uint64(NUM_INTEREST - 1) * INTERVAL + 1);

        uint256 lenderUsdcBefore = IERC20(usdc).balanceOf(lender);
        uint256 lenderMBefore = IERC20(address(mockMToken)).balanceOf(lender);
        uint256 feeRecipientBefore = IERC20(usdc).balanceOf(feeRecipient);
        uint256 borrowerCollateralBefore = IERC20(cbbtc).balanceOf(borrower);

        vm.expectEmit(true, true, true, true, address(clone));
        emit LoanSettled();

        vm.prank(borrower);
        clone.makePayment();

        assertTrue(clone.status() == LoanStatus.Settled);

        // Moonwell borrow zeroed.
        assertEq(mockMToken.borrowOf(address(clone)), 0);

        // Fee split: totalInterestPaid = 4 × 10 + 10 = 50 USDC,
        // fee = 50 × 5% = 2.5 USDC, lender = 47.5 USDC.
        uint256 totalInterest = NUM_INTEREST * INTEREST_AMT + INTEREST_AMT;
        uint256 fee = (totalInterest * FEE_BPS) / 10_000;
        uint256 lenderInterest = totalInterest - fee;

        assertEq(
            IERC20(usdc).balanceOf(feeRecipient) - feeRecipientBefore,
            fee
        );
        assertEq(
            IERC20(usdc).balanceOf(lender) - lenderUsdcBefore,
            lenderInterest
        );
        assertEq(
            IERC20(address(mockMToken)).balanceOf(lender) - lenderMBefore,
            M_TOKEN_AMOUNT
        );
        assertEq(
            IERC20(cbbtc).balanceOf(borrower) - borrowerCollateralBefore,
            COLLATERAL_AMOUNT
        );
        // Clone drained except for any rounding leftover.
        assertEq(IERC20(address(mockMToken)).balanceOf(address(clone)), 0);
        assertEq(IERC20(cbbtc).balanceOf(address(clone)), 0);
    }

    function test_settle_insufficientPrincipalReverts() public {
        _payAllInterest();

        // Drain the clone's USDC before the final payment so selfBal <
        // borrowBal. We attack the state directly (no factory path
        // exists for this otherwise).
        uint256 stash = IERC20(usdc).balanceOf(address(clone));
        vm.prank(address(clone));
        IERC20(usdc).transfer(makeAddr("drainer"), stash);

        vm.warp(firstDueAt + uint64(NUM_INTEREST - 1) * INTERVAL + 1);
        // The borrower's final-payment transferFrom will still move
        // FINAL_AMT into the clone, but that's less than PRINCIPAL
        // (mockMToken.borrowOf == PRINCIPAL from activate), so the
        // pre-flight check trips.
        //
        // Fix: also reduce the final payment amount in this test by
        // adjusting the schedule — but we can't change schedule after
        // init. Instead bump borrowBalance on the mock to something
        // larger than FINAL_AMT + stash to force the check.
        //
        // Simpler: mock borrowBalanceCurrent to return a huge value.
        uint256 huge = 10_000_000e6;
        vm.mockCall(
            address(mockMToken),
            abi.encodeWithSelector(
                MockSettleMToken.borrowBalanceCurrent.selector,
                address(clone)
            ),
            abi.encode(huge)
        );

        vm.prank(borrower);
        vm.expectRevert();
        clone.makePayment();
    }

    // ─── forceDefault ────────────────────────────────────────────────

    /// Lender escape hatch: borrower paid all interest on time but the
    /// final payment can't settle (Moonwell APR drift, etc). Without
    /// forceDefault the loan is stuck Active forever.
    function test_forceDefault_afterPrincipalGraceElapsed() public {
        // Pay all interest on time so we land at cursor == numInterestPayments
        // with status still Active.
        _payAllInterest();
        assertEq(clone.paymentCursor(), NUM_INTEREST);
        assertTrue(clone.status() == LoanStatus.Active);

        vm.warp(principalDueAt + GRACE + 1);
        vm.prank(lender);
        clone.forceDefault();

        assertTrue(clone.status() == LoanStatus.Defaulted);
    }

    function test_forceDefault_beforePrincipalGraceReverts() public {
        _payAllInterest();
        vm.warp(principalDueAt + GRACE - 1);
        vm.prank(lender);
        vm.expectRevert(CreditLoan.PaymentNotYetMissed.selector);
        clone.forceDefault();
    }

    function test_forceDefault_wrongCallerReverts() public {
        _payAllInterest();
        vm.warp(principalDueAt + GRACE + 1);
        vm.prank(borrower);
        vm.expectRevert(CreditLoan.OnlyLender.selector);
        clone.forceDefault();
    }

    function test_forceDefault_notActiveReverts() public {
        // Loan is Defaulted already; forceDefault should reject.
        _triggerDefault();
        vm.warp(principalDueAt + GRACE + 1);
        vm.prank(lender);
        vm.expectRevert(CreditLoan.LoanNotActive.selector);
        clone.forceDefault();
    }

    // ─── seizeAll ────────────────────────────────────────────────────

    function _triggerDefault() internal {
        _warpPastGrace(0);
        clone.claimMissedPayment();
        _warpPastGrace(1);
        clone.claimMissedPayment();
        // Now status = Defaulted after the second miss.
        assertTrue(clone.status() == LoanStatus.Defaulted);
    }

    function test_seizeAll_happy() public {
        _triggerDefault();

        uint256 lenderBefore = IERC20(cbbtc).balanceOf(lender);
        uint256 seizedAlready = clone.seizedCollateralAmount();
        uint256 remaining = COLLATERAL_AMOUNT - seizedAlready;

        vm.expectEmit(true, true, true, true, address(clone));
        emit DefaultSeized(remaining);

        vm.prank(lender);
        clone.seizeAll();

        assertTrue(clone.status() == LoanStatus.Closed);
        assertEq(IERC20(cbbtc).balanceOf(lender) - lenderBefore, remaining);
        assertEq(clone.seizedCollateralAmount(), COLLATERAL_AMOUNT);
        assertEq(IERC20(cbbtc).balanceOf(address(clone)), 0);
    }

    function test_seizeAll_notDefaultedReverts() public {
        vm.prank(lender);
        vm.expectRevert(CreditLoan.LoanNotDefaulted.selector);
        clone.seizeAll();
    }

    function test_seizeAll_wrongCallerReverts() public {
        _triggerDefault();
        vm.prank(borrower);
        vm.expectRevert(CreditLoan.OnlyLender.selector);
        clone.seizeAll();
    }

    // ─── repayLoanAfterDefault ──────────────────────────────────────

    function test_repayLoanAfterDefault_happy() public {
        _triggerDefault();
        vm.prank(lender);
        clone.seizeAll();

        // Lender buys USDC off-market and repays the Moonwell borrow.
        uint256 owed = mockMToken.borrowOf(address(clone));
        deal(usdc, lender, owed);
        vm.prank(lender);
        IERC20(usdc).approve(address(clone), owed);

        vm.prank(lender);
        clone.repayLoanAfterDefault(owed);

        assertEq(mockMToken.borrowOf(address(clone)), 0);
    }

    function test_repayLoanAfterDefault_notClosedReverts() public {
        vm.prank(lender);
        vm.expectRevert(CreditLoan.LoanNotClosed.selector);
        clone.repayLoanAfterDefault(1);
    }

    function test_repayLoanAfterDefault_allowsPartial() public {
        _triggerDefault();
        vm.prank(lender);
        clone.seizeAll();

        uint256 half = mockMToken.borrowOf(address(clone)) / 2;
        deal(usdc, lender, half);
        vm.prank(lender);
        IERC20(usdc).approve(address(clone), half);

        vm.prank(lender);
        clone.repayLoanAfterDefault(half);

        // Borrow reduced by half; still non-zero.
        assertTrue(mockMToken.borrowOf(address(clone)) > 0);
    }

    // ─── redeemAndReturn ────────────────────────────────────────────

    function test_redeemAndReturn_happy() public {
        _triggerDefault();
        vm.prank(lender);
        clone.seizeAll();

        uint256 owed = mockMToken.borrowOf(address(clone));
        deal(usdc, lender, owed);
        vm.prank(lender);
        IERC20(usdc).approve(address(clone), owed);
        vm.prank(lender);
        clone.repayLoanAfterDefault(owed);

        uint256 mBalBefore = IERC20(address(mockMToken)).balanceOf(lender);
        uint256 cloneMBal = IERC20(address(mockMToken)).balanceOf(
            address(clone)
        );

        vm.expectEmit(true, true, true, true, address(clone));
        emit LenderReimbursed(cloneMBal);

        vm.prank(lender);
        clone.redeemAndReturn();

        assertEq(
            IERC20(address(mockMToken)).balanceOf(lender) - mBalBefore,
            cloneMBal
        );
        assertEq(IERC20(address(mockMToken)).balanceOf(address(clone)), 0);
    }

    function test_redeemAndReturn_notClosedReverts() public {
        vm.prank(lender);
        vm.expectRevert(CreditLoan.LoanNotClosed.selector);
        clone.redeemAndReturn();
    }

    function test_redeemAndReturn_borrowOutstandingReverts() public {
        _triggerDefault();
        vm.prank(lender);
        clone.seizeAll();

        // borrow still > 0 — haven't repaid.
        vm.prank(lender);
        vm.expectRevert();
        clone.redeemAndReturn();
    }
}
