# Moonwell Contracts V2 — Test Coverage Audit Report

**Date:** 2026-02-24 **Scope:** All protocol-owned contracts across Base (8453),
Moonbeam (1284), Optimism (10), and testnets

---

## Executive Summary

| Metric                                                  | Count                                      |
| ------------------------------------------------------- | ------------------------------------------ |
| Protocol contracts (isContract: true) across all chains | ~500 (273 Base, 74 Moonbeam, 153 Optimism) |
| Source contracts (src/\*.sol)                           | 137                                        |
| Unit test files                                         | 37                                         |
| Integration test files                                  | 41                                         |
| Fuzz test files                                         | 1 (MultichainGovernanceFuzzing.t.sol)      |
| Invariant test files                                    | 1 (xWELLInvariant.t.sol)                   |

**Overall Assessment:** Core contracts (Comptroller, MToken, xWELL,
MultichainGovernor, TemporalGovernor) have strong unit + integration coverage.
Critical gaps exist in fuzz/invariant testing, newer market integrations, fee
splitter address-level coverage, and the Optimism deployment test coverage.

---

## 1. Source Contracts with NO Unit Tests

| Source File                                       | Category | Notes                                                         |
| ------------------------------------------------- | -------- | ------------------------------------------------------------- |
| `src/tokensale/TokenSaleDistributor.sol`          | Legacy   | 9 files, zero tests. Appears deprecated but still in codebase |
| `src/tokensale/TokenSaleDistributorProxy.sol`     | Legacy   | Same                                                          |
| `src/tokensale/TokenSaleDistributorStorage.sol`   | Legacy   | Same                                                          |
| `src/tokensale/ReentrancyGuard.sol`               | Legacy   | Same                                                          |
| `src/tokensale/SafeERC20.sol`                     | Legacy   | Same                                                          |
| `src/morpho/FeeSplitter.sol`                      | Morpho   | Only integration tests, no unit tests                         |
| `src/router/ERC4626EthRouter.sol`                 | Router   | Only integration tests, no unit tests                         |
| `src/MWethDelegate.sol`                           | Core     | Only integration tests via PostProposalCheck                  |
| `src/MErc20Delegator.sol`                         | Core     | Tested indirectly through integration tests only              |
| `src/Unitroller.sol`                              | Core     | Tested indirectly through Comptroller tests                   |
| `src/oracles/ChainlinkOracle.sol`                 | Oracle   | Only integration tests, no dedicated unit tests               |
| `src/oracles/ChainlinkBoundedCompositeOracle.sol` | Oracle   | Only integration tests                                        |
| `src/oracles/ChainlinkFeedOEVWrapper.sol`         | Oracle   | Only integration tests                                        |
| `src/oracles/ChainlinkOEVMorphoWrapper.sol`       | Oracle   | Only integration tests                                        |

---

## 2. Source Contracts with NO Integration Tests

| Source File                                   | Category | Risk                                                  |
| --------------------------------------------- | -------- | ----------------------------------------------------- |
| `src/tokensale/TokenSaleDistributor.sol`      | Legacy   | Low (deprecated)                                      |
| `src/tokensale/TokenSaleDistributorProxy.sol` | Legacy   | Low (deprecated)                                      |
| `src/irm/JumpRateModel.sol`                   | IRM      | Medium — tested indirectly but no dedicated fork test |
| `src/views/BaseMoonwellViews.sol`             | Views    | Low — abstract base tested via child contracts        |

---

## 3. Protocol Addresses with NO Test Coverage

### Newer Base Markets (never referenced in any test file)

These mToken markets from `chains/8453.json` are deployed on-chain but have
**zero dedicated test references**:

