// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

enum OfferStatus {
    Active,
    Consumed,
    Canceled
}

enum RequestStatus {
    Active,
    Consumed,
    Canceled
}

enum LoanStatus {
    Pending,
    Active,
    Settled,
    Defaulted,
    Closed
}

struct PaymentSchedule {
    uint32 numInterestPayments;
    uint32 intervalSeconds;
    uint64 firstInterestDueAt;
    uint64 principalDueAt;
    uint256 interestAmountPerPayment;
    uint256 finalPaymentAmount;
}

struct Offer {
    address lender;
    address mToken;
    uint256 mTokenAmount;
    address principalToken;
    uint256 maxPrincipal;
    uint16 maxApr;
    uint16 minApr;
    uint32 minTerm;
    uint32 maxTerm;
    address[] acceptedCollateral;
    uint16 minBorrowerCreditTier;
    uint64 expiresAt;
    uint256 nonce;
}

struct Request {
    address borrower;
    address principalToken;
    uint256 principal;
    address collateralToken;
    uint256 collateralAmount;
    uint16 maxApr;
    uint32 minTerm;
    uint32 maxTerm;
    uint64 expiresAt;
    uint256 nonce;
}

struct BackendTerms {
    uint256 chainId;
    address factory;
    uint256 loanNonce;
    address lender;
    address borrower;
    address mToken;
    uint256 mTokenAmount;
    address principalToken;
    uint256 principal;
    address collateralToken;
    uint256 collateralAmount;
    uint16 apr;
    uint32 term;
    PaymentSchedule schedule;
    uint32 gracePeriod;
    uint16 overSeizureBps;
    uint16 consecutiveMissesForDefault;
    uint16 marketplaceFeeBps;
    address feeRecipient;
    uint16 borrowerCreditTier;
    uint64 issuedAt;
    uint64 validUntil;
}

struct InitParams {
    address lender;
    address borrower;
    address mToken;
    uint256 mTokenAmount;
    address principalToken;
    uint256 principal;
    address collateralToken;
    AggregatorV3Interface collateralChainlinkFeed;
    uint256 collateralAmount;
    uint16 apr;
    uint32 term;
    PaymentSchedule schedule;
    uint32 gracePeriod;
    uint16 overSeizureBps;
    uint16 consecutiveMissesForDefault;
    uint16 marketplaceFeeBps;
    address feeRecipient;
    address backendSignerAtOrigination;
    uint32 stalenessWindow;
    address comptrollerAddr;
}
