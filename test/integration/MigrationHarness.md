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

2. **Phase A.5** — Simulates `PostDeployEthereumXWell.s.sol` (the deployer-run
   script that flips Eth `xWELL`, `WormholeBridgeAdapter`, and `ProxyAdmin`
   ownership to the new governor; first two use `Ownable2Step`, third is
   1-step).

3. **Phase B** — Installs the `WormholeRelayerAdapter` mock and overrides the
   `wormhole()` slot on every governor / vote collection so cross- chain
   proposal actions (Eth → Moonbeam/Base/OP) execute in-memory against the
   in-fork TemporalGovernors.

4. **Phase C** —
   `mip-e00.initProposal → deploy → afterDeploy → build → simulate → validate`.
   Deploys `Comptroller`, `Unitroller`, `MultiRewardDistributor`,
   `ChainlinkOracle`, four `MTokens` (WETH/USDC/USDT/cbBTC), four
   `JumpRateModel` IRMs, and `WETHRouter` on Ethereum. Sets the new governor as
   pendingAdmin on every market and the Unitroller, and as admin on the oracle.
   **`simulate` then runs the full propose → vote → execute path on the new
   governor**, which queues `_acceptAdmin()` on every Eth mToken + Unitroller +
   acceptOwnership() on the Eth WormholeBridgeAdapter, plus cross-chain
   acceptOwnership for Moonbeam WormholeBridgeAdapter, Moonbeam VC, Moonbeam
   VPA, Base VPA, and Optimism VPA via Wormhole → TG. `validate` asserts the
   post-state.

   - **Phase C.1** — Before `simulate`, the harness pre-funds the governor with
     each underlying token. For USDT, forge-std's `deal()` trips USDT's
     `delegateContract` probe in stdStorage, so the harness writes the balance
     directly to `TetherToken.balances[governor]` at base slot 2 and bumps
     `_totalSupply` at slot 5. WETH/USDC/cbBTC use `deal()` as normal.