| Address Name       | Category | Risk                                           |
| ------------------ | -------- | ---------------------------------------------- |
| `MOONWELL_WELL`    | mToken   | **High** — newer market, no supply/borrow test |
| `MOONWELL_USDS`    | mToken   | **High** — newer market                        |
| `MOONWELL_TBTC`    | mToken   | **High** — newer market                        |
| `MOONWELL_LBTC`    | mToken   | **High** — newer market                        |
| `MOONWELL_VIRTUAL` | mToken   | **High** — newer market                        |
| `MOONWELL_MORPHO`  | mToken   | **High** — newer market                        |
| `MOONWELL_cbXRP`   | mToken   | **High** — newest market                       |
| `MOONWELL_MAMO`    | mToken   | **High** — newest market                       |
| `MOONWELL_AERO`    | mToken   | Medium — older but still no dedicated test     |
| `MOONWELL_EURC`    | mToken   | Medium                                         |
| `MOONWELL_wrsETH`  | mToken   | Medium                                         |
| `MOONWELL_weETH`   | mToken   | Medium                                         |

### Fee Splitters (zero test references to specific deployed addresses)

| Address Name                      | Chain    | Risk                                                  |
| --------------------------------- | -------- | ----------------------------------------------------- |
| `USDC_METAMORPHO_FEE_SPLITTER`    | Base     | **High** — fee flows never tested against real deploy |
| `WETH_METAMORPHO_FEE_SPLITTER`    | Base     | **High**                                              |
| `EURC_METAMORPHO_FEE_SPLITTER`    | Base     | **High**                                              |
| `USDC_METAMORPHO_FEE_SPLITTER_V2` | Base     | **High**                                              |
| `WETH_METAMORPHO_FEE_SPLITTER_V2` | Base     | **High**                                              |
| `EURC_METAMORPHO_FEE_SPLITTER_V2` | Base     | **High**                                              |
| `cbBTC_METAMORPHO_FEE_SPLITTER`   | Base     | **High**                                              |
| `meUSDC_METAMORPHO_FEE_SPLITTER`  | Base     | **High**                                              |
| `USDC_METAMORPHO_FEE_SPLITTER`    | Optimism | **High**                                              |

> Note: `FeeSplitterIntegration.t.sol` tests the FeeSplitter _contract logic_
> but deploys a fresh instance — it does NOT test any of these specific deployed
> fee splitter addresses.

### URD (Universal Reward Distributor)

| Address Name              | Chain | Risk                                    |
| ------------------------- | ----- | --------------------------------------- |
| `MOONWELL_METAMORPHO_URD` | Base  | Medium — reward distribution not tested |

### OEV Wrappers (newer deployments with no address-specific tests)

| Address Name                        | Chain | Risk   |
| ----------------------------------- | ----- | ------ |
| `CHAINLINK_BTC_USD_OEV_WRAPPER`     | Base  | Medium |
| `CHAINLINK_EURC_USD_OEV_WRAPPER`    | Base  | Medium |
| `CHAINLINK_WELL_USD_OEV_WRAPPER`    | Base  | Medium |
| `CHAINLINK_USDS_USD_OEV_WRAPPER`    | Base  | Medium |
| `CHAINLINK_TBTC_USD_OEV_WRAPPER`    | Base  | Medium |
| `CHAINLINK_VIRTUAL_USD_OEV_WRAPPER` | Base  | Medium |
| `CHAINLINK_MORPHO_USD_OEV_WRAPPER`  | Base  | Medium |
| `CHAINLINK_cbXRP_USD_OEV_WRAPPER`   | Base  | Medium |
| `CHAINLINK_MAMO_USD_OEV_WRAPPER`    | Base  | Medium |
| `DAI_ORACLE_OEV_WRAPPER`            | Base  | Medium |
| `CHAINLINK_USDC_USD_OEV_WRAPPER`    | Base  | Medium |
| `cbETHETH_ORACLE_OEV_WRAPPER`       | Base  | Medium |
| `CHAINLINK_AERO_ORACLE_OEV_WRAPPER` | Base  | Medium |

> Note: `ChainlinkOEVWrapperIntegration.t.sol` tests OEV wrapper logic but uses
> `Liquidations.sol` utility which only covers ETH/USD and a subset of wrappers.

### Morpho Oracle Infrastructure (no test coverage)

