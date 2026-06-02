# Credit Delegation — Phase 2 Plan (Credit Bureau)

> Companion to `docs/CREDIT_DELEGATION_SPEC_V1.md`. V1 specifies the shipped,
> fully **overcollateralized** marketplace (PR #629). This doc plans **Phase
> 2**: bringing the live Moonwell credit score on-chain and unlocking
> reputation-priced — and ultimately **undercollateralized** — lending.
>
> Scope decisions locked with the team:
>
> - **Sequence: 2a → 2b.** Ship score-on-chain + tier-priced
>   _overcollateralized_ loans first (low legal risk, generates calibration
>   data), then undercollateralized behind legal sign-off.
> - **Default-loss model: option 1 → option 2.** Start with _lender-eats-it_
>   (prime-only, ≥50% collateralized), migrate to a fee-funded
>   `CreditInsuranceVault` once default data validates pricing.

---

## 0. The fact that reframes Phase 2

The credit bureau's **read** layer is already live (PR #629 TODO:
_"`lunar-indexer` ships credit data per wallet"_ ✅). Verified against the live
skill on 2026-06-02:

```
GET https://api.moonwell.fi/v1/credit-report/{address}?chain=&window=
→ { score: 300–850 | null,
    tier: "prime"(≥740) | "near_prime"(670–739) | "subprime"(580–669)
        | "deep_subprime"(<580) | null,
    insufficientHistory, components{paymentHistory(175) creditUtilization(150)
        historyLength(100) marketDiversity(75) activityConsistency(50)},
    healthFactor{…}, activity{…}, signals{…}, disclaimers[], schemaVersion }
```

**Critical:** this endpoint is **read-only and unsigned**. There is no EIP-712
signature, no `reportHash`, and no `/credit/attestation` endpoint. Its own
disclaimer says _"no prediction is implied … not an underwriting decision."_

