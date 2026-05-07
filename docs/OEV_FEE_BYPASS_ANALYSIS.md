# OEV Fee Bypass — Analysis of C4 Issue #195

**Source:**
[code-423n4/moonwell-bug-bounty-submissions#195](https://github.com/code-423n4/moonwell-bug-bounty-submissions/issues/195)
**Title:** OEV Fee Bypass via Permissionless Auxiliary Morpho Market
**Contract:** `src/oracles/ChainlinkOEVMorphoWrapper.sol` **Status:** Triage —
submitter claims High; reviewer suggests Medium; this analysis recommends
Medium.

---

## Summary

`ChainlinkOEVMorphoWrapper.updatePriceEarlyAndLiquidate()` advances
`cachedRoundId` (unlocking the fresh Chainlink price for every consumer of
`latestRoundData()`) on any successful call, regardless of which Morpho market
is passed in. The only validation is that
`marketParams.oracle.BASE_FEED_1() == address(this)`. Because Morpho Blue
markets and `MorphoChainlinkOracleV2` oracles are permissionless, an attacker
can construct a throwaway market that satisfies this check, self-liquidate a
dust position, and unlock the fresh price while paying ~zero protocol fee. They
(or any other liquidator) can then liquidate real Moonwell-Morpho positions
through Morpho Blue's standard `liquidate()` at the freshly unlocked price —
entirely bypassing the OEV split.

## Verified Technical Claims (vs. on-chain code)

| Claim                                                                                | Result    |
| ------------------------------------------------------------------------------------ | --------- |
| L392-397 only checks `BASE_FEED_1() == address(this)`; no market allowlist           | confirmed |
| L414 sets `cachedRoundId = roundId` unconditionally on success                       | confirmed |
| Morpho oracle factory and `createMarket` are permissionless                          | confirmed |
| Dust seizure → `protocolFee = 0` via L590-594 short-circuit                          | confirmed |
| `_calculateCollateralSplit` uses real prices for both legs (not the attacker oracle) | confirmed |

## Exploit Path (two-step, two markets)

**Step 1 — Unlock price via dummy market**

```solidity
wrapper.updatePriceEarlyAndLiquidate(attackerMarket, attacker, 1, ...);
```

- Attacker created `attackerOracle` via the permissionless Morpho factory with
  `baseFeed1 = wrapper`.
- Attacker created `attackerMarket` via `morphoBlue.createMarket(...)` using
  that oracle.
- Inside the wrapper:
  - L392-397 check passes.
  - L414 sets `cachedRoundId = newRoundId`. ← side effect on shared state.
  - L432-438 calls `morphoBlue.liquidate(attackerMarket, ...)` — only the dust
    market is touched.
- `_calculateCollateralSplit` returns `protocolFee = 0` because
  `collateralUSD = 1 wei × realWELLprice / 1e18` truncates to 0.

**Step 2 — Liquidate real victim through Morpho Blue directly**

```solidity
morphoBlue.liquidate(realMoonwellMarket, realVictim, seizedAssets, 0, "");
```

- Reads the real market's oracle → which reads the wrapper's
  `latestRoundData()`.
- L240 condition `roundId != cachedRoundId` is now **false** (just synced in
  Step 1) → wrapper returns the fresh price with no delay.
- Real victim is underwater at the fresh price → liquidation succeeds at the
  full Morpho 1.05× bonus.
- The OEV-split logic only runs inside `updatePriceEarlyAndLiquidate`; native
  Morpho Blue `liquidate()` knows nothing about it.

## PoC Quality Notes

The submitted Foundry test relies on
`vm.mockCall(attackerOracle, price.selector, abi.encode(1))` to force the
position underwater. On mainnet, `vm.mockCall` is unavailable; an attacker would
have to engineer the oracle factory inputs (`baseTokenDecimals`,
`quoteTokenDecimals`, `*VaultConversionSample`) so that
`MorphoChainlinkOracleV2.price()` returns a near-zero value while
`BASE_FEED_1 = wrapper` still holds. This is plausible (those parameters are
factory inputs, not enforced to match real token decimals) but is **not**
demonstrated by the submitted PoC. Before paying out, request a non-mocked PoC
that constructs a self-liquidating dust position end-to-end on a Base fork.

## Severity Assessment — Medium (not High)

- No theft of user or protocol principal.
- No insolvency risk.
- Liquidations on real markets still execute correctly.
- What's lost is **OEV revenue** — the entire purpose of the wrapper.

This maps to "function/availability impacted; assets not at risk" → Medium. The
bypass nullifies the wrapper's design intent, which is material, but is
opportunity cost rather than asset loss.

## Mitigation Analysis

### Option A — Minimum protocol-fee floor (partial mitigation, NOT recommended as primary)

```solidity
require(protocolFee >= minProtocolFee, "fee too low");
```

Why this only partially works:

- `_calculateCollateralSplit` uses **real prices** for both legs, so the
  attacker can't manipulate the fee math via their malicious oracle.
- However, the attacker can scale up `seizedAssets` to clear the floor; the
  seized collateral is their own self-supplied WELL, of which 30% returns to
  them as `liquidatorFee` (they are `msg.sender`) and the remainder goes to
  `feeRecipient`.
- Net cost to attacker ≈ `protocolFee` (≈ the floor amount, in WELL).
- If real OEV per round > floor, the bypass is still profitable.
- A floor pegged to expected OEV is impractical (varies per round, per market).

Effectively the floor becomes a fixed per-round tax: protocol captures the
floor, attacker keeps the surplus.

### Option B — Market allowlist (recommended primary fix)

```solidity
mapping(bytes32 => bool) public approvedMarkets;
event MarketApproved(bytes32 indexed id, bool approved);

function setApprovedMarket(bytes32 marketId, bool approved) external onlyOwner {
    approvedMarkets[marketId] = approved;
    emit MarketApproved(marketId, approved);
}

function updatePriceEarlyAndLiquidate(MarketParams memory marketParams, ...) external {
    bytes32 id = keccak256(abi.encode(marketParams));
    require(approvedMarkets[id], "ChainlinkOEVMorphoWrapper: market not approved");
    // ... existing logic
}
```

Wrappers are deployed per-feed, so the legitimate market(s) using each wrapper
are known and finite at deploy time. Forcing every successful call to be on an
approved market means any `cachedRoundId` advance is by definition a _real_
liquidation generating real OEV split. No dust path is possible.

### Option C — Defense-in-depth (allowlist + floor)

Use the allowlist as the gate, plus a small floor as a safety net in case an
approved market is misconfigured or its oracle is attacked.

## Recommended Action

1. **Primary fix:** market allowlist on `updatePriceEarlyAndLiquidate`.
2. Add `MarketApproved(bytes32 indexed id, bool approved)` event so
   governance/monitoring can audit approvals.
3. Wire initial allowlist into the existing initializer pattern via
   `reinitializer(3)` taking `bytes32[] _approvedMarkets`, so the upgrade flips
   the gate and seeds approvals atomically (otherwise legitimate liquidations
   break the moment the gate goes live).
4. Optional: minimum protocol-fee floor as defense-in-depth.

## Reference — Verified Code Locations

- Only check on `marketParams`:
  `src/oracles/ChainlinkOEVMorphoWrapper.sol:392-397`
- Round-id advance: `src/oracles/ChainlinkOEVMorphoWrapper.sol:414`
- Delay logic that consults `cachedRoundId`:
  `src/oracles/ChainlinkOEVMorphoWrapper.sol:239-266`
- Dust → zero-fee short-circuit:
  `src/oracles/ChainlinkOEVMorphoWrapper.sol:590-594`
- Real-price fee math (immune to attacker oracle):
  `src/oracles/ChainlinkOEVMorphoWrapper.sol:496-561`
