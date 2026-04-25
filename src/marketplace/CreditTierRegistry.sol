// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2Step} from "@openzeppelin-contracts/contracts/access/Ownable2Step.sol";

/// @notice Onchain mirror of the off-chain credit-tier scale (0 = anyone,
/// 1-1000 by convention). The marketplace factory reads `tier(borrower)`
/// at match time and rejects matches where the registry value is below
/// the offer's `minBorrowerCreditTier` or differs from the value the
/// backend signed. Owned by a key distinct from the BackendTerms signer
/// so a single-key compromise can't simultaneously spoof tier writes
/// and BackendTerms; an attacker must compromise both to elevate a
/// borrower onto offers requiring tier ≥ minTier.
contract CreditTierRegistry is Ownable2Step {
    error ZeroAddress();
    error LengthMismatch();

    event TierSet(
        address indexed borrower,
        uint16 previousTier,
        uint16 newTier
    );

    mapping(address => uint16) public tier;

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddress();
        _transferOwnership(initialOwner);
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
