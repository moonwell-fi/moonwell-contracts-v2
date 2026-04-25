// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

import {CreditLoan} from "@protocol/marketplace/CreditLoan.sol";
import {InitParams, LoanStatus, PaymentSchedule} from "@protocol/marketplace/CreditTypes.sol";

import {Fixture} from "./Fixture.t.sol";

/// Mutable-price Chainlink stub: tests can tweak `answer` and
/// `updatedAt` between calls to simulate stale / invalid data.
contract MutableFeed {
    int256 public answer;
    uint256 public updatedAt;
    uint8 internal immutable _decimals;

    constructor(int256 _answer, uint8 d) {
        answer = _answer;
        _decimals = d;
        updatedAt = block.timestamp;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function setAnswer(int256 _a) external {
        answer = _a;
    }

    function setUpdatedAt(uint256 _u) external {
        updatedAt = _u;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (0, answer, 0, updatedAt, 0);
    }
}

contract ClaimMissedPaymentTest is Fixture {
    event CollateralSeized(
        uint32 indexed cursor,
        uint256 missedUsd,
        uint256 seizedCollateral
    );
    event KeeperBountyPaid(address indexed keeper, uint256 amount);
    event LoanDefaulted(uint16 missedCount, uint64 at);

    bytes4 internal constant ENTER_MARKETS_SEL =
        bytes4(keccak256("enterMarkets(address[])"));
    bytes4 internal constant BORROW_SEL = bytes4(keccak256("borrow(uint256)"));

    uint32 internal constant NUM_INTEREST = 4;
    uint32 internal constant INTERVAL = 7 days;
    uint256 internal constant PRINCIPAL = 400e6;
    uint256 internal constant INTEREST_AMT = 10e6;
    uint256 internal constant FINAL_AMT = PRINCIPAL + INTEREST_AMT;
    uint32 internal constant GRACE = 1 days;
    uint256 internal constant COLLATERAL_AMOUNT = 1e7; // 0.1 cbBTC
    uint32 internal constant STALENESS = 3_600;

    CreditLoan internal clone;
    MutableFeed internal feed;
    MutableFeed internal usdcFeed;
    uint64 internal firstDueAt;

    function setUp() public override {
        super.setUp();
        feed = new MutableFeed(1e13, 8); // cbBTC @ $100k
        usdcFeed = new MutableFeed(1e8, 8); // USDC @ $1
        firstDueAt = uint64(block.timestamp + INTERVAL);

        clone = new CreditLoan();
        vm.prank(address(factory));
        clone.initialize(_defaultParams(COLLATERAL_AMOUNT));

        _mockMoonwellSuccess();

        vm.prank(address(factory));
        clone.activate();

        // Seed the clone with the borrower's collateral (cbBTC). In the real
        // createLoan flow the factory's safeTransferFrom moves this in; here
        // we bypass the factory and set it directly.
        deal(cbbtc, address(clone), COLLATERAL_AMOUNT);
    }

    function _defaultParams(
        uint256 collateral
    ) internal view returns (InitParams memory p) {
        p.lender = lender;
        p.borrower = borrower;
        p.mToken = mUsdc;
        p.mTokenAmount = 1_000e6;
        p.principalToken = usdc;
        p.principal = PRINCIPAL;
        p.collateralToken = cbbtc;
        p.collateralChainlinkFeed = AggregatorV3Interface(address(feed));
        // Separate feed for the principal side — pegged at $1 so the
        // seize math computes against a stable USDC reference. Tests
        // that simulate a principal depeg can `usdcFeed.setAnswer(...)`
        // before calling claimMissedPayment.
        p.principalChainlinkFeed = AggregatorV3Interface(address(usdcFeed));
        p.collateralAmount = collateral;
        p.apr = 800;
        p.term = 30 days;
        p.schedule = PaymentSchedule({
            numInterestPayments: NUM_INTEREST,
            intervalSeconds: INTERVAL,
            firstInterestDueAt: firstDueAt,
            principalDueAt: firstDueAt + uint64(INTERVAL) * NUM_INTEREST,
            interestAmountPerPayment: INTEREST_AMT,
            finalPaymentAmount: FINAL_AMT
        });
        p.gracePeriod = GRACE;
        p.overSeizureBps = 2_000;
        p.consecutiveMissesForDefault = 2;
        p.marketplaceFeeBps = 500;
        p.feeRecipient = feeRecipient;
        p.comptrollerAddr = unitroller;
        p.collateralFeedStaleness = STALENESS;
        p.principalFeedStaleness = STALENESS;
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

    function _refreshFeeds() internal {
        feed.setUpdatedAt(block.timestamp);
        usdcFeed.setUpdatedAt(block.timestamp);
    }

    function _warpPastGrace(uint32 cursor) internal {
        uint64 dueAt = firstDueAt + uint64(cursor) * INTERVAL;
        vm.warp(dueAt + GRACE + 1);
        feed.setUpdatedAt(block.timestamp); // collateral feed
        usdcFeed.setUpdatedAt(block.timestamp); // principal feed
    }

    // ─── tests ────────────────────────────────────────────────────────

    function test_claimMissedPayment_happy() public {
        _warpPastGrace(0);

        // Expected seize: missed=$10 (10 USDC, 6 decimals), +20% = $12 USD.
        // cbBTC at $100k → 12e18 * 1e8 / (1e13 * 1e10) = 12_000 units = 0.00012 cbBTC.
        uint256 expectedSeize = 12_000;
        uint256 lenderBefore = IERC20(cbbtc).balanceOf(lender);

        vm.expectEmit(true, true, true, true, address(clone));
        emit CollateralSeized(0, INTEREST_AMT, expectedSeize);

        clone.claimMissedPayment();

        assertEq(clone.paymentCursor(), 1);
        assertEq(clone.missedCount(), 1);
        assertEq(clone.seizedCollateralAmount(), expectedSeize);
        assertEq(IERC20(cbbtc).balanceOf(lender) - lenderBefore, expectedSeize);
        assertTrue(clone.status() == LoanStatus.Active);
    }

    /// Depeg scenario: principal token (USDC) drops to $0.50. The
    /// missed payment's USD value drops 50% in the seize math, so the
    /// lender seizes proportionally less collateral — protects the
    /// borrower from over-seizure during a USDC depeg event. Previously
    /// (before the principal feed wire-up) the seize math hardcoded
    /// $1 and would have over-seized 2x.
    function test_claimMissedPayment_principalDepegHalvesSeize() public {
        _warpPastGrace(0);
        usdcFeed.setAnswer(5e7); // $0.50, half-peg

        // Was 12_000 at $1; at $0.50 missed-USD halves so seize halves.
        uint256 expectedSeize = 6_000;

        clone.claimMissedPayment();
        assertEq(clone.seizedCollateralAmount(), expectedSeize);
    }

    /// Keeper bounty: when keeperBountyBps > 0, msg.sender keeps a
    /// fraction of the seize; the lender gets the rest. Sum is the
    /// full seize amount — bounty doesn't expand the seize, just
    /// redistributes it.
    function test_claimMissedPayment_keeperBountyPaid() public {
        // Build a fresh clone with bounty=50 bps (within the 100 bps cap).
        CreditLoan bountyClone = new CreditLoan();
        InitParams memory p = _defaultParams(COLLATERAL_AMOUNT);
        p.keeperBountyBps = 50; // 0.5%

        vm.prank(address(factory));
        bountyClone.initialize(p);
        _mockMoonwellSuccess();
        deal(usdc, address(bountyClone), PRINCIPAL);
        vm.prank(address(factory));
        bountyClone.activate();
        deal(cbbtc, address(bountyClone), COLLATERAL_AMOUNT);

        _warpPastGrace(0);

        // Expected seize: 12_000 (same math as happy case).
        // 50 bps of 12_000 = 60 to keeper; 11_940 to lender.
        uint256 totalSeize = 12_000;
        uint256 expectedBounty = (totalSeize * 50) / 10_000;
        uint256 expectedLender = totalSeize - expectedBounty;

        address keeper = makeAddr("keeper");
        uint256 lenderBefore = IERC20(cbbtc).balanceOf(lender);

        vm.expectEmit(true, true, true, true, address(bountyClone));
        emit KeeperBountyPaid(keeper, expectedBounty);

        vm.prank(keeper);
        bountyClone.claimMissedPayment();

        assertEq(IERC20(cbbtc).balanceOf(keeper), expectedBounty);
        assertEq(
            IERC20(cbbtc).balanceOf(lender) - lenderBefore,
            expectedLender
        );
        assertEq(bountyClone.seizedCollateralAmount(), totalSeize);
    }

    /// keeperBountyBps == 0 disables the carve. Lender gets the full
    /// seize, no KeeperBountyPaid event emitted.
    function test_claimMissedPayment_keeperBountyDisabled() public {
        _warpPastGrace(0);

        uint256 lenderBefore = IERC20(cbbtc).balanceOf(lender);
        address keeper = makeAddr("keeper");

        vm.prank(keeper);
        clone.claimMissedPayment();

        assertEq(IERC20(cbbtc).balanceOf(keeper), 0);
        assertEq(IERC20(cbbtc).balanceOf(lender) - lenderBefore, 12_000);
    }

    function test_claimMissedPayment_anyoneCanCall() public {
        _warpPastGrace(0);
        address keeper = makeAddr("keeper");
        vm.prank(keeper);
        clone.claimMissedPayment();
        assertEq(clone.missedCount(), 1);
    }

    function test_claimMissedPayment_beforeActiveReverts() public {
        CreditLoan fresh = new CreditLoan();
        vm.prank(address(factory));
        fresh.initialize(_defaultParams(COLLATERAL_AMOUNT));
        vm.expectRevert(CreditLoan.LoanNotActive.selector);
        fresh.claimMissedPayment();
    }

    function test_claimMissedPayment_withinGraceReverts() public {
        vm.warp(firstDueAt + GRACE - 1);
        _refreshFeeds();

        vm.expectRevert(CreditLoan.PaymentNotYetMissed.selector);
        clone.claimMissedPayment();
    }

    function test_claimMissedPayment_pastInterestPhaseReverts() public {
        // Walk cursor past the interest phase via sequential missed claims.
        // 4 misses advance cursor from 0 → 4 == numInterestPayments.
        // But we only want 2 consecutive misses to avoid triggering
        // acceleration before reaching the guard, so bump the threshold.
        CreditLoan fresh = new CreditLoan();
        InitParams memory p = _defaultParams(COLLATERAL_AMOUNT);
        p.consecutiveMissesForDefault = 10; // high enough to avoid default

        vm.prank(address(factory));
        fresh.initialize(p);
        _mockMoonwellSuccess();
        // re-deal usdc to the fresh clone (mock borrow stub)
        deal(usdc, address(fresh), PRINCIPAL);
        vm.prank(address(factory));
        fresh.activate();
        deal(cbbtc, address(fresh), COLLATERAL_AMOUNT);

        for (uint32 i = 0; i < NUM_INTEREST; i++) {
            vm.warp(firstDueAt + uint64(i) * INTERVAL + GRACE + 1);
            feed.setUpdatedAt(block.timestamp);
            usdcFeed.setUpdatedAt(block.timestamp);
            fresh.claimMissedPayment();
        }
        assertEq(fresh.paymentCursor(), NUM_INTEREST);

        vm.warp(firstDueAt + uint64(NUM_INTEREST) * INTERVAL + GRACE + 1);
        _refreshFeeds();
        vm.expectRevert(CreditLoan.PastInterestPhase.selector);
        fresh.claimMissedPayment();
    }

    function test_claimMissedPayment_invalidOracleReverts() public {
        _warpPastGrace(0);
        feed.setAnswer(0);
        vm.expectRevert(CreditLoan.InvalidOraclePrice.selector);
        clone.claimMissedPayment();
    }

    function test_claimMissedPayment_negativeOracleReverts() public {
        _warpPastGrace(0);
        feed.setAnswer(-1);
        vm.expectRevert(CreditLoan.InvalidOraclePrice.selector);
        clone.claimMissedPayment();
    }

    function test_claimMissedPayment_staleOracleReverts() public {
        _warpPastGrace(0);
        feed.setUpdatedAt(block.timestamp - STALENESS - 10);
        vm.expectRevert(CreditLoan.StaleOraclePrice.selector);
        clone.claimMissedPayment();
    }

    /// Boundary: feed updated *exactly* `staleness` seconds ago is
    /// accepted (the comparison is strict `>`, not `>=`). One second
    /// older flips into the revert path. This test pins the boundary
    /// so a future tweak from `>` to `>=` would surface as a test
    /// failure rather than a silently changed acceptance window.
    function test_claimMissedPayment_staleOracleAtBoundaryAccepted() public {
        _warpPastGrace(0);
        feed.setUpdatedAt(block.timestamp - STALENESS); // exactly at threshold
        usdcFeed.setUpdatedAt(block.timestamp - STALENESS);
        clone.claimMissedPayment();
        assertEq(clone.missedCount(), 1);
    }

    function test_claimMissedPayment_staleOracleOneSecondOverReverts() public {
        _warpPastGrace(0);
        feed.setUpdatedAt(block.timestamp - STALENESS - 1);
        vm.expectRevert(CreditLoan.StaleOraclePrice.selector);
        clone.claimMissedPayment();
    }

    function test_claimMissedPayment_capsAtAvailableCollateral() public {
        // Use a tiny collateral amount so the computed seize overshoots
        // the available balance.
        CreditLoan tiny = new CreditLoan();
        InitParams memory p = _defaultParams(100);
        vm.prank(address(factory));
        tiny.initialize(p);
        _mockMoonwellSuccess();
        deal(usdc, address(tiny), PRINCIPAL);
        vm.prank(address(factory));
        tiny.activate();
        deal(cbbtc, address(tiny), 100);

        _warpPastGrace(0);

        tiny.claimMissedPayment();
        assertEq(tiny.seizedCollateralAmount(), 100); // capped
        assertEq(IERC20(cbbtc).balanceOf(address(tiny)), 0);
    }

    function test_claimMissedPayment_triggersAccelerate() public {
        // Miss cursor 0 → missedCount=1, still Active.
        _warpPastGrace(0);
        clone.claimMissedPayment();
        assertTrue(clone.status() == LoanStatus.Active);
        assertEq(clone.missedCount(), 1);

        // Miss cursor 1 → missedCount=2 == consecutiveMissesForDefault → accelerate.
        _warpPastGrace(1);

        vm.expectEmit(true, true, true, true, address(clone));
        emit LoanDefaulted(2, uint64(block.timestamp));
        clone.claimMissedPayment();

        assertTrue(clone.status() == LoanStatus.Defaulted);
        assertEq(clone.missedCount(), 2);
    }
}