5. **Phase D** — Runs **`mip-e01` (First Ethereum Proposal)** through governance
   via `HybridProposalV2.simulate`. The new `MultichainGovernorV2` proposes,
   votes, and executes — no pranks:

   - Eth: `xWELL.acceptOwnership()` (TODO #1)
   - Eth: `VotingPowerAggregator.acceptOwnership()` (TODO #2)
   - Moonbeam (Wormhole → TG): `Unitroller._acceptAdmin()` + per-mToken
     `_acceptAdmin()` for every market whose `pendingAdmin == TG` (TODO #4)

   `mip-e01.build()` enumerates Moonbeam mTokens via
   `Comptroller.getAllMarkets()` at build time and only pushes `_acceptAdmin`
   for markets that x56 actually set `pendingAdmin = TG` on — automatically
   filters out markets with admins other than the old `MultichainGovernor`.

6. **Phase 0** — Stubs xWELL bridging activation by calling `addTrustedSenders`
   on every chain's `WormholeBridgeAdapter` for the other three chains' adapters
   (TODO #3). Idempotent — skips any chain pair already configured.

7. **Phase E (Eth-native smoke test)** — Builds and runs
   `EthMarketUpdateSmoke.sol`, a real `HybridProposalV2` subclass that bumps
   `MOONWELL_WETH` reserve factor to 15% on the new governor. Exercises the full
   `propose → vote → execute` path on `MultichainGovernorV2`, with the action
   landing directly on the Ethereum Unitroller (no Wormhole hop).

8. **Phase F (cross-chain smoke test)** — Builds and runs
   `BaseMarketUpdateSmoke.sol`, a real `HybridProposalV2` subclass with one
   `ActionType.Base` action that bumps `MOONWELL_USDC` reserve factor to 12% on
   Base. Exercises the full cross-chain path: `governorV2.execute` on Eth →
   `publishMessage` → fake VAA → `BaseTemporalGovernor.queueProposal` → vm.warp
   past TG's `proposalDelay` (24h) → `BaseTemporalGovernor.executeProposal` →
   reserve factor change lands on the live Base USDC market.

9. **Phase G (break-glass execution path)** — Three tests:
   - `testPhaseG_breakGlassUnwindsEthOwnership`: invokes
     `governorV2.executeBreakGlass` with the `transferOwnership(PAUSE_GUARDIAN)`
     calldata (whitelist entry #7, seeded by mip-x56). Verifies the Eth
     `WormholeBridgeAdapter.pendingOwner` flips to PAUSE_GUARDIAN, and that
     `breakGlassGuardian` becomes `address(0)` (one-shot property).
   - `testPhaseG_breakGlassRejectsNonWhitelistedCalldata`: shows that
     `executeBreakGlass` reverts on a calldata targeting an attacker address
     (only `transferOwnership(PAUSE_GUARDIAN)` is whitelisted, not
     `transferOwnership(<arbitrary>)`).
   - `testPhaseG_breakGlassRejectsNonGuardianCaller`: confirms the
     `onlyBreakGlassGuardian` modifier rejects calls from non-guardians.

The test methods are named `testPhaseA/C/D/E/F/G_…` and each asserts the
post-phase invariants. Phase E + Phase F are the loop-closers: Eth-native state
mutation and cross-chain state mutation via the new governor. Phase G proves the
migration is reversible via the seeded break-glass calldatas.

## Files

| Path                                                   | Purpose                                  |
| ------------------------------------------------------ | ---------------------------------------- |
| `test/integration/MigrationHarness.t.sol`              | The harness contract (5 tests)           |
| `proposals/mips/mip-e01/mip-e01.sol`                   | First Ethereum Proposal (Phase D)        |
| `proposals/mips/mip-e01/MIP-E01.md`                    | mip-e01 description                      |
| `test/integration/proposals/EthMarketUpdateSmoke.sol`  | Phase E smoke proposal (Eth-native)      |
| `test/integration/proposals/BaseMarketUpdateSmoke.sol` | Phase F smoke proposal (cross-chain)     |
| `proposals/mips/mip-x56/mip-x56.sol`                   | Includes test-mode nonce fix (see below) |
| `proposals/proposalTypes/HybridProposalV2.sol`         | Includes \_runExtChain Moonbeam fix      |
| `Makefile`                                             | `migration-harness` / `…-keep` targets   |

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

Each VNet uses its native chain ID (1284, 8453, 10, 1) so the proposal harness's
`block.chainid` guards pass. The four RPC URLs are written to
`.env.migration-vnets` under the names `MOONBEAM_RPC_URL`, `BASE_RPC_URL`,
`OP_RPC_URL`, `ETH_RPC_URL` — exactly what `foundry.toml`'s `[rpc_endpoints]`
block already references, so Foundry resolves them with zero plumbing.

Each test in the suite re-runs `setUp()`, so a full pass invokes mip-x56

- mip-e00 five times. Expect ~3 min wall-clock for the full bootstrap → 5 tests
  → teardown round trip when nothing else is hammering Tenderly.

## Deliberate scope reductions

The harness now runs every TODO from
`docs/governance/MULTICHAIN_GOVERNOR_MIGRATION_SUMMARY.md` through real
governance **except** xWELL bridging activation:

- **xWELL bridging activation (TODO #3)** — Pre-migration setup that would run
  on the _old_ Moonbeam governor before mip-x56 executes, so xWELL voting power
  can reach Ethereum before the new governor goes live. Tested in a separate
  in-flight Moonbeam-governor proposal — the harness simulates the
  post-migration end-state via Phase 0's direct prank of the bridge adapter
  owners.

## Patches required for the harness to run

Two minimal patches live on this branch and will need to be cherry-picked into
upstream PRs before the harness can run from `deploy/mainnet`:

1. **`proposals/mips/mip-x56/mip-x56.sol`** — Test-mode nonce fix. Captures the
   deployer nonce when the proxy CREATE address is predicted, etches a one-byte
   placeholder so `Addresses.addAddress`'s isContract check passes, then resets
   the nonce + clears the placeholder immediately before the real proxy deploy.
   No-op under a real broadcast (Ethereum nonce naturally matches because no
   other Eth txs happen between predict and deploy). Also committed on
   `feat/multichain-gov-refactor` (commit `b1fa5479`).

2. **`proposals/proposalTypes/HybridProposalV2.sol`** — `_runExtChain`
   dispatches between `checkMoonbeamActions` and `checkBaseOptimismActions`
   based on `block.chainid`. The original called `checkBaseOptimismActions`
   unconditionally, which reverts on the Moonbeam fork. Commit `f5269589` on
   `deploy/mainnet` added Moonbeam acceptOwnership actions to e00.build without
   testing them through simulate, so this path was broken until we wired it.

## What "passing" means

A clean run looks like:

```
[PASS] testPhaseA_mipx56_postMigrationState()
[PASS] testPhaseC_mipe00_ethCoreLive()
[PASS] testPhaseD_postMigrationStubsApplied()
[PASS] testPhaseE_smokeProposalChangesEthMarket()
[PASS] testPhaseF_smokeProposalChangesBaseMarket()
[PASS] testPhaseG_breakGlassUnwindsEthOwnership()
[PASS] testPhaseG_breakGlassRejectsNonWhitelistedCalldata()
[PASS] testPhaseG_breakGlassRejectsNonGuardianCaller()
Suite result: ok. 8 passed; 0 failed; 0 skipped
```

Phase E + F are the loop-closers that prove end-to-end correctness. The other
three are sentinel checks that fail loudly if mip-x56 or mip-e00 ever stop
producing the post-state the migration summary describes (e.g. if mip-e00 gets
refactored and stops calling acceptOwnership on the Eth bridge adapter,
`testPhaseC` fails immediately).

## Confidence by area

| What's being validated                                  | Confidence | Evidence                                                               |
| ------------------------------------------------------- | ---------- | ---------------------------------------------------------------------- |
| mip-x56 deploys produce the right contracts             | HIGH       | Real deploy + ~50 validate assertions                                  |
| mip-x56 Moonbeam ownership transfers                    | HIGH       | Real governance proposal execution + validate                          |
| mip-x56 Wormhole hops to Base/OP TGs                    | HIGH       | Mock auto-delivers; VC upgrade + initializeV3 asserted                 |
| mip-x56 break-glass calldata storage                    | HIGH       | validate() asserts each whitelisted calldata exists                    |
| mip-x56 break-glass execution path                      | **HIGH**   | **Phase G executes break-glass + tests whitelist/auth enforcement**    |
| mip-e00 Eth deploys produce the right contracts         | HIGH       | Real deploy + afterDeploy                                              |
| mip-e00 Eth admin/ownership transfers                   | **HIGH**   | **e00.simulate runs end-to-end through governance**                    |
| mip-e00 cross-chain accepts (TGs accept ownership)      | **HIGH**   | **e00.simulate's Wormhole hops execute against TGs**                   |
| mip-e00 initial-mint of every market                    | HIGH       | USDT-safe deal + e00.simulate mint actions execute                     |
| New governor can propose                                | HIGH       | Phase E + F do this                                                    |
| New governor can vote (xWELL delegation + getPastVotes) | HIGH       | Phase E + F do this                                                    |
| New governor can execute Eth-native actions             | HIGH       | Phase E asserts state change on freshly-deployed market                |
| **New governor can execute cross-chain actions**        | **HIGH**   | **Phase F mutates Base USDC reserve factor end-to-end**                |
| xWELL bridging activation                               | MEDIUM     | Phase 0 stub configures trusted senders; no bridge tx                  |
| Follow-Up "First Ethereum Proposal" path                | **HIGH**   | **mip-e01 executes through governance; all 4 TODOs cleared except #3** |
