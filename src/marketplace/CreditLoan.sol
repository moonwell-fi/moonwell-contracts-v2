// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

import {ICreditLoan} from "@protocol/marketplace/ICreditLoan.sol";
import {InitParams, LoanStatus, PaymentSchedule} from "@protocol/marketplace/CreditTypes.sol";

/// @dev Minimal inward-facing slices of the Moonwell ABI. Declared locally
/// so CreditLoan doesn't take a dependency on the full Comptroller /
/// MToken surface; only the calls this contract actually makes.
interface IMoonwellComptroller {
    function enterMarkets(
        address[] calldata mTokens
    ) external returns (uint256[] memory);
}

interface IMoonwellMToken {
    function borrow(uint256 borrowAmount) external returns (uint256);
    function borrowBalanceCurrent(address account) external returns (uint256);
    function borrowBalanceStored(
        address account
    ) external view returns (uint256);
    function repayBorrowBehalf(
        address borrower,
        uint256 repayAmount
    ) external returns (uint256);
}

contract CreditLoan is ICreditLoan, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error NotImplemented();
    error AlreadyInitialized();
    error OnlyFactory();
    error OnlyBorrower();
    error LoanNotPending();
    error LoanNotActive();
    error PaymentGraceElapsed();
    error EnterMarketsFailed(uint256 errorCode);
    error BorrowFailed(uint256 errorCode);
    error PastInterestPhase();
    error PaymentNotYetMissed();
    error InvalidOraclePrice();
    error StaleOraclePrice();
    error OnlyLender();
    error LoanNotDefaulted();
    error LoanNotClosed();
    error InsufficientPrincipalForRepay(uint256 have, uint256 required);
    error RepayFailed(uint256 errorCode);
    error MoonwellBorrowOutstanding(uint256 balance);

    event LoanActivated(uint64 activatedAt);
    event InterestPaid(uint32 indexed cursor, uint256 amount);
    event LoanSettled();
    event CollateralSeized(
        uint32 indexed cursor,
        uint256 missedUsd,
        uint256 seizedCollateral
    );
    event KeeperBountyPaid(address indexed keeper, uint256 amount);
    event LoanDefaulted(uint16 missedCount, uint64 at);
    event DefaultSeized(uint256 amount);
    event LenderReimbursed(uint256 mTokenAmount);

    address public lender;
    address public borrower;
    address public mToken;
    uint256 public mTokenAmount;
    address public principalToken;
    uint256 public principal;
    address public collateralToken;
    AggregatorV3Interface public collateralChainlinkFeed;
    AggregatorV3Interface public principalChainlinkFeed;
    uint256 public collateralAmount;
    uint16 public apr;
    uint32 public term;
    PaymentSchedule public schedule;
    uint32 public gracePeriod;
    uint16 public overSeizureBps;
    uint16 public consecutiveMissesForDefault;
    uint16 public marketplaceFeeBps;
    address public feeRecipient;
    address public factory;
    address public backendSignerAtOrigination;
    uint64 public activatedAt;
    /// Per-feed staleness windows snapshotted from the factory's
    /// FeedConfig at originate time. Replaces the old single
    /// `stalenessWindow` so a slow-heartbeat principal (USDC, ~24h)
    /// and a fast-heartbeat collateral (BTC, ~1h) get independent
    /// freshness budgets.
    uint32 public collateralFeedStaleness;
    uint32 public principalFeedStaleness;
    /// Bps of seized collateral routed to whoever called
    /// `claimMissedPayment` (msg.sender). 0 disables the bounty.
    uint16 public keeperBountyBps;
    address public comptrollerAddr;

    uint32 public paymentCursor;
    uint16 public missedCount;
    uint256 public totalInterestPaid;
    uint256 public totalPrincipalPaid;
    uint256 public seizedCollateralAmount;
    LoanStatus public override status;

    bool private _initialized;

    function initialize(InitParams calldata params) external override {
        if (_initialized) revert AlreadyInitialized();
        _initialized = true;

        /// Trust is anchored to the caller of initialize, not to a
        /// user-supplied field. The factory deploys each clone via
        /// Clones.clone and initializes it in the same call — msg.sender
        /// is therefore the factory. If a different deployer ever
        /// initialized a clone, they could not impersonate the factory
        /// downstream (activate / seize logic keys off `factory`).
        factory = msg.sender;

        lender = params.lender;
        borrower = params.borrower;
        mToken = params.mToken;
        mTokenAmount = params.mTokenAmount;
        principalToken = params.principalToken;
        principal = params.principal;
        collateralToken = params.collateralToken;
        collateralChainlinkFeed = params.collateralChainlinkFeed;
        principalChainlinkFeed = params.principalChainlinkFeed;
        collateralAmount = params.collateralAmount;
        apr = params.apr;
        term = params.term;
        schedule = params.schedule;
        gracePeriod = params.gracePeriod;
        overSeizureBps = params.overSeizureBps;
        consecutiveMissesForDefault = params.consecutiveMissesForDefault;
        marketplaceFeeBps = params.marketplaceFeeBps;
        feeRecipient = params.feeRecipient;
        backendSignerAtOrigination = params.backendSignerAtOrigination;
        collateralFeedStaleness = params.collateralFeedStaleness;
        principalFeedStaleness = params.principalFeedStaleness;
        keeperBountyBps = params.keeperBountyBps;
        comptrollerAddr = params.comptrollerAddr;

        status = LoanStatus.Pending;
    }

    /// Called by the factory at the tail of createLoan (§7.3). Enters the
    /// Moonwell market, draws `principal` via `mToken.borrow`, and
    /// forwards the borrowed principalToken to the borrower. Reentrancy
    /// is guarded by the factory's nonReentrant on createLoan (§12.1);
    /// this function is only reachable during that atomic call.
    function activate() external override {
        if (msg.sender != factory) revert OnlyFactory();
        if (status != LoanStatus.Pending) revert LoanNotPending();

        address[] memory markets = new address[](1);
        markets[0] = mToken;
        uint256[] memory errs = IMoonwellComptroller(comptrollerAddr)
            .enterMarkets(markets);
        if (errs[0] != 0) revert EnterMarketsFailed(errs[0]);

        uint256 err = IMoonwellMToken(mToken).borrow(principal);
        if (err != 0) revert BorrowFailed(err);

        IERC20(principalToken).safeTransfer(borrower, principal);

        status = LoanStatus.Active;
        activatedAt = uint64(block.timestamp);
        emit LoanActivated(activatedAt);
    }

    /// Borrower-only. Pays the next interest installment or the final
    /// principal payment per §7.4. The caller must have approved
    /// `principalToken` to this contract for the amount due.
    function makePayment() external override nonReentrant {
        if (status != LoanStatus.Active) revert LoanNotActive();
        if (msg.sender != borrower) revert OnlyBorrower();

        uint32 cursor = paymentCursor;
        uint256 amountDue;

        if (cursor < schedule.numInterestPayments) {
            if (block.timestamp >= _interestDueAt(cursor) + gracePeriod) {
                revert PaymentGraceElapsed();
            }
            amountDue = schedule.interestAmountPerPayment;
            IERC20(principalToken).safeTransferFrom(
                borrower,
                address(this),
                amountDue
            );
            totalInterestPaid += amountDue;
            paymentCursor = cursor + 1;
            /// Reset miss counter on any successful interest payment so a
            /// prior clawback event doesn't count against a recovered loan.
            missedCount = 0;
            emit InterestPaid(cursor, amountDue);
        } else {
            if (block.timestamp >= schedule.principalDueAt + gracePeriod) {
                revert PaymentGraceElapsed();
            }
            amountDue = schedule.finalPaymentAmount;
            IERC20(principalToken).safeTransferFrom(
                borrower,
                address(this),
                amountDue
            );
            /// finalPaymentAmount is "principal + any trailing interest
            /// stub" per §4.4. Route the stub into totalInterestPaid so
            /// it joins the fee/lender distribution in _settle; otherwise
            /// a schedule with uneven compounding would leave USDC
            /// stranded in the clone.
            uint256 trailingInterest = amountDue > principal
                ? amountDue - principal
                : 0;
            totalPrincipalPaid += (amountDue - trailingInterest);
            if (trailingInterest > 0) {
                totalInterestPaid += trailingInterest;
            }
            paymentCursor = cursor + 1;
            _settle();
        }
    }

    function _interestDueAt(uint32 cursor) internal view returns (uint64) {
        /// cursor is zero-indexed: installment i is due at firstInterestDueAt
        /// + i * intervalSeconds.
        return
            schedule.firstInterestDueAt +
            uint64(cursor) *
            uint64(schedule.intervalSeconds);
    }

    /// Happy-path settlement (§7.7): repay Moonwell in full, distribute
    /// interest fee, return lender's mTokens, return residual collateral
    /// to the borrower. `forceApprove(type(uint).max)` overwrites any
    /// residual allowance from a prior partial repay; `type(uint).max` as
    /// the repayAmount is Moonwell's full-repay sentinel
    /// (src/MToken.sol:1297). Pre-flight balance check short-circuits
    /// the `SafeERC20` revert path so a shortfall surfaces as the
    /// specific `InsufficientPrincipalForRepay` error — lenders route
    /// to the default-unwind path (§7.6) in that case.
    function _settle() internal {
        uint256 borrowBal = IMoonwellMToken(mToken).borrowBalanceCurrent(
            address(this)
        );
        uint256 selfBal = IERC20(principalToken).balanceOf(address(this));
        if (selfBal < borrowBal) {
            revert InsufficientPrincipalForRepay(selfBal, borrowBal);
        }
        IERC20(principalToken).forceApprove(mToken, type(uint256).max);
        uint256 err = IMoonwellMToken(mToken).repayBorrowBehalf(
            address(this),
            type(uint256).max
        );
        if (err != 0) revert RepayFailed(err);

        /// Base the fee split on what's actually left after Moonwell
        /// takes its borrow accrual, not on `totalInterestPaid` (which
        /// ignores accrual). Spec §7.7 wrote the formula against the
        /// gross borrower payments — that only works when Moonwell's
        /// borrow APR is zero. Real accrual is non-zero, so we read the
        /// post-repay balance as the distributable pot. Lender bears
        /// the Moonwell cost (their choice of pledged asset); fee
        /// scales down proportionally.
        uint256 distributable = IERC20(principalToken).balanceOf(address(this));
        uint256 fee = (distributable * marketplaceFeeBps) / 10_000;
        uint256 lenderInterest = distributable - fee;

        if (fee > 0) {
            IERC20(principalToken).safeTransfer(feeRecipient, fee);
        }
        if (lenderInterest > 0) {
            IERC20(principalToken).safeTransfer(lender, lenderInterest);
        }

        uint256 mBal = IERC20(mToken).balanceOf(address(this));
        if (mBal > 0) {
            IERC20(mToken).safeTransfer(lender, mBal);
        }

        uint256 remainingCol = collateralAmount - seizedCollateralAmount;
        if (remainingCol > 0) {
            IERC20(collateralToken).safeTransfer(borrower, remainingCol);
        }

        status = LoanStatus.Settled;
        emit LoanSettled();
    }

    /// Anyone can trigger progressive clawback for a missed interest
    /// installment (§7.5). Only valid during the interest phase and only
    /// once grace has elapsed on the current cursor. Seizes collateral
    /// equal to the missed USD + overSeizureBps premium, priced via the
    /// clone's immutable Chainlink feed, capped at remaining collateral.
    /// A small `keeperBountyBps` slice is routed to msg.sender so neutral
    /// keepers can profitably trigger this (without it, the lender's own
    /// bot is the only viable caller — permissionless in name only).
    /// msg.sender (not tx.origin) is the recipient so 4337 / Safe-relay
    /// flows work. When the missed-count threshold is crossed the loan
    /// accelerates.
    function claimMissedPayment() external override nonReentrant {
        if (status != LoanStatus.Active) revert LoanNotActive();

        uint32 cursor = paymentCursor;
        if (cursor >= schedule.numInterestPayments) revert PastInterestPhase();
        if (block.timestamp <= _interestDueAt(cursor) + gracePeriod) {
            revert PaymentNotYetMissed();
        }

        uint256 seizeAmount = _computeSeizeAmount();

        uint256 available = collateralAmount - seizedCollateralAmount;
        if (seizeAmount > available) seizeAmount = available;

        seizedCollateralAmount += seizeAmount;
        unchecked {
            /// missedCount is uint16; bounded by schedule.numInterestPayments
            /// and consecutiveMissesForDefault (capped at 10 by factory).
            missedCount += 1;
        }
        paymentCursor = cursor + 1;

        uint256 keeperShare = (seizeAmount * keeperBountyBps) / 10_000;
        uint256 lenderShare = seizeAmount - keeperShare;
        if (lenderShare > 0) {
            IERC20(collateralToken).safeTransfer(lender, lenderShare);
        }
        if (keeperShare > 0) {
            IERC20(collateralToken).safeTransfer(msg.sender, keeperShare);
            emit KeeperBountyPaid(msg.sender, keeperShare);
        }
        emit CollateralSeized(
            cursor,
            schedule.interestAmountPerPayment,
            seizeAmount
        );

        if (missedCount >= consecutiveMissesForDefault) {
            _accelerate();
        }
    }

    /// Prices both sides through real Chainlink feeds — the principal
    /// side via `principalChainlinkFeed` (no longer a $1-stablecoin
    /// assumption), the collateral side via `collateralChainlinkFeed`.
    /// Each side uses its own staleness budget so a slow-heartbeat
    /// principal feed and a fast-heartbeat collateral feed don't have
    /// to share a window. During a depeg event (USDC → $0.50, etc.) the
    /// missed payment's real USD value drops in lockstep, so the seize
    /// math stays proportional and the lender doesn't end up with
    /// collateral worth far more or far less than the actual missed
    /// obligation.
    function _computeSeizeAmount() internal view returns (uint256) {
        // Missed amount in USD via the principal feed.
        uint256 missedUsd1e18 = _priceUsd1e18(
            principalToken,
            schedule.interestAmountPerPayment,
            principalChainlinkFeed,
            principalFeedStaleness
        );
        uint256 seizeUsd1e18 = (missedUsd1e18 * (10_000 + overSeizureBps)) /
            10_000;

        // Inverse: USD → collateral units, gated by the collateral
        // feed's own staleness budget.
        (, int256 answer, , uint256 updatedAt, ) = collateralChainlinkFeed
            .latestRoundData();
        if (answer <= 0) revert InvalidOraclePrice();
        if (block.timestamp - updatedAt > collateralFeedStaleness) {
            revert StaleOraclePrice();
        }
        uint256 collateralPriceUsd1e18 = uint256(answer) *
            (10 ** (18 - collateralChainlinkFeed.decimals()));
        uint256 collateralDecimals = IERC20Metadata(collateralToken).decimals();
        return
            (seizeUsd1e18 * (10 ** collateralDecimals)) /
            collateralPriceUsd1e18;
    }

    function _priceUsd1e18(
        address token,
        uint256 amount,
        AggregatorV3Interface feed,
        uint32 maxStaleness
    ) internal view returns (uint256) {
        (, int256 answer, , uint256 updatedAt, ) = feed.latestRoundData();
        if (answer <= 0) revert InvalidOraclePrice();
        if (block.timestamp - updatedAt > maxStaleness) {
            revert StaleOraclePrice();
        }
        uint256 priceUsd1e18 = uint256(answer) * (10 ** (18 - feed.decimals()));
        uint256 tokenDecimals = IERC20Metadata(token).decimals();
        return (amount * priceUsd1e18) / (10 ** tokenDecimals);
    }

    function _accelerate() internal {
        status = LoanStatus.Defaulted;
        emit LoanDefaulted(missedCount, uint64(block.timestamp));
    }

    /// Lender escape hatch when `_settle` is wedged: borrower has paid
    /// every interest installment on time but the final principal
    /// payment can't settle (typical cause: Moonwell borrow APR drifted
    /// above marketplace APR for the term, leaving the clone short of
    /// `borrowBalanceCurrent`). Without this, a solvent-but-stuck loan
    /// has no recovery path because the missed-payment route requires
    /// missed *interest*, not a settlement shortfall. Callable by the
    /// lender once the principal due date + grace has elapsed.
    function forceDefault() external override nonReentrant {
        if (status != LoanStatus.Active) revert LoanNotActive();
        if (msg.sender != lender) revert OnlyLender();
        if (block.timestamp <= schedule.principalDueAt + gracePeriod) {
            revert PaymentNotYetMissed();
        }
        _accelerate();
    }

    /// After acceleration, the lender claims all remaining collateral
    /// without per-payment oracle math (§7.6). Status flips Closed; the
    /// Moonwell borrow stays open until the lender unwinds via the
    /// helpers below.
    function seizeAll() external override nonReentrant {
        if (status != LoanStatus.Defaulted) revert LoanNotDefaulted();
        if (msg.sender != lender) revert OnlyLender();

        uint256 remaining = collateralAmount - seizedCollateralAmount;
        seizedCollateralAmount = collateralAmount;
        status = LoanStatus.Closed;

        if (remaining > 0) {
            IERC20(collateralToken).safeTransfer(lender, remaining);
        }
        emit DefaultSeized(remaining);
    }

    /// Post-default unwind step 1: lender (or anyone on their behalf)
    /// deposits principalToken into this contract and calls
    /// `repayBorrowBehalf` to pay down the Moonwell borrow. Can be called
    /// multiple times with partial amounts.
    function repayLoanAfterDefault(
        uint256 repayAmount
    ) external override nonReentrant {
        if (status != LoanStatus.Closed) revert LoanNotClosed();
        IERC20(principalToken).safeTransferFrom(
            msg.sender,
            address(this),
            repayAmount
        );
        IERC20(principalToken).forceApprove(mToken, repayAmount);
        uint256 err = IMoonwellMToken(mToken).repayBorrowBehalf(
            address(this),
            repayAmount
        );
        if (err != 0) revert RepayFailed(err);
    }

    /// Post-default unwind step 2: once the Moonwell borrow is zero, the
    /// lender retrieves their mTokens (which include any supply yield
    /// accrued during the loan).
    function redeemAndReturn() external override nonReentrant {
        if (status != LoanStatus.Closed) revert LoanNotClosed();
        uint256 outstanding = IMoonwellMToken(mToken).borrowBalanceStored(
            address(this)
        );
        if (outstanding != 0) revert MoonwellBorrowOutstanding(outstanding);

        uint256 mBal = IERC20(mToken).balanceOf(address(this));
        if (mBal > 0) {
            IERC20(mToken).safeTransfer(lender, mBal);
        }
        emit LenderReimbursed(mBal);
    }

    function nextPaymentDueAt() external view override returns (uint64) {
        if (status != LoanStatus.Active) return 0;
        uint32 cursor = paymentCursor;
        if (cursor < schedule.numInterestPayments) {
            return _interestDueAt(cursor);
        }
        return schedule.principalDueAt;
    }

    function remainingPayments() external view override returns (uint32) {
        if (status != LoanStatus.Active) return 0;
        uint32 total = schedule.numInterestPayments + 1;
        if (paymentCursor >= total) return 0;
        return total - paymentCursor;
    }

    function totalOwedNow()
        external
        view
        override
        returns (uint256 principalDue, uint256 interestDue)
    {
        if (status != LoanStatus.Active) return (0, 0);
        uint32 cursor = paymentCursor;
        uint32 n = schedule.numInterestPayments;
        if (cursor < n) {
            interestDue =
                uint256(n - cursor) *
                schedule.interestAmountPerPayment;
            principalDue = schedule.finalPaymentAmount;
        } else if (cursor == n) {
            principalDue = schedule.finalPaymentAmount;
        }
    }

    function collateralRemaining() external view override returns (uint256) {
        if (collateralAmount < seizedCollateralAmount) return 0;
        return collateralAmount - seizedCollateralAmount;
    }
}
