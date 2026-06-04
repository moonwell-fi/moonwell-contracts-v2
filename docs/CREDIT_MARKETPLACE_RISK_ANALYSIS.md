# Credit Marketplace — Lender Risk & Bad-Debt Analysis (Phase 1)

> Quantitative risk analysis of the overcollateralized credit delegation
> marketplace (PR #629). Combines **exact contract simulation on a forked Base**
> with real Moonwell (`test/integration/marketplace/sim/CreditRiskSim.t.sol`)
> and a **Monte-Carlo expected-loss model** grounded in those simulated
> outcomes. Live Moonwell USDC parameters at time of writing: borrow APR
> **45.6%**, supply APR **38.8%**, utilization **94%**, mUSDC collateral factor
> **0.88**, liquidation incentive **10%**, close factor **50%**.

---

## 0. TL;DR

1. **In Phase 1 the lender bears 100% of the credit risk.** The marketplace
   protocol (factory, clones, fee recipient) takes **no** bad debt — clones are
   isolated and the protocol routes value, never holds principal. Moonwell takes
   bad debt only in an extreme, low-probability edge case (§5).
2. **The lender is short a put on the borrower's collateral.** A rational
   borrower repays when the collateral is worth more than the debt and walks
   away (defaults) when it is worth less. The lender's protection is the
   **origination buffer only** (`minOriginationLtvBufferBps`, default 10%). The
   20% over-seizure does **not** protect principal — it only covers missed
   _interest_.
3. **The effective buffer is smaller than the nominal one.** Moonwell's borrow
   accrual eats into it: at today's 45.6% borrow APR the **break-even collateral
   drop is ~5–8%** (vs a nominal 10% buffer), worse the longer the loan runs.
4. **The flat 10% buffer is mispriced for volatile collateral, and the APR floor
   is not a profitability guarantee.** The floor only forces marketplace APR ≥
   Moonwell APR (≈0 net spread at `aprFloorBufferBps = 0`). At a realistically-
   priced loan, the lender's **expected PnL is negative for anything more
   volatile than a stablecoin at the 10% minimum** (even low-vol collateral).
   For BTC-class collateral the lender needs a **~72%/yr net spread** (or a ~30%
   buffer) just to break even. Profitability requires the buffer to scale with
   `σ × √term` **or** a net spread ≥ the break-even (§5) — neither enforced
   today.
5. **Second loss axis: Moonwell liquidation of the clone (§5).** If the lender
   pledges too little mUSDC (or mUSDC's CF is cut), the clone's own Moonwell
   position can be liquidated, costing the lender ~**10% of the borrowed
   principal** (the liquidation incentive) — independent of the borrower.
6. **Third loss axis: settlement insolvency (§6).** The on-chain APR floor
   validates the `apr` _field_, but the borrower's payments come from the
   `schedule`, which is **not** checked against Moonwell's accrual. A schedule
   that under-prices the borrow makes `_settle` revert and forces the lender to
   eat the Moonwell cost.

---

## 1. The three loss axes

| Axis                                                  | Trigger                                                       | Who loses                            | Magnitude                                       | Protection                                                |
| ----------------------------------------------------- | ------------------------------------------------------------- | ------------------------------------ | ----------------------------------------------- | --------------------------------------------------------- |
| **A. Borrower default w/ collateral crash** (primary) | collateral falls below the debt; borrower rationally defaults | **Lender**                           | up to ~full debt (≈100%+ of principal)          | origination buffer only                                   |
| **B. Moonwell liquidation of the clone**              | clone health < 1 (thin mUSDC pledge, CF cut, rate drag)       | **Lender**                           | ~10% of borrowed principal per full liquidation | lender's mUSDC headroom (unchecked on-chain)              |
| **C. Settlement insolvency**                          | `schedule` interest < Moonwell borrow accrual over the term   | **Lender** (must fund the shortfall) | the accrual shortfall; recoverable, ugly UX     | backend must size the schedule; APR floor is insufficient |

The marketplace protocol itself is **never** a loss-bearer in Phase 1 (§7.2).

---

## 2. Methodology

- **Exact contract simulation** (`CreditRiskSim.t.sol`, forked Base, real
  Moonwell mUSDC + real Chainlink): originate a loan at the **protocol-minimum**
  110% collateralization, move the collateral price, drive a borrower default,
  run the lender's full recovery (clawback → `seizeAll` →
  `repayLoanAfterDefault` → `redeemAndReturn`), and measure the lender's
  realized USD PnL. This is ground truth — every value flow is the real contract
  on real Moonwell.
  - Lender marketplace PnL =
    `(interest received − USDC injected to repay Moonwell) + (seized collateral valued at the crashed price)`.
    The pledged mUSDC and its supply yield are returned in full (no Moonwell
    liquidation in this axis) and are the lender's always-on baseline, so they
    are excluded.
- **Monte-Carlo expected loss** (400k paths, appendix script): collateral price
  is GBM over a 35-day term; a rational borrower defaults at maturity iff the
  collateral is worth less than the Moonwell debt; lender loss-given-default =
  `max(0, debt − collateralValue)` — the same loss function the simulation
  produces. This yields P(default), E[loss], tail risk (CVaR95), and E[lender
  PnL] across collateral volatilities and buffers.

Assumptions / bounds: the MC models **maturity (European) default** — a
conservative upper bound; a borrower who defaults the instant they go underwater
(and a lender who seizes instantly) realizes less. The grace period + 2-miss
default ladder add a real seizure lag in the other direction. Drift is set to
zero (volatility-only). E[lender PnL] folds in the simulation's interest spread
(~$31 on a rich test schedule) and is therefore _optimistic_ for the lender; the
loss-side metrics (P, E[loss], CVaR) are schedule-independent and are the robust
risk numbers.

---

## 3. Scenario results (exact, forked Base)

Loan: principal **$400 USDC**, collateral sized to the **protocol-minimum 110%**
(~$441 of cbBTC), term 30d (4 weekly interest installments + final), 20%
over-seizure, 5% fee, loan APR priced just above Moonwell's live 45.6%.

### 3.0 Happy path (borrower repays in full)

| Borrower pays   | Lender receives | Fee   | Moonwell borrow accrual |
| --------------- | --------------- | ----- | ----------------------- |
| $50.00 interest | **$31.02**      | $1.63 | **$17.34**              |

The lender's profit = scheduled interest − Moonwell borrow cost − fee.
Moonwell's 45.6% borrow APR consumes a third of the interest over the term.
(Conservation: 31.02 + 1.63 + 17.34 = 49.99 ≈ 50.)

### 3.1 Collateral crash + early strategic default

The borrower pays nothing and misses two installments (default at ~day 15):

| Collateral drop | Lender PnL   | % of principal |
| --------------- | ------------ | -------------- |
| 0%              | **+$33.89**  | +8.5%          |
| 5%              | +$11.82      | +3.0%          |
| **10%**         | **−$10.25**  | **−2.6%**      |
| 15%             | −$32.31      | −8.1%          |
| 20%             | −$54.38      | −13.6%         |
| 30%             | −$98.51      | −24.6%         |
| 50%             | **−$186.77** | **−46.7%**     |

- **Break-even ≈ 7.7% collateral drop** (early default, ~15-day accrual). The
  nominal 10% buffer is eroded ~2.3pts by Moonwell's borrow accrual. A
  **full-term default (35 days)** erodes it further to ~**5.1%**.
- **Loss is linear** beyond break-even at ~1% of the collateral (~$4.4) per 1%
  additional drop, up to the full debt (~100%+ of principal) as collateral → 0.
- **A default with the collateral intact is _profitable_ for the lender** (+8.5%
  at 0% drop — they keep the buffer). The borrower only defaults when it hurts
  the lender — see §4.
- **Over-seizure (20%) is irrelevant here.** It applies only to the missed
  _interest_ (~$10/installment), not the principal-scale shortfall. Confirmed in
  simulation: the seize math moves ~$24 of collateral on the two misses; the
  principal-scale loss comes entirely from the eroded origination buffer.

**Unwind mechanics (precision notes):**

- The lender receives 100% of the collateral units **minus `keeperBountyBps`**
  (≤1%, governance-set, 0 in these sims) routed to whoever calls
  `claimMissedPayment` — a sub-dollar, lender-adverse carve.
- **No marketplace fee is charged on the default path.** `_settle`'s fee branch
  is never reached on default; `redeemAndReturn` sweeps 100% of any pre-default
  interest the borrower paid to the lender. The `feeRecipient` earns nothing
  when a loan defaults.
- `redeemAndReturn` gates on `borrowBalanceStored != 0` while
  `repayLoanAfterDefault` repays `borrowBalanceCurrent`. A lender who repays the
  exact owed amount and then calls `redeemAndReturn` in a _later_ block hits a
  re-accrued dust borrow → `MoonwellBorrowOutstanding` revert, temporarily
  stranding their mUSDC until they top up the dust. **Over-fund the repay (or
  repay + redeem atomically)** — the sim funds `owed + 1e6` in one transaction.

---

## 4. Borrower gaming = a free put option

The borrower deposits collateral worth ~110% of the principal and receives the
principal in cash. Their rational strategy:

- **Collateral ≥ debt:** repay (keep the appreciated/intact collateral, pay the
  scheduled interest). The lender earns the spread.
- **Collateral < debt:** default — keep the borrowed cash, forfeit the
  now-cheaper collateral. The lender is forced to "buy" the collateral at the
  debt price and eats `debt − collateralValue`.

This is a **short put** held by the lender, struck at ≈ the debt. The 10% buffer
is the premium baked into over-collateralization; the scheduled interest is
additional premium. The borrower **cannot** profitably game the _mechanics_
beyond exercising this put — `claimMissedPayment` over-seizes a premium on every
miss, `missedCount` resets don't extend the term (fixed due dates), and the
collateral token is governance-whitelisted (no self-dealing). The only "gaming"
is the rational exercise of the embedded put, which the protocol prices solely
via the buffer.

**Credit tier does not neutralize this.** `minBorrowerCreditTier` screens out
low-reputation borrowers, but a _prime_ borrower with a collapsed collateral is
equally rational to default. Tier gating reduces operational/willful default,
not the structural short-put exposure.

---

## 5. Expected loss (averages) vs collateral volatility & buffer

Monte-Carlo, 400k paths, 35-day term, debt at maturity = $417.5 (= $400 + 4.4%
Moonwell accrual). **Lead with the schedule-independent loss metrics
(P(default), E[loss], CVaR95)** — these are robust. The two `E[PnL]` columns are
schedule-_dependent_ and bracket the truth: `E[PnL]@$2` assumes a realistically-
priced loan whose interest barely clears the APR floor (≈0 net spread after
Moonwell + the 5% fee — the _enforceable_ minimum), and `E[PnL]@$31` assumes the
rich test schedule. The **break-even net spread** is the decision metric: the
interest the lender must net _above_ Moonwell's borrow cost, per loan, just to
offset expected default losses.

| Collateral (σ)     | Buffer  | P(default) | E[loss]/P | CVaR95/P  | Break-even net spread | E[PnL] @ $2 | E[PnL] @ $31 |
| ------------------ | ------- | ---------- | --------- | --------- | --------------------- | ----------- | ------------ |
| Stable ~5%         | 10%     | 0.0%       | 0.00%     | 0.0%      | $0 (0%/yr)            | +$2.0       | +$31.0       |
| Low-vol ~20%       | 10%     | 20.8%      | 0.73%     | 7.7%      | $3.7 (10%/yr)         | **−$1.3**   | +$21.6       |
| Low-vol ~20%       | 20%     | 1.3%       | 0.03%     | 0.6%      | $0.1 (0%/yr)          | +$1.9       | +$30.5       |
| **BTC ~50%**       | **10%** | **39.7%**  | **4.18%** | **25.3%** | **$27.7 (72%/yr)**    | **−$15.5**  | +$2.0        |
| BTC ~50%           | 20%     | 20.5%      | 1.73%     | 18.0%     | $8.7 (23%/yr)         | −$5.3       | +$17.7       |
| BTC ~50%           | 30%     | 9.0%       | 0.64%     | 10.9%     | $2.8 (7%/yr)          | −$0.7       | +$25.7       |
| **Volatile ~100%** | **10%** | 49.5%      | 10.58%    | 48.7%     | $83.8 (218%/yr)       | −$41.3      | −$26.6       |
| Volatile ~100%     | 30%     | 29.0%      | 5.04%     | 38.6%     | $28.4 (74%/yr)        | −$18.7      | +$1.8        |
| **Memecoin ~150%** | **10%** | 54.8%      | 17.02%    | 66.0%     | $150.6 (393%/yr)      | −$67.2      | −$54.1       |
| Memecoin ~150%     | 30%     | 40.4%      | 11.01%    | 59.1%     | $73.9 (193%/yr)       | −$42.8      | −$25.6       |

**Reading it:**

- **Stablecoin collateral:** safe and profitable at any buffer.
- **The APR floor does not make lending profitable.** It only forces marketplace
  APR ≥ Moonwell APR (net spread ≈ 0 at `aprFloorBufferBps = 0`). At a
  realistically-priced loan (`E[PnL]@$2`), **the lender's expected PnL is
  negative for anything more volatile than a stablecoin at the 10% minimum** —
  even low-vol collateral (−$1.3). The rich-schedule column (+$2 to +$31) is
  what an _aggressively-priced_ loan would earn and should not be read as
  typical.
- **BTC-class at the 10% minimum:** ~40% of loans default, CVaR95 = 25% of
  principal, and the lender needs a **72%/yr net spread** (a ~117% APR loan)
  just to break even — far beyond what the floor enforces. A **30% buffer**
  drops the break-even spread to a realistic ~7%/yr.
- **Volatile / memecoin collateral:** break-even spreads of 70–390%/yr — not
  investable. Should be heavily over-collateralized (≥50%, see §7) or not
  listed.

The headline: **a flat 10% minimum is only safe for low-volatility collateral,
and the APR floor is not a profitability guarantee.** Lender profitability
requires _either_ a buffer scaled to `σ × √term` _or_ a net interest spread at
least equal to the break-even column — neither of which the protocol enforces
today. cbBTC's ~50% annual vol implies a ~15% one-sigma move over 35 days,
already larger than the ~5–8% effective buffer.

> **Caveat (model):** the GBM Itô term lowers the _median_ terminal price by ∝
> σ²T, which inflates `P(default)` at extreme σ — the >50% memecoin figures are
> partly this artifact, not pure dispersion. It is a conservative bias
> (overstates risk) and does not change the σ√term scaling conclusion; read the
> highest-vol `P(default)` as upper-leaning. `E[loss]` is martingale-preserved
> and unaffected.

### 5.1 Buffer design — concrete parameters

Solving the MC for the **minimum origination buffer** that holds
`E[loss] ≤ 1% of P` **and** `CVaR95 ≤ 10% of P` (a defensible per-loan risk
limit), at a 35-day term:

| Collateral (annual σ) | σ·√(35d) | **Required buffer**          | implied `k = buffer / (σ·√T)` |
| --------------------- | -------- | ---------------------------- | ----------------------------- |
| Stablecoin ~5%        | 1.5%     | **5%** (accrual floor binds) | 3.2                           |
| Low-vol ~20%          | 6.2%     | **10%** (≈ today's default)  | 1.6                           |
| cbBTC / ETH ~50%      | 15.5%    | **~33%**                     | 2.1                           |
| Volatile ~100%        | 31.0%    | **~88%**                     | 2.8                           |
| Memecoin ~150%        | 46.4%    | **>120%** (don't list)       | —                             |

**Design rule:** `requiredBufferBps ≈ max(1000, k·σ·√term) + borrowAPR·term`,
with `k ≈ 2` and the additive `borrowAPR·term` (~4.4% today) covering Moonwell
accrual. The current flat **10% is correctly calibrated for ~20%-vol
collateral** and is materially too thin for anything more volatile.

**The table above is the _target_ buffer; the design question is who sets it —
and a _static_ buffer is the wrong instrument.** Whether configured by
governance per token or signed by the lender per offer, a fixed value is (a)
operationally heavy to maintain per asset and (b) **stale by match time**,
because collateral volatility is time-varying: a calm asset can spike well past
its configured buffer before governance's ~5-day cycle — or a days-old resting
offer — can react. The buffer must be set against _live_ conditions at match
time.

Recommended split (it mirrors the existing trust model — precise pricing
off-chain, coarse enforcement on-chain):

1. **Backend pricing engine = the dynamic buffer.** It already de-facto sets the
   realized ratio (it chooses the offer×request match and the principal, then
   signs `BackendTerms`). Make it **volatility-aware** — size the required
   collateral per match from live realized/implied vol + liquidity. This is the
   only layer that can adapt fast enough.
2. **Short `BackendTerms.validUntil` (minutes) = freshness.** This is what keeps
   the backend's vol-priced quote from being executed after a regime change —
   the mechanism that makes a per-match buffer _stay_ accurate. (The spec
   already recommends a short `validUntil`; this is another reason.)
3. **On-chain = a coarse backstop by risk _class_, not per token.** Give
   `whitelistCollateralToken` a small risk-class enum (e.g.
   `stable / bluechip / longtail` → floors ~`5% / 25% / 75%`): governance
   maintains ~3 numbers and just **assigns a class** per token at whitelist
   (rarely changed). This bounds the backend-compromise worst case per asset
   class without pretending to track live vol on-chain; the existing global
   `minOriginationLtvBufferBps` becomes the floor-of-floors. Also cap **max
   term** per class (the buffer grows with `√term` and accrual linearly — long
   terms on volatile collateral compound both).
4. _(Optional)_ a lender-signed per-offer `minCollateralBufferBps` lets a
   conservative lender raise their personal floor — but it shares the same
   staleness limitation, so it's sugar, not the primary control.

A fully on-chain _dynamic_ buffer (vol derived from feed history or a vol
oracle) is possible but complex/gameable and lacks a clean oracle for long-tail
assets — Phase-2+, not now. The on-chain options are additive (new
enum/mapping + setter arg) and don't touch the clone layout or the EIP-712
typehashes. Until shipped, the backend must enforce the volatility-scaled buffer
and treat the on-chain floor strictly as a floor, **not** a target.

---

## 6. Bad-debt taxonomy — who actually eats it

### 6.1 The lender (the credit underwriter) — bears essentially all of it

- **Axis A** (§3, §4): collateral crash beyond the effective buffer. Quantified
  above. This is the dominant, structural exposure.
- **Axis B — Moonwell liquidation of the clone.** The clone supplies the
  lender's mUSDC (CF 0.88) and borrows the USDC principal. Its Moonwell health =
  `0.88 × pledgeValue / debt`. To originate, the lender must pledge ≥
  `P/0.88 ≈ 1.136 P`. **The marketplace does not enforce any headroom beyond
  Moonwell's own borrow check** — a lender who pledges the bare minimum starts
  at health 1.0 and is liquidatable on the first interest tick. Erosion from
  rate drag is modest (borrow 45.6% vs supply 38.8% ⇒ health decays ~0.6% over
  35 days), but a **CF cut** by Moonwell governance drops health proportionally
  and instantly. On liquidation a liquidator repays up to 50% (close factor) and
  seizes mUSDC at a **10% bonus**; clearing the full debt costs the lender ≈
  `(incentive−1) × debt = 10% × P` (~$40 on $400 ≈ 8.8% of the pledge). The 50%
  close factor means a single liquidation realizes ~5%, so a full clear takes ≥2
  passes. The borrower's escrowed collateral is untouched — this is a pure
  lender loss, additive to Axis A. _(This 10% figure is closed-form, not
  simulated — the harness deliberately over-pledges to isolate Axis A; a
  dedicated Axis-B liquidation sim is a worthwhile follow-up.)_
- **Axis C — settlement insolvency** (§7.3 in spec): `_checkAprFloor` validates
  the `apr` field, but payments come from `schedule.interestAmountPerPayment` /
  `finalPaymentAmount`, which are **not** validated against Moonwell's accrual.
  In fact the `apr` value is **dead storage** post-match — no payment or
  settlement code reads it; only the schedule drives cashflows. If the schedule
  under-prices the borrow (interest < accrual over the term), `_settle` (which
  runs only on the **final** payment) reverts `InsufficientPrincipalForRepay`
  and rolls that payment back; the loan stays `Active`. The lender recovers via
  `forceDefault` → `seizeAll` → `repayLoanAfterDefault` → `redeemAndReturn`,
  fronting principal-minus-paid-interest (then offset by the seized collateral)
  — i.e. **the lender alone funds the Moonwell-cost shortfall**. (This boundary
  is documented and exercised by the interest-amount fuzz `_minSolventInterest`,
  which deliberately stays in the solvent region once Moonwell's rate is ~45%; a
  ~$1-interest schedule cannot cover ~$17 of accrual.)

### 6.2 The marketplace protocol — no fund loss or bad debt

By design (§12.7 per-loan isolation): each loan is an isolated EIP-1167 clone
(independent storage, unique consumed `loanNonce` salt, `cloneDeterministic`
reverts on collision); the factory never custodies funds (transfers go
lender/borrower → clone directly); the `feeRecipient` only ever receives, and
only on the `_settle` happy path. No shared pool, no socialized loss. Phase 1
has **no protocol-level fund loss or bad debt**.

Two precision caveats on "bears nothing": (a) the protocol **forgoes** (does not
_lose_) fee revenue on every defaulted loan — the `feeRecipient` earns only on
settlement; (b) an abandoned/bricked clone strands the **lender's** capital
(pledged mUSDC + an accruing Moonwell debt that is eventually liquidated), never
the factory's or `feeRecipient`'s — the clone-bricking griefing vector imposes
no protocol-level cost. (Phase 2b's `CreditInsuranceVault` would deliberately
put protocol-pooled capital at risk for undercollateralized loans.)

### 6.3 Moonwell — bears bad debt only in an extreme edge case

Moonwell takes bad debt only if a clone's position is so underwater that seizing
**all** the mUSDC cannot cover the USDC borrow (`borrow > pledgeValue`). For a
same-asset USDC-supply/USDC-borrow position this requires borrow accrual to
exceed the entire pledge buffer — only at extreme rates × long terms × minimal
pledge **and** liquidators failing to act inside the 10% incentive band. Low
probability; the marketplace does not increase Moonwell's bad-debt surface
beyond any ordinary leveraged-supply position. (A USDC depeg moves both legs
together and does **not** by itself create relative insolvency.)

---

## 7. Recommendations

> **Shipped on-chain** (this PR, TDD'd): the trust-minimized backstops for #3,
> #4, and the coarse on-chain layer of #1 are now enforced at `createLoan`:
> **#3** `_checkScheduleSolvency` (schedule interest ≥ projected Moonwell
> accrual); **#1** per-collateral buffer floor (`setCollateralBufferBps` →
> effective buffer = `max(global, per-collateral)` in `_checkOriginationLtv`);
> **#4** `setMinMoonwellHealthBufferBps` → the clone's `activate` rejects a
> pledge that can't borrow `principal·(1+buffer)` without a Moonwell shortfall.
> All default to off/unchanged, so they're opt-in floors; the **dynamic,
> vol-aware** sizing (#1 main, #2) still belongs in the backend with a short
> `validUntil`.

1. **Size the buffer to _live_ volatility — not a flat 10% and not a static
   per-token value.** Target ≈ `2·σ·√term + borrowAPR·term` per match (§5.1: ~5%
   stable, ~33% BTC/ETH, delist memecoin), set **dynamically by the backend**
   with a **short `validUntil`** so quotes can't execute stale; back it on-chain
   with **coarse per-risk-class floors** (`stable/bluechip/longtail`) rather
   than a per-token number (vol is too time-variable to maintain per token). The
   APR floor alone (net spread ≈ 0) guarantees neither solvency nor
   compensation; equivalently, the lender must net ≥ the break-even spread (§5).
2. **Account for Moonwell accrual in the effective buffer.** At 45.6% borrow APR
   the nominal 10% becomes ~5–8% by default time. Either shorten max terms,
   require a larger buffer when Moonwell's borrow APR is high, or have the
   backend add `borrowAPR × term` to the required buffer.
3. **Enforce schedule solvency, not just the APR field.** Add an on-chain (or
   firmly-enforced backend) check that
   `Σ schedule interest ≥ projected Moonwell accrual over the term`. The current
   `_checkAprFloor` is necessary but not sufficient (it checks `apr`, not the
   schedule that actually drives payments).
4. **Enforce a lender-side Moonwell-health buffer.** The protocol lets a lender
   pledge the bare Moonwell minimum and get liquidated. Add a minimum
   pledge-to-principal ratio (e.g., require
   `pledgeValue ≥ principal / CF × (1 + healthBufferBps)`), or surface the
   clone's health prominently so backends never originate near 1.0.
5. **Over-seizure is interest insurance, not principal insurance.** Don't rely
   on `overSeizureBps` for collateral-crash protection; it only offsets missed
   installments. Principal protection is the buffer, full stop.
6. **Credit tier mitigates willful default, not the structural put.** Use
   `minBorrowerCreditTier` to screen operational risk; do not treat it as
   collateral-crash protection.
7. **Phase 2b note:** undercollateralized loans remove Axis A's buffer entirely
   — the lender (or `CreditInsuranceVault`) is then short a _naked_ put. The
   loss-absorption model (option 1 lender-eats-it → option 2 vault) must be
   sized against exactly these expected-loss numbers, restricted to prime tier,
   and capped (`minCollateralizationBps`) accordingly.

---

## 8. Reproduce

- **Contract simulation**
  (`test/integration/marketplace/sim/CreditRiskSim.t.sol` — outside the CI glob,
  env-gated):
  `RUN_RISK_SIM=true forge test --match-path 'test/integration/marketplace/sim/CreditRiskSim.t.sol' --match-test test_riskReport -vv`
  (forked Base; numbers vary with the live Moonwell rate and BTC price at the
  fork block — the _shape_ is invariant).
- **Monte-Carlo** (expected-loss table, §5):

```python
import math, random
random.seed(42)
P, borrowAPR, T = 400.0, 0.456, 35/365.0
N = 400_000
debtT = P*(1+borrowAPR*T)
def run(buffer_bps, sigma_annual):
    S0 = P*(1+buffer_bps/10000.0); sig = sigma_annual*math.sqrt(T)
    losses=[]; n_def=0; pnl=0.0; spread=31.0
    for _ in range(N):
        ST = S0*math.exp(-0.5*sig*sig + sig*random.gauss(0,1))
        if ST < debtT:
            n_def+=1; L=debtT-ST; losses.append(L); pnl+=-L
        else: pnl+=spread
    losses.sort(); allL=[0.0]*(N-len(losses))+losses; allL.sort()
    tail=allL[int(0.95*N):]
    return (n_def/N, sum(losses)/N/P*100, (sum(losses)/len(losses) if losses else 0)/P*100,
            sum(tail)/len(tail)/P*100, pnl/N)
```

---

*Generated from `CreditRiskSim.t.sol` (forked Base, real Moonwell) + the
Monte-Carlo model above. Live Moonwell parameters are volatile; re-run before
relying on absolute figures. The risk *structure* (lender short-put, buffer must
scale with volatility, protocol bears no bad debt) is invariant.*
