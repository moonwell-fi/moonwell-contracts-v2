# MAMO / USD Price Feed Deprecation Plan (MOO-1019)

Plan to stop depending on the Chainlink `MAMO / USD` feed on Base without
freezing user accounts or leaving the mMAMO wind-down mispriced.

All figures were measured on Base at block `52904291` (2026-10-21) with MAMO at
$0.00733.

## 1. What depends on the feed

| Consumer                                                     | Address                                                                                                                                               | Path to feed                                                           | Exposure                                                                                                                                                    |
| ------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Chainlink feed `CHAINLINK_MAMO_USD`                          | `0xeF7541b388a77C1709a3d44BfBfC5c1ED3F0Ac94`                                                                                                          | n/a (8 decimals, 24h heartbeat, 0.5% deviation threshold)              | Live: last update about 38 min before the measurement. No `shutdownDate` in Chainlink's Base feed directory.                                                |
| Core `ChainlinkOracle` → mMAMO                               | oracle `0xEC942bE8A8114bFD0396A5052c36027f2cA6a9d0`, feed slot `MAMO` = `CHAINLINK_MAMO_USD_OEV_WRAPPER` `0xDBD37C274A70A8A3f92A227c843a6a8d3203afe6` | `getFeed("MAMO")` → OEV wrapper → feed                                 | **High**: used for every liquidity check of every account that entered mMAMO                                                                                |
| Morpho oracle `MORPHO_CHAINLINK_MAMO_USD_ORACLE`             | `0x18d1325e8528E3ceafBf9a77F3bE3f76Fec42D5C`                                                                                                          | `BASE_FEED_1` = `CHAINLINK_MAMO_USD_ORACLE_PROXY` `0xF4DC…adb9` → feed | Dust: markets `0xace0…393d` ($13.8 collateral / $0.38 borrow) and `0x3ae2…6cea` ($0.09 / $0.003)                                                            |
| Morpho oracle `0x800e0d16…5ab3` (not in the registry)        | `BASE_FEED_1` = `0x98B14fc2…17De` (wrapper → same feed)                                                                                               | same feed                                                              | Dust: market `0xe6c4…1c24` ($0.04 collateral, $0 borrow)                                                                                                    |
| Mamo `SlippagePriceChecker` (`CHAINLINK_SWAP_CHECKER_PROXY`) | `0x5A8F10be44E25Bb21492C5f46DA94cDb1f0b2fF6`                                                                                                          | none on chain                                                          | None: 0 of 23 checker events reference MAMO or the feed. The `cbBTC → MAMO` route in `mamo-contracts` `008_MamoStakingV2Deployment.sol` was never executed. |
| Off-chain: `mamo-compounder`                                 | `src/dashboard/mamo-valuation.ts` (`MAMO_USD_FEED`), `src/helpers/mamo-reward-compounder.ts:258`                                                      | direct `latestRoundData`                                               | Dashboard and compounder USD valuation                                                                                                                      |

## 2. mMAMO market state

