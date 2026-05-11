# Moonwell Governance Migration: MIP-X45 + MIP-X56 Audit Brief

## Overview

This migration moves Moonwell governance from Moonbeam to Ethereum mainnet. The
system spans four chains: **Ethereum** (new home), **Moonbeam** (current home),
**Base**, and **Optimism**. The migration is executed across two governance
proposals and two deployer-run scripts.

For details on the smart contract changes for MultichainGovernorV2, read
[this doc](./MULTICHAIN_GOVERNOR_V2.md).

---

## Execution Order

| Step | Script                               | Executor   | Chain(s)                           |
| ---- | ------------------------------------ | ---------- | ---------------------------------- |
| 0    | `DeployXWellEthereum.s.sol`          | Deployer   | Ethereum                           |
| 1    | `mip-x45.sol` — deploy + submit      | Deployer   | Moonbeam, Base, OP, Ethereum       |
| 2    | `mip-x45.sol` — proposal executes    | Governance | Moonbeam → Base, OP (via Wormhole) |
| 3    | `mip-x56.sol` — deploy + afterDeploy | Deployer   | All 4 chains                       |
| 4    | `mip-x56.sol` — proposal executes    | Governance | Moonbeam → Base, OP (via Wormhole) |
| 5    | `PostDeployEthereumXWell.s.sol`      | Deployer   | Ethereum                           |

Step 0 is already complete (xWELL, stkWELL, WormholeBridgeAdapter, ProxyAdmin,
EcosystemReserve are live on Ethereum).

---

## MIP-X45: Prerequisite Upgrades

### Purpose

Prepare the existing system for migration by upgrading stkWELL across chains and
validating the Ethereum xWELL deployment.

### Actions

**Moonbeam (executed by MultichainGovernor):**

- `upgradeAndCall` stkWELL proxy to V2 with `initializeV2()` via
  `MOONBEAM_PROXY_ADMIN` — switches snapshot logic from block numbers to
  timestamps
- Call `setNewStakedWell(stkWELL, toUseTimestamps=true)` on MultichainGovernor
  to enable timestamp-based voting

**Base (via Wormhole from MultichainGovernor):**

- Upgrade stkWELL to V2 — removes faulty `configureAssets` function

**Optimism (via Wormhole from MultichainGovernor):**

- Upgrade stkWELL to V2 — same as Base

### Deployment Phase

- Deploys new stkWELL implementation contracts on Moonbeam, Base, and Optimism
- Validates that Ethereum xWELL, stkWELL, and ProxyAdmin are already deployed
  (from Step 0)

### Key Parameters

These have been confirmed to have no issues or conflicts with Ethereum Mainnet
finality.

| Parameter                       | Value                      |
| ------------------------------- | -------------------------- |
| Ethereum xWELL buffer cap       | 100M xWELL                 |
| Ethereum xWELL rate limit       | 1,158 xWELL/sec (~19M/day) |
| Ethereum xWELL pause duration   | 10 days                    |
| Ethereum stkWELL cooldown       | 7 days                     |
| Ethereum stkWELL unstake window | 2 days                     |

---

## MIP-X56: Governance Migration

### Purpose

Deploy the new governance infrastructure on Ethereum and migrate all contract
ownership from the Moonbeam MultichainGovernor to the new system.

### Deployment Phase (deployer-run)

**Ethereum:**

- Reuse the existing ProxyAdmin (already deployed in Step 0)
- Deploy MultichainGovernorV2 implementation
- Deploy VotingPowerAggregator (impl + proxy via ProxyAdmin) — initialized
  atomically with deployer as owner
- Deploy MultichainGovernorV2 proxy with `initialize(...)` encoded in the proxy
  constructor's `_data`, so creation and initialization happen in the same
  transaction (no uninitialized window).
- Set EMISSIONS_ADMIN = MultichainGovernorV2 proxy

**Moonbeam:**

- Deploy MultichainGovernor v1.1 implementation (adds `recoverETH()`)
- Deploy TemporalGovernor (non-upgradeable) — trusted sender: Ethereum
  MultichainGovernorV2
- Deploy VotingPowerAggregator (impl + proxy via MOONBEAM_PROXY_ADMIN)
- Deploy MultichainVoteCollectionMoonbeam (impl + proxy via
  MOONBEAM_PROXY_ADMIN) — trusted sender: Ethereum MultichainGovernorV2

