# ChainlinkOEV Loan Feed Desync Fix — Design

**Date:** 2026-04-24 **Branch:** `feat/chainlink-oev-fix` **Bounty reference:**
[code-423n4/moonwell-bug-bounty-submissions#150](https://github.com/code-423n4/moonwell-bug-bounty-submissions/issues/150)
(duplicates: #170, moonwell-bug-bounty#210, #211, #215, #217, #218, #221)
**Severity:** Medium (sponsor-acknowledged goodwill bounty — no funds at risk)

---

## 1. Problem Statement

Both `ChainlinkOEVWrapper` and `ChainlinkOEVMorphoWrapper` expose a
`_getLoanTokenPrice` helper used by `_calculateCollateralSplit` to price the
loan side of a liquidation. The in-code comment on the Core wrapper claims the
helper "bypasses any OEV wrapper to get fresh price data, preventing price
staleness exploits," but the implementation does the opposite:

```solidity
AggregatorV3Interface loanFeed = chainlinkOracle.getFeed(loanToken.symbol());
(, int256 loanAnswer, , , ) = loanFeed.latestRoundData();
```

`chainlinkOracle.getFeed(symbol)` returns whatever address is registered for
that symbol in the `ChainlinkOracle`. If the registered feed is itself an OEV
wrapper, `latestRoundData()` applies that wrapper's OEV-delay logic and returns
a _delayed_ price. Meanwhile the collateral side of the same liquidation reads a
_fresh_ price directly from the wrapper's own `priceFeed.latestRoundData()`.

### Impact

- Fresh collateral price vs stale loan price → incorrect `repayUSD` in
  `_calculateCollateralSplit` → incorrect fee split between liquidator and
  protocol.
- Overestimated loan price → `repayUSD` inflated → liquidator fee grows,
  protocol shrinks.
- Underestimated loan price → `repayUSD` deflated → liquidator fee shrinks,
  protocol grows.
- No liquidation-correctness or funds-at-risk impact — Morpho/Moonwell core use
  their own market-level oracles for the insolvency check; the OEV wrapper's
  split math is purely a post-liquidation accounting distribution.

### Secondary bug (Morpho wrapper only)

`ChainlinkOEVMorphoWrapper._getLoanTokenPrice` only checks `loanAnswer > 0`. The
Core wrapper's equivalent calls `_validateRoundData` which additionally checks
`updatedAt != 0` and `answeredInRound >= roundId`. This is a parity gap — the
Morpho wrapper should validate the loan round the same way.

---

## 2. Scope

**In scope:**

1. Fix the desync in `ChainlinkOEVWrapper._getLoanTokenPrice`.
2. Fix the desync in `ChainlinkOEVMorphoWrapper._getLoanTokenPrice`.
3. Restore `_validateRoundData` parity in
   `ChainlinkOEVMorphoWrapper._getLoanTokenPrice`.
4. Unit + integration tests covering both fixes.
5. Governance MIP to redeploy `ChainlinkOEVWrapper` on Base and Optimism and
   upgrade the `ChainlinkOEVMorphoWrapper` proxy on Base.
6. Address registration in `chains/8453.json`, `chains/10.json`, and
   `proposals/Addresses.sol`.

**Explicitly out of scope:**

- Generic Chainlink staleness heartbeat checks (M-02 from the 2023 audit, OOS
  per bounty scope).
- Chainlink L2 Sequencer Uptime feed checks (M-03 from the 2023 audit, OOS per
  bounty scope).
- Any refactor of `_getCollateralTokenPrice`, the `latestRoundData()`
  round-decrement loop, or the liquidation core flow.
- Any changes to external function signatures or event ABIs.

---

## 3. Architecture

### 3.1 Shared interface

New file: `src/oracles/IOEVWrapperFeed.sol`

```solidity
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import { AggregatorV3Interface } from "./AggregatorV3Interface.sol";

interface IOEVWrapperFeed {
  function priceFeed() external view returns (AggregatorV3Interface);
}
```

Both `ChainlinkOEVWrapper` and `ChainlinkOEVMorphoWrapper` already expose a
public `priceFeed` state variable, so they satisfy this interface with no
additional changes.

### 3.2 Deref helper

Add an internal view helper to each wrapper:

```solidity
/// @notice Resolve a feed registered in ChainlinkOracle down to its raw
///         Chainlink aggregator, single-hop.
/// @dev If the registry feed is itself an OEV wrapper (exposes priceFeed()),
///      returns the inner aggregator. Otherwise returns the input unchanged.
///      Deliberately single-hop to avoid recursion and match the registry
///      invariant (entries are raw or a single level of wrapping).
function _resolveRawFeed(
  AggregatorV3Interface registryFeed
) internal view returns (AggregatorV3Interface) {
  try IOEVWrapperFeed(address(registryFeed)).priceFeed() returns (
    AggregatorV3Interface inner
  ) {
    if (address(inner) != address(0)) {
      return inner;
    }
  } catch {
    // registry feed is a raw aggregator (no priceFeed() function) —
    // fall through and return the input.
  }
  return registryFeed;
}
```

Failure modes:

- **Registry feed is raw (no `priceFeed()`):** try reverts, catch swallows,
  returns input.
- **Registry feed is an OEV wrapper with a valid inner feed:** returns inner.
- **Registry feed is a wrapper but `priceFeed()` returns zero:** defensive
  fallback to the input (shouldn't happen with current wrappers which set
  `priceFeed` at construction/init).
- **Registry feed is `address(0)`:** try reverts on non-contract call → returns
  `address(0)` → later `latestRoundData()` reverts on empty code. Same failure
  mode as today.

### 3.3 No storage changes

No mappings, no setters, no new initializers. `ChainlinkOEVMorphoWrapper` does
not need `reinitializer(3)` — storage layout is unchanged.

---

## 4. Code Changes

### 4.1 `src/oracles/ChainlinkOEVWrapper.sol`

**Existing `_getLoanTokenPrice` (line 599-640):**

```solidity
AggregatorV3Interface loanFeed = chainlinkOracle.getFeed(
    underlyingLoan.symbol()
);
int256 loanAnswer;
{
    (uint80 roundId, int256 answer, , uint256 updatedAt, uint80 answeredInRound)
        = loanFeed.latestRoundData();
    _validateRoundData(roundId, answer, updatedAt, answeredInRound);
    loanAnswer = answer;
}
uint8 feedDecimals = loanFeed.decimals();
// ... scaling
```

**After:**

```solidity
AggregatorV3Interface registryFeed = chainlinkOracle.getFeed(
    underlyingLoan.symbol()
);
AggregatorV3Interface loanFeed = _resolveRawFeed(registryFeed);
int256 loanAnswer;
{
    (uint80 roundId, int256 answer, , uint256 updatedAt, uint80 answeredInRound)
        = loanFeed.latestRoundData();
    _validateRoundData(roundId, answer, updatedAt, answeredInRound);
    loanAnswer = answer;
}
uint8 feedDecimals = loanFeed.decimals();  // decimals from resolved feed
// ... scaling
```

Also: update the comment block on the function to accurately describe single-hop
deref behavior.

### 4.2 `src/oracles/ChainlinkOEVMorphoWrapper.sol`

**Existing `_getLoanTokenPrice` (line 496-528):**

```solidity
AggregatorV3Interface loanFeed = chainlinkOracle.getFeed(
    loanToken.symbol()
);
(, int256 loanAnswer, , , ) = loanFeed.latestRoundData();
require(loanAnswer > 0, "ChainlinkOEVMorphoWrapper: invalid loan token price");
```

**After:**

```solidity
AggregatorV3Interface registryFeed = chainlinkOracle.getFeed(
    loanToken.symbol()
);
AggregatorV3Interface loanFeed = _resolveRawFeed(registryFeed);
int256 loanAnswer;
{
    (uint80 roundId, int256 answer, , uint256 updatedAt, uint80 answeredInRound)
        = loanFeed.latestRoundData();
    _validateRoundData(roundId, answer, updatedAt, answeredInRound);
    loanAnswer = answer;
}
uint8 feedDecimals = loanFeed.decimals();
// ... scaling
```

This commit simultaneously fixes the desync (via `_resolveRawFeed`) and restores
validation parity (via `_validateRoundData`).

### 4.3 `src/oracles/IOEVWrapperFeed.sol`

New file as specified in §3.1.

### 4.4 No changes

- External function signatures on both wrappers — unchanged.
- Events — unchanged.
- Storage layout — unchanged.
- `_calculateCollateralSplit`, `_getCollateralTokenPrice`, `latestRoundData`,
  `getRoundData`, `updatePriceEarlyAndLiquidate` — unchanged.

---

## 5. Testing

### 5.1 Unit tests

Extend `test/unit/ChainlinkOEVWrapperTest.t.sol` and
`test/unit/ChainlinkOEVMorphoWrapperTest.t.sol` (create if absent):

1. **Raw-feed path:** registry returns a plain mock aggregator with no
   `priceFeed()` method. Assert `_getLoanTokenPrice` reads from it directly and
   the split matches expected.
2. **Wrapped-feed path:** registry returns a mock that exposes `priceFeed()`
   returning a different inner mock. Give the outer and inner different answers;
   assert the split uses the inner's price.
3. **Desync regression:** set up the exact failure — outer (wrapped) mock
   returns a delayed answer (simulating the OEV delay), inner returns a fresh
   answer. Assert the split uses the fresh price.
4. **Wrapper with zero `priceFeed()`:** defensive fallback — registry feed is a
   wrapper but its `priceFeed()` returns `address(0)`. Assert the registry feed
   itself is used (no revert, no deref-to-zero).
5. **Single-hop invariant:** mock whose `priceFeed()` itself points at another
   mock exposing `priceFeed()`. Assert only one hop is taken.
6. **Morpho validation parity:** three new cases in the Morpho test —
   `updatedAt == 0` reverts, `answeredInRound < roundId` reverts, `answer <= 0`
   continues to revert as before.

### 5.2 Integration tests

Extend `test/integration/`:

7. **Base fork (`PRIMARY_FORK_ID=8453`):** simulate WELL/USDC Morpho liquidation
   against live `ChainlinkOracle`. Assert the loan (USDC) price is sourced from
   the raw Chainlink USDC/USD aggregator, not via any intermediate wrapper.
8. **Base fork core market:** construct a scenario where a loan token's
   registered feed is a wrapper. Simulate WETH-collateral liquidation and assert
   the split matches the inner-price expectation.
9. **PostProposalCheck:** extend the proposal's `validate()` to check —
   - New wrapper addresses are live and owned by the correct admin.
   - `ChainlinkOracle.getFeed("WETH")` on Base and Optimism returns the new
     wrapper.
   - Morpho market's oracle `BASE_FEED_1` points at the upgraded wrapper (same
     address — proxy, impl changed).
   - Parameters (`liquidatorFeeBps`, `maxRoundDelay`, `maxDecrements`,
     `feeRecipient`, `owner`) are preserved.

### 5.3 Profiles

- Default: `forge test`
- CI: `FOUNDRY_PROFILE=ci forge test`

---

## 6. Deployment & Governance

### 6.1 Redeploys and upgrades

- **Base:** deploy new `ChainlinkOEVWrapper` for WETH/ETH (replaces
  `0xeb083d234ec636A10325ea42bCbbE09Aa56d1547`).
- **Optimism:** deploy new `ChainlinkOEVWrapper` for WETH/ETH (replaces
  `0x531f69127bB04Ebb0Fd321b8092d34a4C2B4E0f1`).
- **Base:** upgrade `ChainlinkOEVMorphoWrapper` proxy at
  `0xAEeE6335f50e1f8aF924DF0742b1879C9761F5f5` to a new implementation. Storage
  layout unchanged — no `reinitializer` call needed.

Parameters preserved from MIP-X38:

| Parameter          | Value |
| ------------------ | ----- |
| `liquidatorFeeBps` | 4000  |
| `maxRoundDelay`    | 10    |
| `maxDecrements`    | 10    |

`feeRecipient`, `owner`, `chainlinkOracle`, and `priceFeed` all carried forward
from the existing deployments.

### 6.2 MIP

Single cross-chain proposal `mip-x##` (governance hub is Moonbeam; executes on
Base and Optimism via Temporal). Steps:

1. **Base:**
   - Deploy new `ChainlinkOEVWrapper(WETH)`.
   - Call `ChainlinkOracle.setFeed("WETH", newWrapper)`.
   - Upgrade `ChainlinkOEVMorphoWrapper` proxy to new implementation.
2. **Optimism:**
   - Deploy new `ChainlinkOEVWrapper(WETH)`.
   - Call `ChainlinkOracle.setFeed("WETH", newWrapper)`.

Lifecycle: `deploy()` → `afterDeploy()` → `build()` → `simulate()` →
`validate()` (per `proposals/templates/`).

### 6.3 Files

- `proposals/mips/mip-x##/mip-x##.sh` — sets `JSON_PATH`, `DESCRIPTION_PATH`,
  `PRIMARY_FORK_ID=1`.
- `proposals/mips/mip-x##/mip-x##.json`
- `proposals/mips/mip-x##/mip-x##.md`
- `proposals/mips/mip-x##/mip-x##.sol` — proposal contract.
- `proposals/mips/mips.json` — new entry with `id: 0`.
- `chains/8453.json` — new `CHAINLINK_ETH_USD_OEV_WRAPPER` address; keep old
  under a deprecated suffix.
- `chains/10.json` — new `CHAINLINK_ETH_USD_OEV_WRAPPER` address; keep old under
  a deprecated suffix.
- `proposals/Addresses.sol` — loader additions if needed.

### 6.4 Deprecation

Old `ChainlinkOEVWrapper` addresses are retained in `chains/*.json` under a
deprecated key (`..._DEPRECATED`) for historical reference; not removed. The
upgraded Morpho wrapper keeps the same proxy address, so no deprecation entry
there.

---

## 7. Component Boundaries

- `_resolveRawFeed` has one responsibility: single-hop dereference of a registry
  feed to its raw Chainlink aggregator.
- `_validateRoundData` addition in the Morpho wrapper is a parity fix, not a new
  policy — same validation already exists in the Core wrapper.
- The new `IOEVWrapperFeed` interface is internal-facing; it does not change the
  external ABI of either wrapper.
- No public-surface changes mean integrations (Morpho oracle, Moonwell
  `ChainlinkOracle` registry, liquidator scripts) keep working without
  coordination.

---

## 8. Risks & Mitigations

| Risk                                                                                                                                                  | Mitigation                                                                                                                                                                                                   |
| ----------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Deref grabs an unexpected inner feed if a registry entry coincidentally exposes a `priceFeed()` method with the same selector but different semantics | Extremely narrow surface — the selector `priceFeed()` returning `AggregatorV3Interface` is effectively a Moonwell-internal convention. Integration tests on live addresses confirm the correct deref target. |
| New contract redeploy on Base/OP introduces a governance window where the old wrapper is still wired until `setFeed` lands                            | Standard MIP execution flow; Temporal governance ensures atomic per-chain cutover.                                                                                                                           |
| `ChainlinkOEVMorphoWrapper` upgrade has storage-layout bug                                                                                            | Zero storage changes in this revision. `reinitializer(3)` not invoked. Foundry upgrade-safety check should be run as part of CI.                                                                             |
| Tests pass locally but break on fork due to live registry differences                                                                                 | Fork integration tests in §5.2 exercise the live registry directly.                                                                                                                                          |
| Non-upgradeable Core wrapper redeploy orphans the old contract's token balances or allowances                                                         | Wrapper holds no persistent balances between liquidations (`updatePriceEarlyAndLiquidate` is end-to-end); any residual from `recoverERC20`/`recoverETH` admin pathway can be swept pre-cutover.              |

---

## 9. Acceptance Criteria

1. `forge build` passes, `forge test` passes with default and CI profiles.
2. `make slither` shows no new findings beyond baseline.
3. Desync regression test fails on `main` and passes on this branch.
4. Morpho validation-parity tests fail on `main` and pass on this branch.
5. `validate()` in the new MIP passes on Base and Optimism forks after
   `simulate()`.
6. Manual review confirms external ABI, events, and storage layout are unchanged
   on both wrappers.