| Item                 | Value                                                                                                                                                                 |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Comptroller          | `UNITROLLER` `0xfBb21d0380beE3312B33c4353c8936a0F13EF26C`                                                                                                             |
| Collateral factor    | 0                                                                                                                                                                     |
| Supply / borrow caps | 1 / 1 (new mints and borrows are blocked)                                                                                                                             |
| Reserve factor       | 99% (MIP-X66)                                                                                                                                                         |
| IRM                  | `JUMP_RATE_IRM_MOONWELL_MAMO_MIP_X66`, flat 1% APR                                                                                                                    |
| Total borrows        | 3,471,498 MAMO (≈ $25.4k)                                                                                                                                             |
| Total reserves       | 1,908,040 MAMO (accounting only: the market's cash is ≈ 0)                                                                                                            |
| Owed to suppliers    | 1,563,458 MAMO (≈ $11.5k). Not redeemable until borrowers repay.                                                                                                      |
| Borrowers            | 55 accounts with debt, out of 120 historical borrowers. The 55 sum to 3,469,303 MAMO, which matches `totalBorrows` minus unaccrued interest, so the list is complete. |

Largest debts:

| Borrower                                     | Debt (MAMO) | USD     | Account status                                                    |
| -------------------------------------------- | ----------- | ------- | ----------------------------------------------------------------- |
| `0x81f6ae5bd24a31b0b28ffb4012e34d6a10761b3f` | 1,389,299   | $10,184 | **Healthy** EOA: $38.9k mUSDC collateral, $24.0k excess liquidity |
| `0x63cbedd61533d3ae8d9fa92e89acb74736cd98a5` | 843,411     | $6,182  | In shortfall                                                      |
| `0xb71159592228e3ddb132fb8d45fed2b7c0ae63af` | 381,196     | $2,794  | In shortfall                                                      |
| `0x2dfa972aa8fcedf3079137227d7dbabec731648a` | 348,188     | $2,552  | In shortfall                                                      |
| `0xd71dd9b6e634412713c47fe7ae02c628e338c384` | 230,130     | $1,687  | In shortfall                                                      |

25 of the 55 accounts are in shortfall: this is the bad debt that MIP-X66
references. `0x81f6…1b3f` is the only material position that is still
collateralised.

## 3. What breaks if the feed stops

`ChainlinkOracle.getChainlinkPrice` checks only `answer > 0` and
`updatedAt != 0`. It has **no staleness check**.
`ChainlinkOEVWrapper.latestRoundData` calls `priceFeed.latestRoundData()`
without `try/catch`. The feed can stop in two ways:

1. **The proxy keeps returning its last answer (frozen price).** Accounting
   keeps working, but the MAMO debt stays at the frozen value. If MAMO rallies,
   `0x81f6…1b3f` can redeem mUSDC down to the frozen requirement and walk away.
   For example, at 5× the real price, real debt is about $51k against about
   $11.6k of required collateral, roughly $39k of new bad debt.
2. **The proxy reverts or returns 0.** `getAccountLiquidity` reverts for every
   account that has mMAMO in `getAssetsIn`. Those accounts can no longer borrow,
   redeem collateral, or be liquidated in **any** market. This is the outcome to
   prevent.

Either way, Core cannot keep `feeds["MAMO"]` pointed at this feed when it shuts
down.

## 4. Plan

### Phase 0: confirm the trigger (owner: risk / BD, ~1 day)

- [ ] Who is requesting the shutdown, and when? Chainlink's directory shows no
      shutdown date, so this is either a Moonwell sponsorship decision or a
      notice not yet published. Get the date in writing. Every step below must
      land **before** it.
- [ ] Ask Chainlink whether, after deprecation, the proxy keeps the last answer
      (failure mode 1) or reverts (failure mode 2).

### Phase 1: reduce the live exposure (owner: risk, 1–3 weeks, no code)

- [ ] Ask `0x81f6…1b3f` to repay 1.39M MAMO (about $10.2k). It is the only debt
      that a frozen price could make worse, and it is healthy, so liquidation is
      not available.
- [ ] Optional: a governance repay of the bad-debt accounts from reserves. This
      is out of scope here: the reserves are illiquid MAMO, so it needs MAMO
      from outside.

### Phase 2: governance MIP on Base, cut Core off the feed (owner: eng, ~1 day to write plus ~7 days of governance)

Actions executed by `TEMPORAL_GOVERNOR` (the `ChainlinkOracle` admin, verified
on chain):

1. `ChainlinkOracle.setDirectPrice(MAMO, P)`. `getPrice` uses `prices[token]`
   whenever it is non-zero, so the feed is never read again. MAMO has 18
   decimals, so `P` is the USD price × 1e18. The spot value today is
   `7332760000000000`.
   - Verified by `eth_call` from the TG: succeeds. A non-admin caller reverts
     `only admin may call`. Today `assetPrices(MAMO)` = 0, so no override is
     set.
2. Optional, for clarity on dashboards:
   `Comptroller._setMintPaused(mMAMO, true)` and
   `_setBorrowPaused(mMAMO, true)`. Caps of 1 already block both.

`validate()` should assert the following:

- `ChainlinkOracle.getUnderlyingPrice(mMAMO) == P`.
- Mock the feed and the OEV wrapper to revert, then check that
  `getAccountLiquidity(0x81f6…)` and one shortfall account still return without
  reverting. This proves Core no longer reads the feed.
- `getAccountLiquidity` for the top 5 borrowers is unchanged against a pre-MIP
  snapshot, within accrual drift.

Choosing `P` is a **decision** (see section 5).

### Phase 3: Morpho and the off-chain side (owner: eng, ~half a day)

- [ ] Morpho markets `0xace0…`, `0x3ae2…` and `0xe6c4…` hold under $15 in total.
      Morpho markets are immutable, so no action is possible. Announce that they
      freeze when the feed stops. Check that no Moonwell MetaMorpho vault has a
      non-zero cap on them, and set it to 0 if one does.
- [ ] `mamo-compounder`: replace `MAMO_USD_FEED` with a DEX price (the Aerodrome
      MAMO/USDC pool) or with a fail-soft path.
- [ ] Keep `CHAINLINK_MAMO_USD_OEV_WRAPPER` and
      `CHAINLINK_MAMO_USD_ORACLE_PROXY` in `chains/8453.json` until the feed is
      gone. After that, archive them following the `_DEPRECATED_Vn` pattern from
      MIP-X43.

### Phase 4: after the shutdown (owner: eng, ~1 hour)

- [ ] On a fork after the shutdown block, run `getAccountLiquidity` for all 55
      borrowers and confirm none revert.
- [ ] Update the price override only through governance. There is no automation:
      `P` is a fixed value until the market reaches 0 borrows.

## 5. Open decisions

| #   | Decision                                    | Options                                                                                                                                                                   | Recommendation                                                                                                                                 |
| --- | ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| D1  | Value of `P`                                | (a) spot at the time of writing; (b) a conservative multiple (for example 2–3× spot), which raises the collateral that `0x81f6` must keep; (c) a TWAP oracle on Aerodrome | (a) if `0x81f6` has repaid by Phase 2; otherwise (b). (c) needs a new contract and a manipulation review, which is overkill for a $25k market. |
| D2  | Order between Phase 1 and the shutdown date | Wait for the repay, or ship Phase 2 regardless                                                                                                                            | Ship Phase 2 regardless. A revert at shutdown freezes accounts; a frozen price only risks one bounded position.                                |
| D3  | Who sponsors and requests the shutdown      | n/a                                                                                                                                                                       | Confirm in Phase 0.                                                                                                                            |

## 6. Reproducing the measurements

```bash
set -a; . .env; set +a
M=0x2F90Bb22eB3979f5FfAd31EA6C3F0792ca66dA32   # mMAMO
C=0xfBb21d0380beE3312B33c4353c8936a0F13EF26C   # UNITROLLER
cast call $M "totalBorrows()(uint256)" --rpc-url "$BASE_RPC_URL"
cast call $C "getAccountLiquidity(address)(uint256,uint256,uint256)" 0x81f6ae5bd24a31b0b28ffb4012e34d6a10761b3f --rpc-url "$BASE_RPC_URL"
cast logs --from-block 30000000 --address $M "Borrow(address,uint256,uint256,uint256)" --rpc-url "$BASE_RPC_URL" --json
```

Note: query the `UNITROLLER` proxy. `COMPTROLLER` in `chains/8453.json` is the
implementation and returns empty storage.