| Address Name                          | Chain | Risk   |
| ------------------------------------- | ----- | ------ |
| `MORPHO_CHAINLINK_WELL_USD_ORACLE`    | Base  | Medium |
| `MORPHO_CHAINLINK_MAMO_USD_ORACLE`    | Base  | Medium |
| `MORPHO_CHAINLINK_stkWELL_USD_ORACLE` | Base  | Medium |
| `CHAINLINK_WELL_USD_ORACLE_PROXY`     | Base  | Medium |
| `CHAINLINK_MAMO_USD_ORACLE_PROXY`     | Base  | Medium |
| `CHAINLINK_stkWELL_USD_ORACLE_PROXY`  | Base  | Medium |
| `CHAINLINK_ORACLE_PROXY_ADMIN`        | Base  | Medium |

### Bounded Composite Oracles

| Address Name                                       | Chain | Risk                                              |
| -------------------------------------------------- | ----- | ------------------------------------------------- |
| `REDSTONE_LBTC_BTC_CHAINLINK_BOUNDED_ORACLE_PROXY` | Base  | Medium — LBTC oracle uses Redstone, not Chainlink |
| `REDSTONE_LBTC_BTC_CHAINLINK_BOUNDED_ORACLE_IMPL`  | Base  | Medium                                            |

### Reserve Automation (individual instances not tested)

All 15+ `RESERVE_AUTOMATION_*` instances on Base are deployed but none are
tested by address. `ReserveAutomationIntegration.t.sol` tests the contract logic
generically.

### 4626 Factory/Router

| Address Name         | Chain | Risk                                                     |
| -------------------- | ----- | -------------------------------------------------------- |
| `ERC20_FACTORY_4626` | Base  | Low — tested via integration but not by deployed address |
| `ETH_FACTORY_4626`   | Base  | Low                                                      |
| `ETH_ROUTER_4626`    | Base  | Low                                                      |

---

## 4. Modules with Weak Fuzzing/Invariant Coverage

### Current State

- **Fuzz tests:** 1 file — `MultichainGovernanceFuzzing.t.sol` (governance
  voting only)
- **Invariant tests:** 1 file — `xWELLInvariant.t.sol` (xWELL token
  supply/balance invariants)

### Contracts Needing Fuzz/Invariant Tests (by priority)

| Contract                     | Priority     | Rationale                                                                                                                                     |
| ---------------------------- | ------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| **Comptroller**              | **Critical** | Core lending logic — collateral factor, liquidation eligibility, market enter/exit. No fuzz tests for borrow limits or liquidation boundaries |
| **MToken (MErc20)**          | **Critical** | Exchange rate calculation, interest accrual, mint/redeem/borrow/repay flows. No parametric testing of edge cases                              |
| **MultiRewardDistributor**   | **High**     | Reward calculation across multiple tokens. Rounding errors could lead to fund loss. No fuzz tests                                             |
| **TemporalGovernor**         | **High**     | Timelock mechanism, trusted sender management, proposal execution. No fuzz tests                                                              |
| **ChainlinkOEVWrapper**      | **High**     | Price manipulation resistance, fee calculations. No fuzz tests for extreme price scenarios                                                    |
| **FeeSplitter**              | **High**     | Fee distribution math — `testFeeSplitsAlwaysSumToTotal` exists but is limited parametric, not proper invariant                                |
| **JumpRateModel**            | **Medium**   | Interest rate curve — no fuzz tests for extreme utilization ratios                                                                            |
| **ReserveAutomation**        | **Medium**   | Automated reserve management — no fuzz tests                                                                                                  |
| **WormholeBridgeAdapter**    | **Medium**   | Message encoding/decoding — no fuzz tests for malformed messages                                                                              |
| **ChainlinkCompositeOracle** | **Medium**   | Multi-feed composition — no fuzz tests for decimal mismatches                                                                                 |

---

## 5. Security-Critical Gaps

### 5.1 Oracle Contracts — Gaps

**Severity: HIGH**

- **No integration tests for newer OEV wrappers** (BTC, EURC, WELL, USDS, TBTC,
  VIRTUAL, MORPHO, cbXRP, MAMO). The `ChainlinkOEVWrapperIntegration.t.sol` only
  covers ETH/USD wrapper through the liquidation flow. Each new OEV wrapper
  should be validated against its specific Chainlink feed on a fork.
