// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

import {ICreditLoan} from "@protocol/marketplace/ICreditLoan.sol";
import {InitParams, LoanStatus, PaymentSchedule} from "@protocol/marketplace/CreditTypes.sol";

contract CreditLoan is ICreditLoan {
    error NotImplemented();
    error AlreadyInitialized();

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
        factory = params.factory;

        status = LoanStatus.Pending;
    }

    function activate() external pure override {
        revert NotImplemented();
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
