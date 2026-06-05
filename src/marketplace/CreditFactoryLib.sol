// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Offer, Request, BackendTerms} from "@protocol/marketplace/CreditTypes.sol";

/// Validation helpers extracted from `CreditMarketplaceFactory` to keep the
/// factory's deployed bytecode under the EIP-170 24,576-byte limit.
///
/// These are `public` library functions: each is deployed once and the factory
/// DELEGATECALLs them, so `storage` parameters resolve against the *factory's*
/// own storage (the OpenZeppelin EnumerableSet pattern). The logic is therefore
/// byte-for-byte identical to the former inlined `_checkTermsBounds` /
/// `_containsCollateral` and reads exactly the same state — only the
/// `tierRegistry.tier(borrower)` lookup is hoisted into the factory and passed
/// in as `onchainTier` so the library needs no registry reference.
///
/// The custom errors are redeclared here so reverts originate with identical
/// 4-byte selectors to the factory's declarations (selector = keccak of the
/// error signature, independent of the declaring contract) — existing
/// `expectRevert(...selector)` tests still match.
library CreditFactoryLib {
    error ZeroAddress();
    error InvalidGracePeriod();
    error InvalidOverSeizureBps();
    error InvalidConsecutiveMisses();
    error InvalidMarketplaceFeeBps();
    error BoundsViolation(bytes32 which);
    error BorrowerTierMismatch(uint16 signed, uint16 onchain);

    /// Mirror the factory's caps (see `setDefaultParams`); duplicated here as
    /// compile-time constants — no storage cost.
    uint16 internal constant MAX_OVER_SEIZURE_BPS = 5_000;
    uint32 internal constant MAX_GRACE_PERIOD = 7 days;
    uint16 internal constant MAX_MARKETPLACE_FEE_BPS = 2_000;
    uint16 internal constant MAX_CONSECUTIVE_MISSES = 10;

    /// Equivalent to the former `CreditMarketplaceFactory._checkTermsBounds`.
    /// `o`/`r` are storage pointers into the factory; `onchainTier` is
    /// `tierRegistry.tier(r.borrower)` read by the factory before the call.
    function checkTermsBounds(
        Offer storage o,
        Request storage r,
        BackendTerms calldata terms,
        uint16 onchainTier
    ) public view {
        if (terms.lender != o.lender) revert BoundsViolation("lender");
        if (terms.borrower != r.borrower) revert BoundsViolation("borrower");
        if (terms.mToken != o.mToken) revert BoundsViolation("mToken");
        if (terms.mTokenAmount != o.mTokenAmount) {
            revert BoundsViolation("mTokenAmount");
        }
        if (terms.principalToken != o.principalToken) {
            revert BoundsViolation("principalToken.offer");
        }
        if (terms.principalToken != r.principalToken) {
            revert BoundsViolation("principalToken.request");
        }
        if (terms.principal > o.maxPrincipal) {
            revert BoundsViolation("principal.max");
        }
        if (terms.principal != r.principal) {
            revert BoundsViolation("principal.request");
        }
        if (terms.collateralToken != r.collateralToken) {
            revert BoundsViolation("collateralToken");
        }
        if (terms.collateralAmount != r.collateralAmount) {
            revert BoundsViolation("collateralAmount");
        }
        if (terms.apr < o.minApr || terms.apr > o.maxApr) {
            revert BoundsViolation("apr.offer");
        }
        if (terms.apr > r.maxApr) revert BoundsViolation("apr.request");
        if (terms.term < o.minTerm || terms.term > o.maxTerm) {
            revert BoundsViolation("term.offer");
        }
        if (terms.term < r.minTerm || terms.term > r.maxTerm) {
            revert BoundsViolation("term.request");
        }
        if (!_containsCollateral(o.acceptedCollateral, r.collateralToken)) {
            revert BoundsViolation("collateral.notAccepted");
        }
        /// Backend's signed tier must match registry exactly. This
        /// ties the off-chain risk-engine's view of the borrower to
        /// onchain state, so a compromised backend can't grant a
        /// borrower a higher tier than the registry shows. The
        /// registry value is then gated against the offer's minimum.
        if (terms.borrowerCreditTier != onchainTier) {
            revert BorrowerTierMismatch(terms.borrowerCreditTier, onchainTier);
        }
        if (onchainTier < o.minBorrowerCreditTier) {
            revert BoundsViolation("creditTier");
        }

        /// Operational parameters (gracePeriod, overSeizureBps,
        /// consecutiveMissesForDefault, marketplaceFeeBps, feeRecipient)
        /// appear ONLY in BACKEND_TERMS_TYPEHASH — neither the lender nor
        /// the borrower signs them. Re-enforce the same caps `setDefaultParams`
        /// applies so a buggy or compromised backend can't sign out-of-bounds
        /// terms into a live clone: marketplaceFeeBps > 10_000 would underflow
        /// `_settle` and permanently brick happy-path settlement,
        /// overSeizureBps could seize a wildly disproportionate premium per
        /// miss, consecutiveMissesForDefault == 0 would default on the first
        /// miss, and a zero feeRecipient reverts settlement when fee > 0.
        if (terms.gracePeriod > MAX_GRACE_PERIOD) revert InvalidGracePeriod();
        if (terms.overSeizureBps > MAX_OVER_SEIZURE_BPS) {
            revert InvalidOverSeizureBps();
        }
        if (
            terms.consecutiveMissesForDefault == 0 ||
            terms.consecutiveMissesForDefault > MAX_CONSECUTIVE_MISSES
        ) {
            revert InvalidConsecutiveMisses();
        }
        if (terms.marketplaceFeeBps > MAX_MARKETPLACE_FEE_BPS) {
            revert InvalidMarketplaceFeeBps();
        }
        if (terms.feeRecipient == address(0)) revert ZeroAddress();
    }

    function _containsCollateral(
        address[] memory list,
        address token
    ) private pure returns (bool) {
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == token) return true;
        }
        return false;
    }
}