- **Redstone LBTC oracle not tested**. The
  `REDSTONE_LBTC_BTC_CHAINLINK_BOUNDED_ORACLE` uses a different data provider
  (Redstone vs Chainlink). No tests validate this non-Chainlink feed path.
- **No stale price feed testing at scale**.
  `ChainlinkBoundedCompositeOracleIntegration.t.sol` tests staleness for one
  oracle, but there's no systematic staleness test across all deployed feeds.
- **No oracle manipulation fuzzing**. No tests simulate rapid price movements,
  sandwich attacks, or oracle front-running.

### 5.2 Governance Contracts — Gaps

**Severity: MEDIUM-HIGH**

- **No edge-case testing for quorum boundaries**. Tests validate voting works,
  but don't test proposals at exact quorum threshold (off-by-one).
- **No cross-chain message replay protection testing**. While chain ID checks
  exist in the code, no test explicitly attempts cross-chain replay attacks.
- **No failed Wormhole message recovery testing**. If a Wormhole relay fails,
  there's no test for the manual recovery path.
- **MultichainGovernor fuzzing is limited**. Only tests vote aggregation with
  1-255 voters; doesn't fuzz proposal parameters, timing windows, or cross-chain
  vote collection periods.

### 5.3 Token Handling Contracts — Gaps

**Severity: MEDIUM**

- **xWELL has good invariant tests** but delegation voting power consistency
  across chains is not tested.
- **XERC20Lockbox** — tested in deployment integration tests but no dedicated
  unit tests for edge cases (deposit/withdraw with 0 amounts, max uint amounts).
- **MToken reentrancy** — tested via `ReentrancyBaseLiveSystemIntegration.t.sol`
  with `MaliciousBorrower`, but only for WETH market. Other token types
  (ERC-777, rebasing tokens) not tested.

### 5.4 Bridge Adapters — Gaps

**Severity: MEDIUM-HIGH**

- **Axelar bridge has NO integration tests**. Only unit tests in
  `AxelarBridgeAdapter.t.sol`. No fork test against real Axelar Gateway
  contracts.
- **Wormhole integration uses mocked relayer**.
  `CrossChainPublishMessageIntegration.t.sol` and
  `LiveProposalsIntegration.t.sol` use `WormholeRelayerAdapter` mock, not actual
  Wormhole contracts.
- **No malformed message handling tests**. No tests for invalid/corrupted
  Wormhole VAAs or Axelar GMP messages.
- **No bridge cost validation at scale**.
  `BridgeValidationHookIntegration.t.sol` checks 4x-10x cost bounds but doesn't
  stress test with varying gas prices.

### 5.5 Fee Splitter Contracts — Gaps

**Severity: HIGH**

- **Zero deployed fee splitter addresses tested**.
  `FeeSplitterIntegration.t.sol` creates fresh instances and validates the
  logic, but none of the 9 deployed fee splitter contracts
  (`USDC_METAMORPHO_FEE_SPLITTER`, `WETH_METAMORPHO_FEE_SPLITTER`, etc.) are
  tested against their real on-chain configuration.
- **No test verifies fee splitter owner/configuration matches expectations**. A
  misconfigured fee splitter could silently redirect fees.
- **V1 to V2 migration not tested**. Both V1 and V2 fee splitter addresses exist
  — no test validates the migration path.

### 5.6 Morpho Integration — Gaps

**Severity: MEDIUM**

- **No integration test against live Morpho Blue markets on Optimism**.
  `USDC_METAMORPHO_FEE_SPLITTER` exists on Optimism (chain 10) but tests only
  fork Base.
- **Morpho oracle factory addresses not validated**.
  `MORPHO_CHAINLINK_ORACLE_FACTORY` and `MORPHO_FACTORY_V1_1` are registered but
  never tested.
- **No Morpho liquidation failure tests**. What happens when a Morpho Blue
  liquidation fails? No tests cover this path.

### 5.7 Optimism Deployment — Major Gap

**Severity: HIGH**