A smart contract cannot trust an unsigned HTTP body. Therefore the **#1
prerequisite for any on-chain credit logic is an off-chain signed-attestation
service** (the open PR #629 TODO: _"`moonwell-ai` wraps service endpoints with
x402"_). The on-chain work in §3–§4 below **cannot be tested end-to-end** until
that service signs with a governance-registered key. Today the only trust bridge
is `CreditTierRegistry` — a `uint16` written by an owner key, with no score→tier
mapping and no freshness.

---

## 1. Where Phase 1 left the seams (and why 2 widens them)

The audit of PR #629 (6-dimension adversarial pass) confirmed all five product
properties are correctly implemented and found **no fund-theft bugs**. Its one
structural theme is directly load-bearing for Phase 2:

> **The backend signer is fully trusted for every operational/economic loan
> parameter, and those parameters bypass the governance caps.**

Phase 2 hands the backend a _fourth_ signed input (the credit attestation) and —
in 2b — lets that input _reduce required collateral_. So the seam must be closed
**before** 2b, not after. The hardening fixes in §2 are Phase-2 prerequisites,
not optional cleanup.

---

## 2. Phase 2a prerequisites — audit hardening (implemented in this branch)

These three fixes harden the exact surfaces Phase 2 expands. All landed with TDD
(failing test → fix → green) in `test/unit/marketplace/`.

| Audit ID                  | Fix                                                                                                                                                                                                                                                                                                                                                                   | Files                                        |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| **MATCH-01 / F-03** (med) | `createLoan` now re-enforces the `setDefaultParams` caps on the backend-signed `gracePeriod`, `overSeizureBps`, `consecutiveMissesForDefault`, `marketplaceFeeBps`, and `feeRecipient != 0`. Closes the consent gap (these fields are not in `OFFER`/`REQUEST` typehashes) so a buggy/compromised backend can't brick `_settle` (fee > 100% underflow) or over-seize. | `CreditMarketplaceFactory._checkTermsBounds` |
| **ACCT-02** (med)         | `repayLoanAfterDefault` repays `min(owed, balance)` so the clone's pre-default interest counts toward the Moonwell debt (lender funds only the shortfall); `redeemAndReturn` sweeps any residual `principalToken` to the lender. Previously the borrower's paid interest was stranded forever in a defaulted clone.                                                   | `CreditLoan`                                 |
| **CDM-02** (med)          | New lender-only `forceDefaultStaleOracle()`: during the interest phase, if a payment is genuinely missed **and** a depended-on Chainlink feed is unusable (stale / non-positive / future-stamped) so `claimMissedPayment` reverts, the lender can accelerate without oracle math, then `seizeAll`. Delivers the enforcement path §12.10/§12.12 promised.              | `CreditLoan`, `ICreditLoan`                  |

Remaining audit items are low/info and tracked but **not** Phase-2 blockers:
CDM-04 (fee-on-transfer collateral — gated by governance whitelist), ACCT-03
(APR-floor is an origination snapshot — documented, recoverable; consider
letting the _borrower_ trigger unwind after grace), and the doc/cosmetic items
MATCH-04, MATCH-05, F-06, ACCT-04 (update spec §16; rename/remove unread
`default*` storage; fix the `CollateralSeized.missedUsd` label).

---

## 3. Phase 2a — bring the score on-chain (overcollateralized, tier-priced)

Goal: make `minBorrowerCreditTier` _mean something_ and let the backend price
APR off a verifiable score, **without** changing the collateralization
invariant. Low legal risk; ships the data pipeline that 2b depends on.

### 3a.1 Off-chain (critical path — gates everything)

1. **Signed attestation endpoint** in `lunar-indexer` / `moonwell-ai`:
   `GET /v1/credit/attestation/{address}` returning the report **plus** an
   EIP-712 signature from a dedicated `creditBureauAttestor` key (see §5 for the
   schema). This key is **distinct** from both the `backendSigner` and the
   `CreditTierRegistry` owner (preserve the multi-key separation the audit
   validated — TIER-02).
2. **x402 wrapping** of POST offer/request, POST match, and GET credit endpoints
   (the open TODO). The attestation fetch is the new x402-metered call.
3. **Canonical `score → uint16 tier` mapping** defined once and shared by API,
   registry sync, and contracts (see §5.2). E.g.
   `unrated=0, deep_subprime=1, subprime=2, near_prime=3, prime=4`.

### 3a.2 On-chain (minimal)

- Automate `CreditTierRegistry.setTiers` syncs from the signed feed (the
  registry already exists; it's just unpopulated). Keep the existing advisory
  gate.
- **Optional hardening (TIER-03):** add `issuedAt`/`validUntil` (or a block
  stamp) to registry entries so a stale tier isn't load-bearing indefinitely.
  Cheap, and forward-useful once tier becomes load-bearing in 2b.
- No loan-logic changes. APR is still priced off-chain off the score; the §7.3
  Chainlink LTV check still enforces ≥110% collateral.

**Exit criteria for 2a:** real attestations flowing, registry auto-synced, at
least one tier-gated overcollateralized loan originated on mainnet, and ≥1 month
of repayment/default data captured to calibrate 2b pricing.

---

## 4. Phase 2b — undercollateralized (spec §18 / "Phase 3e"), behind legal sign-off

Only after legal review. Reuses the `setCreditLoanImplementation` evolution hook
so the same factory hosts both over- and undercollateralized loans.

### 4.1 Factory additions

```solidity
address public creditBureauAttestor;            // distinct from backendSigner
function setCreditBureauAttestor(address) external onlyOwner;

struct CreditAttestation {                       // see §5.1 for the typehash
    address subject;
    uint16  tier;
    uint16  score;
    bytes32 reportHash;
    uint64  issuedAt;
    uint64  validUntil;
}

// createLoan gains a 4th signature + attestation:
function createLoan(
    uint256 offerId, uint256 requestId,
    BackendTerms calldata terms,
    CreditAttestation calldata attestation,
    bytes calldata offerSig, bytes calldata requestSig,
    bytes calldata backendSig, bytes calldata attestationSig
) external returns (uint256 loanId, address loanAddress);
```

Factory verifies: `attestationSig` recovers `creditBureauAttestor`;
`attestation.subject == request.borrower`;
`attestation.validUntil > block.timestamp`;
`attestation.tier >= offer.minBorrowerCreditTier`; and
`attestation.reportHash == terms.attestationReportHash` (binds the attestation
to _these_ terms, blocking replay of an old attestation against new terms).

### 4.2 `BackendTerms` v2 — ⚠️ requires a **versioned typehash**

```solidity
struct BackendTerms {
  // existing fields …
  bytes32 attestationReportHash; // must equal CreditAttestation.reportHash
  uint16 minCollateralizationBps; // 0 = uncollateralized; 10_000 = par; >10_000 = over
}
```

Spec §18.6 says _"factory storage and clone layout stay compatible"_ — true. But
it omits that **signatures do not stay compatible**: `BACKEND_TERMS_TYPEHASH` is
a string constant in `CreditTypeHashes.sol`, so adding fields changes the hash
and **breaks every signature path**. Phase 2b must introduce a
`BACKEND_TERMS_TYPEHASH_V2` (and a v2 `hashBackendTerms`) and route the new
`createLoan` variant through it, leaving the v1 hash intact for any in-flight v1
offers. This is the single most error-prone part of 2b — pin it with a
typehash-string unit test.

### 4.3 `CreditLoanV2` implementation

- Relaxed origination: when `minCollateralizationBps < 10_000`, skip / scale the
  §7.3 Chainlink LTV check accordingly (the whole point of 2b). Over the floor
  it behaves like v1.
- Emits
  `CreditDefault(borrower, principalOutstanding, interestOutstanding, collateralSeized, borrowerTierAtOrigination, at)`
  on acceleration so the bureau closes the reputation loop (downgrades the
  borrower, feeding future reports).
- Deployed via `setCreditLoanImplementation`; v1 clones keep their logic
  forever.

### 4.4 Default-loss absorption — option 1 → option 2

- **Launch (option 1, lender-eats-it):** undercollateralization priced entirely
  into APR. Gate hard: **prime tier only, `minCollateralizationBps ≥ 5_000`.**
  No new contracts. The first cohort _is_ the pricing calibration set.
- **Then (option 2, `CreditInsuranceVault`):** route a slice of
  `marketplaceFeeBps` into a fee-funded coverage pool; on an undercollateralized
  default the pool tops up the lender's shortfall up to a per-loan cap. Pool
  size + cap are governance knobs. New contract, owned by the Temporal Governor.

### 4.5 Other layers (tracked, not in this repo)

Backend pricing engine for tier × ratio × market; CLI flag for under-collat (or
implicit when `collateralAmount < principal`); frontend surfaces tier per
request and warns lenders when an offer is fillable by below-prime borrowers.

---

## 5. Off-chain attestation spec (deliverable for lunar-indexer / moonwell-ai)

This is the contract the off-chain service must satisfy. The on-chain
`CreditAttestation` struct/typehash must match it byte-for-byte.

### 5.1 EIP-712 schema

- **Domain:** reuse the marketplace domain — `name="MoonwellCreditMarketplace"`,
  `version="1"`, `chainId`, `verifyingContract = factory`. (The attestation is
  consumed by the factory, so binding it to the factory's domain prevents
  cross-contract replay.)
- **Type:**

  ```
  CreditAttestation(
    address subject,     // the borrower the report is about
    uint16  tier,        // mapped per §5.2
    uint16  score,       // 300–850, or 0 when insufficientHistory
    bytes32 reportHash,  // keccak256 over the canonical report JSON (see §5.3)
    uint64  issuedAt,
    uint64  validUntil   // keep SHORT — minutes, mirroring BackendTerms.validUntil
  )
  ```

- **Signer:** the `creditBureauAttestor` key, registered on the factory by
  governance. Rotate independently of `backendSigner` and the registry owner.

### 5.2 Canonical score → tier mapping (single source of truth)

| API `tier`                        | score band | on-chain `uint16` |
| --------------------------------- | ---------- | ----------------- |
| (unrated / `insufficientHistory`) | `null`     | `0`               |
| `deep_subprime`                   | `< 580`    | `1`               |
| `subprime`                        | `580–669`  | `2`               |
| `near_prime`                      | `670–739`  | `3`               |
| `prime`                           | `≥ 740`    | `4`               |

Both the registry sync and the attestation `tier` field use this mapping. The
factory's existing `minBorrowerCreditTier` comparison then works unchanged. Pin
the mapping in a shared constants module so API, indexer, and contracts can't
drift.

### 5.3 `reportHash`

`keccak256` over a **canonicalized** subset of the report (stable key order,
fixed decimal scaling) — e.g. `{subject, score, tier, windowDays, generatedAt}`.
The service returns both the raw report and the `reportHash`; the factory only
ever sees `reportHash` (bound into `BackendTerms.attestationReportHash`). This
lets a dispute reconstruct exactly which report underwrote a loan without
putting the full report on-chain.

### 5.4 Freshness & failure modes

- `validUntil` short (match `BackendTerms` — minutes), so a downgrade can't be
  outrun by a stale attestation.
- `insufficientHistory` ⇒ `tier=0, score=0`; such a borrower can only match
  tier-0 offers (i.e. the lender explicitly opted into "anyone"). Fail-closed.
- Attestor key compromise is bounded the same way the backend key is: short
  validity, governance rotation (`setCreditBureauAttestor`), pause guardian.

---

## 6. Testing plan

- **2a:** registry sync idempotency; tier-gated match happy/again-stale paths;
  score→tier mapping unit tests; attestation signature verification (EOA +
  EIP-1271).
- **2b:** versioned-typehash string test (catches signature breakage);
  undercollateralized forked-Base lifecycle (activate with
  `minCollateralizationBps < 10_000`, no LTV revert); default → `CreditDefault`
  emission; 4-signature failure matrix (bad/expired/mismatched attestation,
  `reportHash` mismatch); `CreditInsuranceVault` shortfall top-up + cap.
- Keep the forked-Base integration harness
  (`CreditMarketplaceIntegration.t.sol`) as the source of truth for
  real-Moonwell accrual.

## 7. Deployment / governance

- Phase 1 deploys via `script/DeployCreditMarketplace.s.sol`, which still has
  **placeholder** `BACKEND_SIGNER` / `FEE_RECIPIENT` / `TIER_REGISTRY_OWNER`
  (`0xBEEF…`, `0xFEE0…`, `0xC0DE…`). Replace before any mainnet deploy.
- There is **no governance MIP yet** for the §14.3 post-deploy checklist
  (whitelist mTokens/collateral, set staleness window, LTV buffer, default
  params, verify signer/recipient/guardian). Phase 2 should add a proper
  `mip-b##` proposal rather than relying on the forge script alone.
- 2b adds `setCreditBureauAttestor` and (option 2) `CreditInsuranceVault`
  deployment + funding to the governance surface.

## 8. PR sequence

| #   | Title                             | Contents                                                                                               |
| --- | --------------------------------- | ------------------------------------------------------------------------------------------------------ |
| 0   | Audit hardening (this branch)     | MATCH-01/F-03 bounds, ACCT-02 default-path, CDM-02 stale-oracle hatch + tests ✅                       |
| 1   | Registry sync + freshness         | off-chain signed-attestation endpoint; `CreditTierRegistry` freshness fields; score→tier constants     |
| 2   | Governance MIP                    | `mip-b##` post-deploy checklist + real signer/recipient/owner addresses                                |
| 3   | Attestation type + attestor role  | `CREDIT_ATTESTATION_TYPEHASH`, `creditBureauAttestor`, `BACKEND_TERMS_TYPEHASH_V2`, 4-sig `createLoan` |
| 4   | `CreditLoanV2`                    | undercollateralized activation + `CreditDefault`; deploy via `setCreditLoanImplementation`             |
| 5   | `CreditInsuranceVault` (option 2) | fee-funded coverage + governance wiring                                                                |
| 6   | Mainnet beta                      | prime-only, ≥50% collat, lender-eats-it; backend pricing + frontend                                    |

## 9. Open decisions / legal

- **Legal review** is the gate for 2b (undercollateralized agent-to-agent credit
  is scrutinized territory — spec §18 flags counsel involvement).
- Insurance-pool sizing and per-loan shortfall cap (option 2) — governance.
- Whether to also let the **borrower** trigger the post-grace unwind (ACCT-03),
  so a fully-performing borrower isn't dependent on the lender to free
  collateral — worth folding into `CreditLoanV2`.
