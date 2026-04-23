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

    event LoanActivated(uint64 activatedAt);
    event InterestPaid(uint32 indexed cursor, uint256 amount);
    event LoanSettled();
    event CollateralSeized(
        uint32 indexed cursor,
        uint256 missedUsd,
        uint256 seizedCollateral
    );
    event LoanDefaulted(uint16 missedCount, uint64 at);

    address public lender;
    address public borrower;
    address public mToken;
    uint256 public mTokenAmount;
    address public principalToken;
    uint256 public principal;
    address public collateralToken;
    AggregatorV3Interface public collateralChainlinkFeed;
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
    uint32 public stalenessWindow;
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
        stalenessWindow = params.stalenessWindow;
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
            totalPrincipalPaid += amountDue;
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

    /// Internal settlement: repays Moonwell, returns mTokens to lender,
    /// releases residual collateral to borrower, distributes the fee.
    /// PR8 fills this in; for PR6 the principal-payment path reverts
    /// so the borrower's final payment rolls back until settlement logic
    /// is live. See spec §7.7.
    function _settle() internal pure {
        revert NotImplemented();
    }

    /// Anyone can trigger progressive clawback for a missed interest
    /// installment (§7.5). Only valid during the interest phase and only
    /// once grace has elapsed on the current cursor. Seizes collateral
    /// equal to the missed USD + overSeizureBps premium, priced via the
    /// clone's immutable Chainlink feed, capped at remaining collateral.
    /// When the missed-count threshold is crossed the loan accelerates.
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

        IERC20(collateralToken).safeTransfer(lender, seizeAmount);
        emit CollateralSeized(
            cursor,
            schedule.interestAmountPerPayment,
            seizeAmount
        );

        if (missedCount >= consecutiveMissesForDefault) {
            _accelerate();
        }
    }

    /// Priced per spec §7.5: treats principalToken as 1 USD at its own
    /// decimals (MVP assumes USDC-class stables). Non-stable principals
    /// would require a principal-side feed in InitParams — out of scope
    /// here.
    function _computeSeizeAmount() internal view returns (uint256) {
        (, int256 answer, , uint256 updatedAt, ) = collateralChainlinkFeed
            .latestRoundData();
        if (answer <= 0) revert InvalidOraclePrice();
        if (block.timestamp - updatedAt > stalenessWindow) {
            revert StaleOraclePrice();
        }

        uint256 feedDecimals = collateralChainlinkFeed.decimals();
        uint256 collateralPriceUsd1e18 = uint256(answer) *
            (10 ** (18 - feedDecimals));

        uint256 principalDecimals = IERC20Metadata(principalToken).decimals();
        uint256 missedUsd1e18 = (schedule.interestAmountPerPayment * 1e18) /
            (10 ** principalDecimals);
        uint256 seizeUsd1e18 = (missedUsd1e18 * (10_000 + overSeizureBps)) /
            10_000;

        uint256 collateralDecimals = IERC20Metadata(collateralToken).decimals();
        return
            (seizeUsd1e18 * (10 ** collateralDecimals)) /
            collateralPriceUsd1e18;
    }

    function _accelerate() internal {
        status = LoanStatus.Defaulted;
        emit LoanDefaulted(missedCount, uint64(block.timestamp));
    }

    function seizeAll() external pure override {
        revert NotImplemented();
    }

    function repayLoanAfterDefault(uint256) external pure override {
        revert NotImplemented();
    }

    function redeemAndReturn() external pure override {
        revert NotImplemented();
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