**Base:**

- Deploy VotingPowerAggregator (impl + proxy via MRD_PROXY_ADMIN)
- Deploy MultichainVoteCollectionV2 implementation (upgrade target for existing
  proxy)

**Optimism:**

- Same as Base

The MultichainGovernorV2 init payload includes:
`startingProposalCount = moonbeam.proposalCount + 1`, the trusted senders
(Moonbeam VoteCollectionV2, Base VoteCollection, OP VoteCollection), and the 8
break-glass whitelisted calldatas (3 publishMessage + 5 admin functions). All of
these are read or built during `deploy()` from already-deployed contracts on the
relevant chains.

### afterDeploy Phase (deployer-run)

**Ethereum:**

- Configure VotingPowerAggregator: `addSnapshotSource(stkWELL)`, transfer
  ownership to governor (Ownable2Step — only sets `pendingOwner`; see Follow-Up
  Items)
- Transfer Ethereum ProxyAdmin ownership to MultichainGovernorV2

The MultichainGovernorV2 itself is already fully initialized at the end of
`deploy()`; no separate `initialize()` call is needed in afterDeploy.

### Build-time precondition

`mip-x56.build()` reverts if any proposal is `Active` or in
`CrossChainVoteCollection` on the Moonbeam governor. `initializeV3()` on Base/OP
removes the legacy Moonbeam governor as a trusted sender, which would strand
in-flight satellite votes — so the deployer must wait for live proposals to
drain (or cancel them) before submitting this migration.

### Proposal Actions (executed by old Moonbeam MultichainGovernor)

**Moonbeam (executed by MultichainGovernor):**

1. Upgrade MultichainGovernor to v1.1 (adds `recoverETH()` function)
2. Call `recoverETH(WELL_FOUNDATION_MULTISIG)` to recover stuck ETH
3. Add stkWELL as snapshot source on Moonbeam VotingPowerAggregator
4. Transfer VotingPowerAggregator ownership to Moonbeam TemporalGovernor
   (Ownable2Step — only sets `pendingOwner`; TemporalGovernor must
   `acceptOwnership()` in the first Ethereum follow-up proposal)
5. Transfer ownership of ~20+ contracts from MultichainGovernor to
   TemporalGovernor:
   - Ownable contracts → `transferOwnership(temporalGovernor)`
   - mTokens/Unitroller → `_setPendingAdmin(temporalGovernor)`
   - ChainlinkOracle → `setAdmin(temporalGovernor)`
   - stkWELL → `setEmissionsManager(temporalGovernor)`

**Base (via Wormhole from Moonbeam):**

1. Upgrade MultichainVoteCollection proxy to V3 implementation
2. Call `initializeV3(votingPowerAggregator, ethChainId, ethGovernorV2)` — sets
   VotingPowerAggregator, removes old Moonbeam governor as trusted sender, adds
   Ethereum governor
3. Add stkWELL as snapshot source on Base VotingPowerAggregator
4. Add Ethereum MultichainGovernorV2 as trusted sender on Base TemporalGovernor
5. Remove Moonbeam MultichainGovernor as trusted sender from Base
   TemporalGovernor

**Optimism (via Wormhole from Moonbeam):**

- Same 5 actions as Base

### Governance Parameters (MultichainGovernorV2)

| Parameter                          | Value                   |
| ---------------------------------- | ----------------------- |
| Proposal threshold                 | 1,000,000 WELL          |
| Voting period                      | 3 days (259,200 sec)    |
| Cross-chain vote collection period | 1 day (86,400 sec)      |
| Quorum                             | 100,000,000 WELL        |
| Pause duration                     | 30 days (2,592,000 sec) |

---

## PostDeployEthereumXWell: Superseded