- **153 contracts deployed on Optimism (chain 10) with minimal dedicated test
  coverage**. No integration test file specifically targets Optimism forks. The
  `SupplyBorrowIntegration.t.sol` uses `PRIMARY_FORK_ID` which defaults to Base.
  Optimism has its own Comptroller, Unitroller, MRD, mTokens, oracles, fee
  splitters, and governance — none fork-tested against Optimism state.

---

## 6. Prioritized Recommendations

### CRITICAL (Write immediately)

| #   | Recommendation                                                                                                                                     | Contracts                       | Effort |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------- | ------ |
| 1   | **Comptroller fuzz tests** — Fuzz collateral factor boundaries, liquidation eligibility, and multi-market borrow limits                            | `Comptroller.sol`               | Medium |
| 2   | **MToken invariant tests** — Invariant: totalSupply \* exchangeRate == totalCash + totalBorrows - totalReserves                                    | `MToken.sol`, `MErc20.sol`      | Medium |
| 3   | **Newer mToken market integration tests** — Fork Base, supply/borrow/liquidate for WELL, USDS, TBTC, LBTC, VIRTUAL, MORPHO, cbXRP, MAMO markets    | All MOONWELL\_\* mTokens        | High   |
| 4   | **Fee splitter live address tests** — Fork Base and verify each deployed fee splitter has correct owner, split ratios, and can execute a fee split | All \*\_METAMORPHO_FEE_SPLITTER | Medium |

### HIGH (Write within 1-2 sprints)

| #   | Recommendation                                                                                                                                                    | Contracts                             | Effort |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- | ------ |
| 5   | **OEV wrapper per-market tests** — Fork Base and validate each OEV wrapper returns correct prices from its underlying Chainlink feed                              | All \*\_OEV_WRAPPER                   | Medium |
| 6   | **Optimism fork integration test** — Create `OptimismLiveSystemIntegration.t.sol` that forks chain 10 and validates Comptroller, mTokens, oracles, and governance | All Optimism contracts                | High   |
| 7   | **Axelar bridge integration test** — Fork Moonbeam and test AxelarBridgeAdapter against real Axelar Gateway                                                       | `AxelarBridgeAdapter.sol`             | Medium |
| 8   | **MultiRewardDistributor fuzz tests** — Fuzz reward accrual with varying speeds, multiple reward tokens, and claim patterns                                       | `MultiRewardDistributor.sol`          | Medium |
| 9   | **Redstone LBTC oracle integration test** — Fork Base and validate the Redstone-based bounded oracle for LBTC market                                              | `ChainlinkBoundedCompositeOracle.sol` | Low    |

### MEDIUM (Write within 1-2 months)

| #   | Recommendation                                                                                                 | Contracts                                           | Effort |
| --- | -------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- | ------ |
| 10  | **TemporalGovernor fuzz tests** — Fuzz proposal timing (queue delay, execution window, pause duration)         | `TemporalGovernor.sol`                              | Medium |
| 11  | **Oracle staleness sweep test** — Fork Base and check all oracle feeds for staleness in a single test          | All CHAINLINK\_\* feeds                             | Low    |
| 12  | **Cross-chain message replay test** — Explicitly attempt replaying a Wormhole VAA on the wrong chain           | `TemporalGovernor.sol`, `WormholeBridgeAdapter.sol` | Medium |
| 13  | **JumpRateModel fuzz tests** — Fuzz utilization 0%-100% and verify rate curve monotonicity                     | `JumpRateModel.sol`                                 | Low    |
| 14  | **Reserve Automation live address tests** — Fork Base, verify each RESERVE*AUTOMATION*\* can execute           | All RESERVE*AUTOMATION*\*                           | Low    |
| 15  | **Morpho oracle factory validation** — Verify MORPHO_CHAINLINK_ORACLE_FACTORY creates correct oracle instances | Morpho oracle contracts                             | Low    |

### LOW (Nice to have)

