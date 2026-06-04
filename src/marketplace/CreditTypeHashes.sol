// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Offer, Request, BackendTerms, PaymentSchedule, CreditAttestation} from "@protocol/marketplace/CreditTypes.sol";

library CreditTypeHashes {
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );

    bytes32 internal constant OFFER_TYPEHASH =
        keccak256(
            "Offer(address lender,address mToken,uint256 mTokenAmount,address principalToken,uint256 maxPrincipal,uint16 maxApr,uint16 minApr,uint32 minTerm,uint32 maxTerm,bytes32 acceptedCollateralHash,uint16 minBorrowerCreditTier,uint64 expiresAt,uint256 nonce)"
        );

    bytes32 internal constant REQUEST_TYPEHASH =
        keccak256(
            "Request(address borrower,address principalToken,uint256 principal,address collateralToken,uint256 collateralAmount,uint16 maxApr,uint32 minTerm,uint32 maxTerm,uint64 expiresAt,uint256 nonce)"
        );

    bytes32 internal constant PAYMENT_SCHEDULE_TYPEHASH =
        keccak256(
            "PaymentSchedule(uint32 numInterestPayments,uint32 intervalSeconds,uint64 firstInterestDueAt,uint64 principalDueAt,uint256 interestAmountPerPayment,uint256 finalPaymentAmount)"
        );

    bytes32 internal constant BACKEND_TERMS_TYPEHASH =
        keccak256(
            "BackendTerms(uint256 chainId,address factory,uint256 loanNonce,address lender,address borrower,address mToken,uint256 mTokenAmount,address principalToken,uint256 principal,address collateralToken,uint256 collateralAmount,uint16 apr,uint32 term,PaymentSchedule schedule,uint32 gracePeriod,uint16 overSeizureBps,uint16 consecutiveMissesForDefault,uint16 marketplaceFeeBps,address feeRecipient,uint16 borrowerCreditTier,uint64 issuedAt,uint64 validUntil)PaymentSchedule(uint32 numInterestPayments,uint32 intervalSeconds,uint64 firstInterestDueAt,uint64 principalDueAt,uint256 interestAmountPerPayment,uint256 finalPaymentAmount)"
        );

    bytes32 internal constant OFFER_CANCEL_TYPEHASH =
        keccak256("OfferCancel(uint256 offerId,address lender,uint256 nonce)");

    bytes32 internal constant REQUEST_CANCEL_TYPEHASH =
        keccak256(
            "RequestCancel(uint256 requestId,address borrower,uint256 nonce)"
        );

    /// Phase 2a credit attestation. Field order MUST match the off-chain
    /// signer's EIP-712 type (moonwell-ai `buildTypedData`) byte-for-byte:
    /// subject, tier, score, reportHash, issuedAt, validUntil.
    bytes32 internal constant CREDIT_ATTESTATION_TYPEHASH =
        keccak256(
            "CreditAttestation(address subject,uint16 tier,uint16 score,bytes32 reportHash,uint64 issuedAt,uint64 validUntil)"
        );

    function hashOffer(Offer memory o) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    OFFER_TYPEHASH,
                    o.lender,
                    o.mToken,
                    o.mTokenAmount,
                    o.principalToken,
                    o.maxPrincipal,
                    o.maxApr,
                    o.minApr,
                    o.minTerm,
                    o.maxTerm,
                    keccak256(abi.encodePacked(o.acceptedCollateral)),
                    o.minBorrowerCreditTier,
                    o.expiresAt,
                    o.nonce
                )
            );
    }

    function hashRequest(Request memory r) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    REQUEST_TYPEHASH,
                    r.borrower,
                    r.principalToken,
                    r.principal,
                    r.collateralToken,
                    r.collateralAmount,
                    r.maxApr,
                    r.minTerm,
                    r.maxTerm,
                    r.expiresAt,
                    r.nonce
                )
            );
    }

    function hashPaymentSchedule(
        PaymentSchedule memory s
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    PAYMENT_SCHEDULE_TYPEHASH,
                    s.numInterestPayments,
                    s.intervalSeconds,
                    s.firstInterestDueAt,
                    s.principalDueAt,
                    s.interestAmountPerPayment,
                    s.finalPaymentAmount
                )
            );
    }

    /// Split into two `abi.encode` halves + `bytes.concat` to avoid
    /// stack-too-deep under optimizer_runs=1. All fields are static types so
    /// the concatenation is byte-equivalent to a single encode.
    function hashBackendTerms(
        BackendTerms memory t
    ) internal pure returns (bytes32) {
        bytes memory head = abi.encode(
            BACKEND_TERMS_TYPEHASH,
            t.chainId,
            t.factory,
            t.loanNonce,
            t.lender,
            t.borrower,
            t.mToken,
            t.mTokenAmount,
            t.principalToken,
            t.principal,
            t.collateralToken,
            t.collateralAmount,
            t.apr,
            t.term
        );
        bytes memory tail = abi.encode(
            hashPaymentSchedule(t.schedule),
            t.gracePeriod,
            t.overSeizureBps,
            t.consecutiveMissesForDefault,
            t.marketplaceFeeBps,
            t.feeRecipient,
            t.borrowerCreditTier,
            t.issuedAt,
            t.validUntil
        );
        return keccak256(bytes.concat(head, tail));
    }

    function hashOfferCancel(
        uint256 offerId,
        address lender,
        uint256 nonce
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(OFFER_CANCEL_TYPEHASH, offerId, lender, nonce)
            );
    }

    function hashRequestCancel(
        uint256 requestId,
        address borrower,
        uint256 nonce
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(REQUEST_CANCEL_TYPEHASH, requestId, borrower, nonce)
            );
    }

    function hashCreditAttestation(
        CreditAttestation memory a
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    CREDIT_ATTESTATION_TYPEHASH,
                    a.subject,
                    a.tier,
                    a.score,
                    a.reportHash,
                    a.issuedAt,
                    a.validUntil
                )
            );
    }
}