An upcoming **interim Moonbeam proposal** (mip-m## — identifier to be assigned)
takes over the xWELL-on-Ethereum bootstrap. That proposal:

1. Enables xWELL on Ethereum (sets the rate limits and pause guardian on the
   Ethereum xWELL).
2. Sets emissions manager on Ethereum stkWELL.
3. Transfers ownership of Ethereum `xWELL` and `WormholeBridgeAdapter` to the
   **PAUSE_GUARDIAN multisig** (`0x5B710010586C1b728B047c3E42473c700eeA4026`,
   already registered in `chains/1.json`).

(Ethereum `ProxyAdmin` ownership is already transferred to MultichainGovernorV2
inside `mip-x56.afterDeploy` — it does not flow through the interim proposal.)

`script/PostDeployEthereumXWell.s.sol` is therefore no longer part of the
mip-x56 deployer flow. Once the interim proposal lands, post-execution
validation is:

- xWELL owner / pendingOwner == PAUSE_GUARDIAN multisig
- WormholeBridgeAdapter owner / pendingOwner == PAUSE_GUARDIAN multisig
- ProxyAdmin owner == MultichainGovernorV2 (unchanged from mip-x56)

The first MultichainGovernorV2 proposal on Ethereum then claims xWELL and
WormholeBridgeAdapter ownership from PAUSE_GUARDIAN (see Follow-Up Items below).

---

## Architecture After Migration

```
                    ┌─────────────────────────────────┐
                    │         ETHEREUM (new home)       │
                    │                                   │
                    │  MultichainGovernorV2 (proposals)  │
                    │  VotingPowerAggregator             │
                    │  xWELL + stkWELL + ProxyAdmin      │
                    │  WormholeBridgeAdapter             │
                    └──────────┬───────┬────────────────┘
                   Wormhole    │       │    Wormhole
              ┌────────────────┘       └────────────────┐
              ▼                                         ▼
┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
│      MOONBEAM        │  │        BASE           │  │      OPTIMISM        │
│                      │  │                       │  │                      │
│  TemporalGovernor    │  │  TemporalGovernor     │  │  TemporalGovernor    │
│  VotingPowerAgg.     │  │  VotingPowerAgg.      │  │  VotingPowerAgg.     │
│  VoteCollectionV2    │  │  VoteCollectionV2     │  │  VoteCollectionV2    │
│  (Moonbeam variant)  │  │                       │  │                      │
│  All existing DeFi   │  │  xWELL + stkWELL      │  │  xWELL + stkWELL    │
│  contracts           │  │  DeFi contracts       │  │  DeFi contracts      │
└──────────────────────┘  └───────────────────────┘  └──────────────────────┘
```

**Voting flow:** Users vote on Ethereum governor. Satellite chains collect votes
locally via VoteCollectionV2 and relay them to Ethereum via Wormhole.
VotingPowerAggregator on each chain resolves xWELL + stkWELL voting power using
timestamp-based snapshots.

**Execution flow:** Proposals pass on Ethereum → MultichainGovernorV2 sends
Wormhole messages → TemporalGovernors on each satellite chain execute the
instructions.

---

## Follow-Up Items

Two follow-up steps complete the migration after MIP-X45/X56:

### A. Interim Moonbeam proposal (xWELL Ethereum enablement)

Enables xWELL on Ethereum and lands the cross-chain trust wiring that MIP-X56
cannot deliver:

- Configure xWELL rate limits and pause guardian on Ethereum xWELL.
- Set emissions manager on Ethereum stkWELL.
- Transfer ownership of Ethereum `xWELL` and `WormholeBridgeAdapter` to the
  **PAUSE_GUARDIAN multisig** (see "PostDeployEthereumXWell: Superseded" above).
  (Ethereum `ProxyAdmin` ownership is handled by `mip-x56.afterDeploy` directly
  to MultichainGovernorV2 and does not flow through the interim proposal.)
- `addTrustedSenders` on all four chains so cross-chain xWELL bridging works
  from/to Ethereum:
  - **Ethereum** WormholeBridgeAdapter — add Moonbeam, Base, and Optimism
    adapters as trusted senders.
  - **Moonbeam** / **Base** / **Optimism** WormholeBridgeAdapters — add the
    Ethereum adapter as trusted sender (via Wormhole → TemporalGovernor).

`addTrustedSenders` lives in this interim proposal (not the first
MultichainGovernorV2 proposal) because the Moonbeam governor still has the
Wormhole-execution path into Base/Optimism TemporalGovernors until MIP-X56
removes it, so the trust wiring is cheaper and more reliable to land here.

### B. First MultichainGovernorV2 proposal on Ethereum (MIP-E00)

The first V2 proposal — currently `proposals/mips/mip-e00/mip-e00.sol` (PR
[#560](https://github.com/moonwell-fi/moonwell-contracts-v2/pull/560)) — calls
`acceptOwnership()` / `_acceptAdmin()` on each contract whose `pendingOwner` or
`pendingAdmin` is set by MIP-X56's deploy and proposal actions:

**Step 1 — Ethereum-direct actions (MultichainGovernorV2 calls):**

- `acceptOwnership()` on **WormholeBridgeAdapter** (Ethereum) — pendingOwner set
  by mip-x56 deployer-side ownership transfer (mip-e00.sol:389).

**Step 2 — Wormhole-relayed actions (Moonbeam/Base/Optimism TemporalGovernor
calls on behalf of the Ethereum governor):**

- `acceptOwnership()` on **WormholeBridgeAdapter** (Moonbeam) — mip-e00.sol:399.
- `acceptOwnership()` on **MultichainVoteCollectionMoonbeam**
  (`VOTE_COLLECTION_V2_PROXY` on Moonbeam) — mip-e00.sol:407.
- `acceptOwnership()` on **VotingPowerAggregator** (Moonbeam) — pendingOwner set
  by MIP-X56 Moonbeam action (mip-x56.sol:885-893) — mip-e00.sol:415.
- `acceptOwnership()` on **VotingPowerAggregator** (Base) — mip-e00.sol:423.
- `acceptOwnership()` on **VotingPowerAggregator** (Optimism) — mip-e00.sol:431.
- `_acceptAdmin()` on Moonbeam **Unitroller** and the mTokens loop — set as
  `pendingAdmin` by MIP-X56 (mip-x56.sol:1038-1052) — mip-e00.sol:374, 455. _Why
  this cannot be in MIP-X56:_ `_acceptAdmin()` requires
  `msg.sender == pendingAdmin` (TemporalGovernor), and TemporalGovernor can only
  execute via Wormhole from the Ethereum governor, which has no proposals yet
  during MIP-X56 execution.

Base and Optimism VotingPowerAggregators have `_transferOwnership` to
TemporalGovernor in the initializer (single-step), so only Moonbeam needed the
two-step pendingOwner path on the aggregator. Base/OP still receive an
`acceptOwnership()` call here because the aggregator was redeployed and its
initial owner was the deployer multisig before the TG accept.

**Gaps not yet covered by MIP-E00 (as of PR head):**

- **xWELL on Ethereum.** Neither MIP-X56 nor MIP-E00 currently calls
  `acceptOwnership()` on Ethereum xWELL. xWELL on Ethereum is enabled and
  re-owned by the upcoming interim Moonbeam proposal (see § A above), which
  parks ownership at the **PAUSE_GUARDIAN multisig**. A subsequent transfer to
  MultichainGovernorV2 (via PAUSE_GUARDIAN signing
  `transferOwnership(governorV2)` → governor `acceptOwnership()` in a follow-up
  V2 proposal) is **TBD** — flag this when reviewing.
- **Ethereum VotingPowerAggregator.** `mip-x56._configureEthereumVotingPower`
  (mip-x56.sol:681) sets `pendingOwner = governorV2`, but MIP-E00 does not call
  `acceptOwnership()` on it. Either MIP-E00 should add this action, or it should
  be addressed in a separate V2 proposal — flag this when reviewing.

---

## Key Design Decisions

1. **Timestamp-based voting:** All VotingPowerAggregators use timestamps (not
   block numbers) for snapshot consistency across chains.

2. **Proposal ID continuity:** MultichainGovernorV2 starts with
   `startingProposalCount = moonbeam.proposalCount + 1`, ensuring proposal IDs
   never overlap.

3. **Break glass guardian:** Three whitelisted `publishMessage` calldatas unwind
   mip-x56's cross-chain trust topology in an emergency. Each targets one
   TemporalGovernor (Moonbeam, Base, Optimism) and (a) removes the new Ethereum
   MultichainGovernorV2 as a trusted sender and (b) restores the old Moonbeam
   `MULTICHAIN_GOVERNOR_PROXY` (v1.1) as a trusted sender. After execution, the
   old Moonbeam governor regains a Wormhole **execution** path into each
   TemporalGovernor and can iteratively reverse the ~75 Moonbeam ownership
   transfers (and any Base/OP follow-up) through normal governance. The
   break-glass guardian role is single-use and revoked atomically with
   execution. **Known caveats — not addressed by break-glass:** (i)
   Base/Optimism `MultichainVoteCollectionV2.targetAddress` is hardcoded to the
   Ethereum V2 governor by `initializeV3` (gated by `reinitializer(3)`, no
   external mutator), so cross-chain vote collection remains broken until a
   post-incident upgrade deploys a `MultichainVoteCollectionV3` exposing
   target-address mutators — the old governor operates on Moonbeam-local voting
   power in the interim. (ii) Ethereum-side contracts owned by V2 (xWELL,
   stkWELL, WormholeBridgeAdapter, VotingPowerAggregator, ProxyAdmin) are not
   unwound — PAUSE_GUARDIAN multisig coordinates Ethereum-side recovery
   separately.

4. **Single Ethereum ProxyAdmin:** There is one shared ProxyAdmin on Ethereum,
   deployed in Step 0 (`DeployXWellEthereum.s.sol`). MIP-X56 reuses it for the
   MultichainGovernorV2 and VotingPowerAggregator proxies (skips deployment if
   `PROXY_ADMIN` is already set in the addresses registry). ProxyAdmin ownership
   is transferred to MultichainGovernorV2 inside `mip-x56.afterDeploy`.

5. **Moonbeam TemporalGovernor:** Deployed as a non-upgradeable contract (not
   behind a proxy). Trusted sender is set at deployment time to Ethereum
   MultichainGovernorV2.

6. **HybridProposal routing:** The framework routes Moonbeam actions directly,
   and Base/Optimism actions via Wormhole. It does **not** route Ethereum
   actions — Ethereum-side configuration is therefore handled by the interim
   Moonbeam proposal (which can publish Wormhole messages cross-chain) and the
   first MultichainGovernorV2 proposal.

7. **Atomic governor proxy initialization:** The Ethereum MultichainGovernorV2
   proxy is deployed with its `initialize(...)` payload encoded into the
   `TransparentUpgradeableProxy` constructor `_data` argument so init runs in
   the same transaction as proxy creation. The Moonbeam TemporalGovernor and
   VoteCollectionMoonbeam need the Ethereum proxy address as a trusted sender at
   deploy time, but the Ethereum proxy's own init data needs the Moonbeam
   VoteCollection address — this circular dependency is resolved inside
   `deploy()` by computing the Ethereum proxy's CREATE address from the
   deployer's nonce, deploying the cross-chain dependents against it, then
   deploying the proxy and asserting the deployed address matches.

---

## Risk Considerations

- **Wormhole dependency:** All cross-chain communication relies on Wormhole. If
  Wormhole is unavailable, satellite chain governance execution is delayed.
- **Deployer trust window:** Between the interim proposal's Ethereum execution
  and the first MultichainGovernorV2 proposal accepting ownership, the
  **PAUSE_GUARDIAN multisig** holds Ethereum xWELL ecosystem ownership. The
  window is bounded by governance turnaround on the first Ethereum proposal.
- **Two-step ownership gap:** Until the first MultichainGovernorV2 proposal
  calls `acceptOwnership()`, xWELL and WormholeBridgeAdapter on Ethereum have
  **PAUSE_GUARDIAN multisig** as the actual owner and MultichainGovernorV2 as
  pending owner. This is a deliberate, time-bounded handoff and is safe because
  PAUSE_GUARDIAN already holds emergency authority across the system.
- **Moonbeam admin gap:** Until the follow-up proposal calls `_acceptAdmin()`,
  Moonbeam mTokens and Unitroller have MultichainGovernor (old, now defunct) as
  admin and TemporalGovernor as pendingAdmin. The old governor can't create new
  proposals, so this state is safe but should be resolved promptly.
- **Deployer Ethereum-nonce stability:** The atomic governor proxy deploy relies
  on the deployer's Ethereum nonce being unchanged between the address
  prediction step and the final proxy deployment. The deployer must not send any
  other Ethereum transactions while `mip-x56.deploy()` is in flight. The script
  asserts deployed address == predicted and reverts if the nonce shifted, so a
  bad outcome surfaces as a clean revert rather than an uninitialized proxy.