| #   | Recommendation                                                   | Effort |
| --- | ---------------------------------------------------------------- | ------ |
| 16  | Remove or archive `src/tokensale/` (9 untested deprecated files) | Low    |
| 17  | Add flashloan attack simulation for MToken markets               | Medium |
| 18  | Stress test with 1000+ accounts/markets                          | High   |
| 19  | Chaos engineering for Wormhole relay failures                    | High   |

---

## Appendix A: Contract Categories by Chain

### Base (8453) — 273 contracts

- **Core Lending:** COMPTROLLER, UNITROLLER, 18 mTokens (MOONWELL\_\*)
- **Interest Rate Models:** 50+ JUMP*RATE_IRM*\* (historical + current)
- **Governance:** TEMPORAL*GOVERNOR, VOTE_COLLECTION*\*, EMISSIONS_ADMIN
- **Oracles:** CHAINLINK*ORACLE, 15+ CHAINLINK*\*\_USD feeds, 13+ OEV_WRAPPER, 3
  composite oracles
- **Morpho:** MORPHO_BLUE (external), 2 MetaMorpho vaults, 9 fee splitters, 1
  URD, oracle factory
- **xWELL/Bridge:** xWELL*PROXY, WORMHOLE_BRIDGE_ADAPTER*\*, XERC20_LOCKBOX
- **4626:** ERC20_FACTORY_4626, ETH_FACTORY_4626, ETH_ROUTER_4626
- **Market Infra:** 15+ RESERVE*AUTOMATION*\*, RESERVE_WELL_HOLDING_DEPOSIT,
  MARKET_ADD_CHECKER
- **Views:** MOONWELL_VIEWS_PROXY, MORPHO_VIEWS_V2_PROXY,
  MORPHO_VAULT_V2_VIEWS_PROXY, PROPOSAL_VIEW
- **Cypher:** CYPHER_AUTO_LOAD, CYPHER_ERC4626_RATE_LIMITED_ALLOWANCE
- **Other:** MWETH_OWNER_WRAPPER, OEV_PROTOCOL_FEE_REDEEMER, WETH_ROUTER,
  WETH_UNWRAPPER, RECOVERY

### Moonbeam (1284) — 74 contracts

- **Core Lending:** COMPTROLLER (Artemis), UNITROLLER, 8+ mTokens (mxcDOT,
  mxcUSDC, etc.)
- **Governance:** MULTICHAIN_GOVERNOR_PROXY, ARTEMIS_GOVERNOR, ARTEMIS_TIMELOCK
- **xWELL/Bridge:** xWELL*PROXY, WORMHOLE_BRIDGE_ADAPTER*_,
  AXELAR*BRIDGE_ADAPTER*_, xWELL_ROUTER
- **Staking:** STK_GOVTOKEN_PROXY (StakedWell)
- **Safety Module:** SAFETY_MODULE

### Optimism (10) — 153 contracts

- **Core Lending:** COMPTROLLER, UNITROLLER, mTokens
- **Governance:** TEMPORAL*GOVERNOR, VOTE_COLLECTION*\*
- **Oracles:** CHAINLINK_ORACLE, multiple feeds + OEV wrappers
- **Morpho:** USDC_METAMORPHO_FEE_SPLITTER
- **xWELL/Bridge:** xWELL*PROXY, WORMHOLE_BRIDGE_ADAPTER*\*

---

## Appendix B: Test File Inventory

### Unit Tests (37 files)

