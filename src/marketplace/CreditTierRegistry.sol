// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2Step} from "@openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {SignatureChecker} from "@openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol";

import {CreditTypeHashes} from "@protocol/marketplace/CreditTypeHashes.sol";
import {EIP712Lib} from "@protocol/marketplace/EIP712Lib.sol";
import {CreditAttestation} from "@protocol/marketplace/CreditTypes.sol";

/// @notice Onchain mirror of the off-chain credit-tier scale (0 = anyone,
/// 1-1000 by convention). The marketplace factory reads `tier(borrower)`
/// at match time and rejects matches where the registry value is below
/// the offer's `minBorrowerCreditTier` or differs from the value the
/// backend signed. Owned by a key distinct from the BackendTerms signer
/// so a single-key compromise can't simultaneously spoof tier writes
/// and BackendTerms; an attacker must compromise both to elevate a
/// borrower onto offers requiring tier ≥ minTier.
///
/// Phase 2a adds a permissionless `setTierFromAttestation` path: anyone can
/// submit a credit-bureau-signed EIP-712 `CreditAttestation` and the
/// registry writes `tier[subject]` after verifying the signature recovers
/// `creditBureauAttestor`. This brings the live off-chain credit score
/// on-chain without trusting the owner key for liveness. The attestation
/// scale is the 0..4 map (0 = unrated, 4 = prime); the owner `setTier`
/// override remains uncapped for governance use.
contract CreditTierRegistry is Ownable2Step {
    error ZeroAddress();
    error LengthMismatch();
    error AttestorNotSet();
    error InvalidAttestationSignature();
    error AttestationExpired();
    error AttestationNotYetValid();
    error TierTooHigh(uint16 tier);
    error StaleAttestation(uint64 incomingIssuedAt, uint64 storedIssuedAt);

    event TierSet(
        address indexed borrower,
        uint16 previousTier,
        uint16 newTier
    );
    event CreditBureauAttestorSet(
        address indexed previous,
        address indexed updated
    );
    event TierAttested(
        address indexed subject,
        uint16 tier,
        uint16 score,
        uint64 issuedAt,
        uint64 validUntil,
        bytes32 reportHash
    );

    /// Upper bound for the attestation tier scale (prime). The owner
    /// `setTier`/`setTiers` overrides are intentionally NOT capped (legacy
    /// 1-1000 convention); only the bureau-attested path is bounded.
    uint16 public constant MAX_TIER = 4;

    /// EIP-712 domain separator. verifyingContract = this registry (Phase
    /// 2a). Built identically to the factory's so the off-chain signer
    /// reuses the same domain machinery.
    bytes32 public immutable DOMAIN_SEPARATOR;

    /// The credit bureau's signing key. Distinct from the owner: the owner
    /// rotates the attestor and can force-write tiers, but cannot itself
    /// mint attestations, and the attestor cannot rotate itself.
    address public creditBureauAttestor;

    mapping(address => uint16) public tier;
    /// `issuedAt` of the attestation that last wrote `tier[subject]`. Basis
    /// for the monotonic anti-downgrade-replay guard and off-chain freshness
    /// checks. Not touched by the owner `setTier`/`setTiers` overrides.
    mapping(address => uint64) public tierAttestedAt;

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddress();
        _transferOwnership(initialOwner);

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                CreditTypeHashes.EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("MoonwellCreditMarketplace")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    /// Rotate the credit-bureau attestor (onlyOwner). Must be distinct from
    /// the owner key in practice to preserve the two-key separation.
    function setCreditBureauAttestor(address newAttestor) external onlyOwner {
        if (newAttestor == address(0)) revert ZeroAddress();
        address previous = creditBureauAttestor;
        creditBureauAttestor = newAttestor;
        emit CreditBureauAttestorSet(previous, newAttestor);
    }

    /// Permissionless: write `tier[subject]` from a bureau-signed
    /// attestation. Anyone (a keeper, the borrower, the frontend) may relay
    /// a fresh attestation. Verifies: attestor configured; subject non-zero;
    /// tier ≤ MAX_TIER; `issuedAt <= now < validUntil`; and a strictly newer
    /// `issuedAt` than the last attested one (blocks replay of a stale but
    /// still-unexpired higher-tier attestation over a fresher downgrade).
    /// The write is persistent — `validUntil` only gates acceptance, it does
    /// not auto-expire the stored tier (the factory's exact-match gate
    /// expects a stable value; consumers read `tierAttestedAt` for freshness).
    function setTierFromAttestation(
        CreditAttestation calldata att,
        bytes calldata sig
    ) external {
        address attestor = creditBureauAttestor;
        if (attestor == address(0)) revert AttestorNotSet();
        if (att.subject == address(0)) revert ZeroAddress();
        if (att.tier > MAX_TIER) revert TierTooHigh(att.tier);
        if (att.issuedAt > block.timestamp) revert AttestationNotYetValid();
        if (att.validUntil <= block.timestamp) revert AttestationExpired();

        uint64 lastAttested = tierAttestedAt[att.subject];
        if (att.issuedAt <= lastAttested) {
            revert StaleAttestation(att.issuedAt, lastAttested);
        }

        bytes32 digest = EIP712Lib.hash(
            DOMAIN_SEPARATOR,
            CreditTypeHashes.hashCreditAttestation(att)
        );
        if (!SignatureChecker.isValidSignatureNow(attestor, digest, sig)) {
            revert InvalidAttestationSignature();
        }

        uint16 previous = tier[att.subject];
        tier[att.subject] = att.tier;
        tierAttestedAt[att.subject] = att.issuedAt;

        emit TierSet(att.subject, previous, att.tier);
        emit TierAttested(
            att.subject,
            att.tier,
            att.score,
            att.issuedAt,
            att.validUntil,
            att.reportHash
        );
    }

    /// Set a borrower's tier. 0 means "anyone" (the default for unset
    /// borrowers); higher values are off-chain risk-grade signals from
    /// the credit bureau / lunar-indexer.
    function setTier(address borrower, uint16 newTier) external onlyOwner {
        if (borrower == address(0)) revert ZeroAddress();
        uint16 previous = tier[borrower];
        tier[borrower] = newTier;
        emit TierSet(borrower, previous, newTier);
    }

    /// Batch helper for periodic syncs from the off-chain bureau. Same
    /// access guard as `setTier` — single key per write loop so a
    /// compromised key still has to be paired with backend compromise
    /// to materially affect matchability.
    function setTiers(
        address[] calldata borrowers,
        uint16[] calldata newTiers
    ) external onlyOwner {
        if (borrowers.length != newTiers.length) revert LengthMismatch();
        for (uint256 i = 0; i < borrowers.length; i++) {
            address borrower = borrowers[i];
            if (borrower == address(0)) revert ZeroAddress();
            uint16 previous = tier[borrower];
            tier[borrower] = newTiers[i];
            emit TierSet(borrower, previous, newTiers[i]);
        }
    }
}
