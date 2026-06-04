// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

enum OfferStatus {
    Active,
    Canceled,
    Consumed,
    Expired
}

enum RequestStatus {
    Active,
    Canceled,
    Consumed,
    Expired
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
    /// Not part of OFFER_TYPEHASH — the lender signs the economic fields
    /// above and the factory stamps status=Active at post time, overriding
    /// whatever the caller passes.
    OfferStatus status;
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
    /// Same rule as Offer.status — not part of REQUEST_TYPEHASH.
    RequestStatus status;
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
    AggregatorV3Interface principalChainlinkFeed;
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
    /// Per-feed staleness windows. Replaces the single `stalenessWindow`
    /// field — Chainlink heartbeats vary by asset (BTC/USD ≈ 1h,
    /// USDC/USD ≈ 24h), so one window can't be right for both. Set at
    /// whitelist time on the factory and snapshotted into the clone here.
    uint32 collateralFeedStaleness;
    uint32 principalFeedStaleness;
    uint16 keeperBountyBps;
    address comptrollerAddr;
    uint16 moonwellHealthBufferBps;
}

/// EIP-712 credit attestation signed off-chain by the credit bureau
/// (`creditBureauAttestor`) and verified on-chain. Phase 2a: consumed by
/// `CreditTierRegistry.setTierFromAttestation` to write a borrower's tier
/// from a bureau-signed report, making the factory's existing
/// `tierRegistry.tier(borrower)` gate load-bearing with no factory change.
/// The EIP-712 verifyingContract is the registry in Phase 2a (the factory
/// in Phase 2b, with the same struct + typehash + attestor key — only the
/// domain's verifyingContract differs).
struct CreditAttestation {
    address subject; // borrower the report is about
    uint16 tier; // mapped 0..4 (0 = unrated / insufficient history)
    uint16 score; // raw 300–850, or 0 when insufficient history
    bytes32 reportHash; // keccak256(abi.encode(subject,score,tier,windowDays,generatedAt))
    uint64 issuedAt;
    uint64 validUntil; // keep SHORT (minutes)
}
