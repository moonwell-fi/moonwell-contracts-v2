# Migration Validation Harness

End-to-end Foundry test harness that drives the full Moonwell governance
migration to Ethereum + Ethereum core deployment against four persistent
Tenderly Virtual Networks (one per chain). Exists on
`feat/migration-vnet-harness`.

## What it validates

For a single setup run, the harness chains together:

1. **Phase A** — `mip-x56` (governor migration). Deploys `MultichainGovernorV2`
   on Ethereum, `TemporalGovernor` + `MultichainVoteCollectionMoonbeam` +
   `VotingPowerAggregator` on Moonbeam, V2 vote-collection impl + VPA on
   Base/Optimism. Transfers Moonbeam ownerships to the new TG. Swaps trusted
   senders on Base/Optimism vote collections. Runs the proposal's `validate()`
   (~50 assertions) at the end.

2. **Phase A.5** — Simulates `PostDeployEthereumXWell.s.sol` (the deployer- run
   script that flips Eth `xWELL`, `WormholeBridgeAdapter`, and `ProxyAdmin`
   ownership to the new governor; first two use `Ownable2Step`, third is
   1-step).

3. **Phase B** — Installs the `WormholeRelayerAdapter` mock and overrides the
   `wormhole()` slot on every governor / vote collection so cross- chain
   proposal actions (Eth → Moonbeam/Base/OP) execute in-memory against the
   in-fork TemporalGovernors.

4. **Phase C** — `mip-e00.initProposal → deploy → afterDeploy`. Deploys
   `Comptroller`, `Unitroller`, `MultiRewardDistributor`, `ChainlinkOracle`,
   four `MTokens` (WETH/USDC/USDT/cbBTC), four `JumpRateModel` IRMs, and
   `WETHRouter` on Ethereum. Sets the new governor as pendingAdmin on every
   market and the Unitroller, and as admin on the oracle.

5. **Phase C.2** — `vm.prank(governorV2)` to call `_acceptAdmin()` on every Eth
   mToken + the Unitroller, and `acceptOwnership()` on the Eth
   `WormholeBridgeAdapter`.

6. **Phase D** — Stubs the migration-summary follow-up items that no on-chain
   proposal performs today:

   - Moonbeam `WormholeBridgeAdapter`, `MultichainVoteCollectionMoonbeam`,
     `VotingPowerAggregator` acceptOwnership (via TG prank)
   - Base + Optimism `VotingPowerAggregator` acceptOwnership (via TG prank)
   - Eth `xWELL` and `VotingPowerAggregator` acceptOwnership (via governor
     prank) — these are TODOs #1 and #2 in
     `docs/governance/MULTICHAIN_GOVERNOR_MIGRATION_SUMMARY.md`
   - Moonbeam mTokens + Unitroller `_acceptAdmin` (via TG prank) — TODO #4