```
test/unit/Comptroller.t.sol
test/unit/MErc20.t.sol
test/unit/MErc20Delegate.t.sol
test/unit/Oracle.t.sol
test/unit/WETHRouter.t.sol
test/unit/WethUnwrapper.t.sol
test/unit/MWethOwnerWrapper.t.sol
test/unit/MultiRewardDistributor.t.sol
test/unit/MultiRewardDistributorFailures.t.sol
test/unit/MultiRewards.t.sol
test/unit/StakedWell.t.sol
test/unit/StakedWellMoonbeam.t.sol
test/unit/Recovery.t.sol
test/unit/ReserveAutomation.t.sol
test/unit/RateLimitedAllowance.t.sol
test/unit/CypherAutoLoad.t.sol
test/unit/OEVProtocolFeeRedeemer.t.sol
test/unit/ChainlinkOEVWrapperUnit.t.sol
test/unit/FaucetWithPermit.t.sol
test/unit/Addresses.t.sol
test/unit/Strings.t.sol
test/unit/ProposalView.t.sol
test/unit/BridgeValidationHookUnit.t.sol
test/unit/xWELL.t.sol
test/unit/xWELLPause.t.sol
test/unit/xWELLVote.t.sol
test/unit/WormholeBridgeAdapter.t.sol
test/unit/WormholeUnwrapperAdapter.t.sol
test/unit/AxelarBridgeAdapter.t.sol
test/unit/Governance/MultichainGovernor.t.sol
test/unit/Governance/MultichainGovernorVoting.t.sol
test/unit/Governance/MultichainVoteCollection.t.sol
test/unit/Governance/MultichainMultipleVoteCollections.t.sol
test/unit/Governance/WormholeBridgeBase.t.sol
test/unit/Governance/MarketAddChecker.t.sol
test/unit/TemporalGovernor/TemporalGovernor.t.sol
test/unit/TemporalGovernor/TemporalGovernorExec.t.sol
```

### Integration Tests (41 files)

```
test/integration/SupplyBorrowIntegration.t.sol
test/integration/4626Integration.t.sol
test/integration/4626EthIntegration.t.sol
test/integration/Moonwell4626FactoryLiveSystemIntegration.t.sol
test/integration/Moonwell4626EthLiveSystemIntegration.t.sol
test/integration/FeeSplitterIntegration.t.sol
test/integration/CypherIntegration.t.sol
test/integration/MultiRewardsDistributorIntegration.t.sol
test/integration/ReserveAutomationIntegration.t.sol
test/integration/ReserveAutomationDeployIntegration.t.sol
test/integration/ERC20HoldingDepositLiveIntegration.t.sol
test/integration/MWethOwnerWrapperIntegration.t.sol
test/integration/WETHPostProposalCheckIntegration.t.sol
test/integration/IRModelWethUpgradePostProposalIntegration.t.sol
test/integration/SystemUpgradeIntegration.t.sol
test/integration/HundredFinanceExploitIntegration.t.sol
test/integration/ReentrancyBaseLiveSystemIntegration.t.sol
test/integration/CalldataExecuteIntegration.t.sol
test/integration/LiveSystemBaseSepoliaIntegration.t.sol
test/integration/MoonbeamIntegration.t.sol
test/integration/MultichainProposalIntegration.t.sol
test/integration/TestTemporalGovernorIntegration.t.sol
test/integration/CrossChainPublishMessageIntegration.t.sol
test/integration/BridgeValidationHookIntegration.t.sol
test/integration/LiveProposalsIntegration.t.sol
test/integration/TestProposalCalldataGenerationIntegration.t.sol
test/integration/oracle/ChainlinkOEVWrapperIntegration.t.sol
test/integration/oracle/ChainlinkOEVMorphoWrapperIntegration.t.sol
test/integration/oracle/ChainlinkCompositeOracleIntegration.t.sol
test/integration/oracle/ChainlinkCompositeOracleArbitrumIntegration.t.sol
test/integration/oracle/ChainlinkBoundedCompositeOracleIntegration.t.sol
test/integration/xWELL/DeployxWellBaseIntegration.t.sol
test/integration/xWELL/DeployxWellMoonbeamIntegration.t.sol
test/integration/xWELL/UnwrapperAdapterIntegration.t.sol
test/integration/xWELL/xWellRouterIntegration.t.sol
test/integration/views/MoonwellViewsV1Integration.t.sol
test/integration/views/MoonwellViewsV2Integration.t.sol
test/integration/views/MoonwellViewsV3Integration.t.sol
test/integration/views/MorphoViews.t.sol
test/integration/views/MorphoViewsV2.t.sol
test/integration/views/MorphoVaultV2Views.t.sol
```

### Fuzz/Invariant Tests (2 files)

```
test/fuzzing/MultichainGovernanceFuzzing.t.sol
test/invariant/xWELLInvariant.t.sol
```
