// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
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

contract CreditLoan is ICreditLoan {
    using SafeERC20 for IERC20;

    error NotImplemented();
    error AlreadyInitialized();
    error OnlyFactory();
    error LoanNotPending();
    error EnterMarketsFailed(uint256 errorCode);
    error BorrowFailed(uint256 errorCode);

    event LoanActivated(uint64 activatedAt);

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

    function makePayment() external pure override {
        revert NotImplemented();
    }

    function claimMissedPayment() external pure override {
        revert NotImplemented();
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

    function nextPaymentDueAt() external pure override returns (uint64) {
        revert NotImplemented();
    }

    function remainingPayments() external pure override returns (uint32) {
        revert NotImplemented();
    }

    function totalOwedNow() external pure override returns (uint256, uint256) {
        revert NotImplemented();
    }

    function collateralRemaining() external pure override returns (uint256) {
        revert NotImplemented();
    }
}