7. **Phase 0** — Stubs xWELL bridging activation by calling `addTrustedSenders`
   on every chain's `WormholeBridgeAdapter` for the other three chains' adapters
   (TODO #3). Idempotent — skips any chain pair already configured.

8. **Phase E (smoke test)** — Builds and runs a real `HybridProposalV2` subclass
   (`EthMarketUpdateSmoke.sol`) that bumps `MOONWELL_WETH` reserve factor to 15%
   on the new governor. Exercises the full
   `propose → vote (mocked voting power) → cross-chain vote collection period → execute`
   path on `MultichainGovernorV2`, with the action landing directly on the
   Ethereum Unitroller (no Wormhole hop).

The test methods are named `testPhaseA/C/D/E_…` and each asserts the post-phase
invariants. The Phase E test is the loop-closer: it proves the new Ethereum
governor can mutate Eth-native market state.

## Files

| Path                                                  | Purpose                                  |
| ----------------------------------------------------- | ---------------------------------------- |
| `test/integration/MigrationHarness.t.sol`             | The harness contract (4 tests)           |
| `test/integration/proposals/EthMarketUpdateSmoke.sol` | Phase E smoke proposal                   |
| `proposals/mips/mip-x56/mip-x56.sol`                  | Includes test-mode nonce fix (see below) |
| `Makefile`                                            | `migration-harness` / `…-keep` targets   |

Outside the contracts repo:

| Path                                                                       | Purpose                          |
| -------------------------------------------------------------------------- | -------------------------------- |
| `../defender-migration/moonwell-tenderly/scripts/setup-migration-vnets.ts` | 4-chain VNet bootstrap           |
| `../defender-migration/moonwell-tenderly/.env.migration-vnets` (generated) | RPC URLs + VNET_IDS for teardown |

## Running it

```bash
# From moonwell-tenderly:
cp .env.example .env  # populate TENDERLY_ACCESS_KEY

# From moonwell-contracts-v2:
make migration-harness       # bootstrap → run → teardown
make migration-harness-keep  # bootstrap → run, keep VNets for inspection
```

Each VNet uses its native chain ID (1284, 8453, 10, 1 ) so the proposal
harness's `block.chainid` guards pass. The four RPC URLs are written to
`.env.migration-vnets` under the names `MOONBEAM_RPC_URL`, `BASE_RPC_URL`,
`OP_RPC_URL`, `ETH_RPC_URL` — exactly what `foundry.toml`'s `[rpc_endpoints]`
block already references, so Foundry resolves them with zero plumbing.

Each test in the suite re-runs `setUp()`, so a full pass invokes mip-x56

- mip-e00 four times. Expect ~2.5 min wall-clock for the full bootstrap → 4
  tests → teardown round trip when nothing else is hammering Tenderly.

## Deliberate scope reductions

Two parts of the production migration path are skipped in the harness, with the
gaps stubbed:

1. **`mip-e00.build/simulate/validate` is skipped.**
   `mip-e00.beforeSimulationHook` pre-funds the governor with each underlying
   token via `forge-std`'s `deal()`. `deal()` uses `stdStorage` to probe the
   balance slot. USDT's `delegateContract` pattern at slot 10 makes `balanceOf`
   revert during the probe write, and `stdStorage` gives up. Rather than etch
   USDT or modify e00, the harness skips the proposal-execute step and stubs the
   admin/ownership accepts (Phase C.2 + Phase D) that the proposal would
   otherwise have done. The smoke test in Phase E only mutates `reserveFactor` —
   no initial-mint state is needed for it to pass.

2. **Phase 0 + Phase D's TODO accepts are pranks, not real proposals.** The four
   follow-ups in `docs/governance/MULTICHAIN_GOVERNOR_MIGRATION_SUMMARY.md`
   (xWELL bridging activation; Eth xWELL/VPA `acceptOwnership`; Moonbeam mTokens
   `_acceptAdmin`) are simulated by direct owner pranks in the harness. On-chain
   these will eventually be either contract changes (for the Ownable2Step
   pattern) or a small follow-up proposal from the new Eth governor. The harness
   uses pranks because:
   - Pre-migration setup (Phase 0) can't run via the new governor (doesn't exist
     yet) and would require a separate proposal on the old Moonbeam governor on
     mainnet.
   - Post-migration Eth-side acceptOwnerships require
     `msg.sender == governorV2`, which only a proposal on `MultichainGovernorV2`
     can satisfy.

## The mip-x56 patch on this branch

`proposals/mips/mip-x56/mip-x56.sol` carries a small change that is
**test-mode-only** but necessary for any harness that runs the full proposal
across forks:

- Captures the deployer's nonce at the moment `_predictedGovernorProxy` is
  computed (`_predictedDeployerNonce`).
- Etches a single placeholder byte at the predicted CREATE address so
  `Addresses.addAddress("…", _, isContract=true)` doesn't reject it.
- Clears the placeholder + resets the deployer's nonce (via `vm.setNonceUnsafe`)
  immediately before the real proxy is deployed at the end of `deploy()`.

Foundry shares the broadcast deployer's nonce **across** forks: every
satellite-chain deployment between the predict and the deploy bumps the same
counter, so by the time the proxy is created on Ethereum the nonce would land
far past the predicted value and the address would not match. The patch resets
the counter immediately before the real deploy. The fix is a no-op under a real
on-chain broadcast (Ethereum nonce naturally matches because nothing else runs
between predict and deploy).

This patch is also being committed on `feat/multichain-gov-refactor` so it lands
via the governor PR. Once that merges and the harness branch rebases on top, the
duplicate change here can be dropped.

## What "passing" means

A clean run looks like:

```
[PASS] testPhaseA_mipx56_postMigrationState()
[PASS] testPhaseC_mipe00_ethCoreLive()
[PASS] testPhaseD_postMigrationStubsApplied()
[PASS] testPhaseE_smokeProposalChangesEthMarket()
Suite result: ok. 4 passed; 0 failed; 0 skipped
```

Phase E is the one that proves end-to-end correctness. The other three are
sentinel checks that fail loudly if mip-x56 or mip-e00 ever stops producing the
post-state the migration summary describes (e.g. if mip-e00 gets refactored and
stops calling acceptOwnership on the Eth bridge adapter, `testPhaseC` fails
immediately).
