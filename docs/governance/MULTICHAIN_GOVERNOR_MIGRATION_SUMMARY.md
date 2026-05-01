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

## PostDeployEthereumXWell: Ethereum Configuration

### Purpose

Configure xWELL ecosystem ownership on Ethereum after MultichainGovernorV2 is
live.

### Actions (5 steps, deployer-run)

1. Grant pause guardian role on xWELL to PAUSE_GUARDIAN
2. Set emissions manager on stkWELL to EMISSIONS_ADMIN (= MultichainGovernorV2
   proxy)
3. Transfer ownership of xWELL to MultichainGovernorV2 (2-step: sets
   pendingOwner)
4. Transfer ownership of WormholeBridgeAdapter to MultichainGovernorV2 (2-step:
   sets pendingOwner)
5. Transfer ownership of ProxyAdmin to MultichainGovernorV2 (1-step: immediate)

### Post-execution validation

- xWELL pendingOwner == MultichainGovernorV2
- WormholeBridgeAdapter pendingOwner == MultichainGovernorV2
- ProxyAdmin owner == MultichainGovernorV2

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

## Follow-Up Items (Require Separate Proposal)

These actions cannot be completed during MIP-X45/X56 and must be handled via a
subsequent governance proposal from the new Ethereum MultichainGovernorV2:

### 1. First Ethereum Proposal: Accept Ownership + addTrustedSenders

The first proposal submitted to MultichainGovernorV2 must complete ownership
transfers and establish cross-chain xWELL bridging trust relationships. The
actions must be executed in this order within the proposal:

**Step 1 — Accept ownership on Ethereum:**

MultichainGovernorV2 calls `acceptOwnership()` on:

- **xWELL** (Ownable2Step — pendingOwner is set by PostDeployEthereumXWell)
- **WormholeBridgeAdapter** (Ownable2Step — pendingOwner is set by
  PostDeployEthereumXWell)
- **VotingPowerAggregator (Ethereum)** (Ownable2Step — pendingOwner is set by
  MIP-X56 `afterDeploy`)

Until these calls are made, ownership transfer is incomplete (deployer is still
current owner for xWELL/WormholeBridgeAdapter; Moonbeam governor still effective
owner for the aggregator until acceptance).

The same proposal should also relay a Wormhole message to Moonbeam
TemporalGovernor to call `acceptOwnership()` on the **Moonbeam
VotingPowerAggregator** (pendingOwner set during MIP-X56 Moonbeam execution).

**Step 2 — addTrustedSenders on all chains:**

Once the governor owns the Ethereum WormholeBridgeAdapter (from Step 1), it can
configure cross-chain trust relationships. The proposal calls
`addTrustedSenders()` on:

- **Ethereum** WormholeBridgeAdapter — add Moonbeam, Base, and Optimism adapters
  as trusted senders (executed directly on Ethereum)
- **Moonbeam** WormholeBridgeAdapter — add Ethereum adapter as trusted sender
  (via Wormhole → TemporalGovernor)
- **Base** WormholeBridgeAdapter — add Ethereum adapter as trusted sender (via
  Wormhole → TemporalGovernor)
- **Optimism** WormholeBridgeAdapter — add Ethereum adapter as trusted sender
  (via Wormhole → TemporalGovernor)

This enables cross-chain xWELL bridging to and from Ethereum. On Moonbeam, Base,
and Optimism, the WormholeBridgeAdapters are owned by their respective
TemporalGovernors, which execute via Wormhole messages from the Ethereum
governor.

**Step 3 — \_acceptAdmin() on Moonbeam contracts:**

MIP-X56 calls `_setPendingAdmin(temporalGovernor)` on Moonbeam mTokens and
Unitroller. To complete the admin transfer, TemporalGovernor must call
`_acceptAdmin()` on each contract. This is sent as a Wormhole message from the
Ethereum governor → Moonbeam TemporalGovernor → `_acceptAdmin()`.

**Why this can't be in MIP-X56:** `_acceptAdmin()` requires
`msg.sender == pendingAdmin` (TemporalGovernor). TemporalGovernor can only
execute via Wormhole from the Ethereum governor, which has no proposals yet
during MIP-X56 execution.

### 2. VotingPowerAggregator ownership (Ethereum and Moonbeam)

The VotingPowerAggregator uses `Ownable2StepUpgradeable` (matching
MultichainVoteCollectionV2) so misconfigured transfers are reversible. MIP-X56
only sets `pendingOwner` on the Ethereum and Moonbeam aggregators; the first
Ethereum follow-up proposal must:

- Call `acceptOwnership()` on the Ethereum VotingPowerAggregator (direct
  Ethereum action).
- Relay a Wormhole message to Moonbeam TemporalGovernor to call
  `acceptOwnership()` on the Moonbeam VotingPowerAggregator.

Base and Optimism VotingPowerAggregators are initialized with TemporalGovernor
as owner via `_transferOwnership` in the initializer, so they are already fully
owned on-chain after MIP-X56 deployment — no follow-up needed for those chains.

---

## Key Design Decisions

1. **Timestamp-based voting:** All VotingPowerAggregators use timestamps (not
   block numbers) for snapshot consistency across chains.

2. **Proposal ID continuity:** MultichainGovernorV2 starts with
   `startingProposalCount = moonbeam.proposalCount + 1`, ensuring proposal IDs
   never overlap.

3. **Break glass guardian:** 8 whitelisted calldatas allow emergency rollback of
   ownership to PAUSE_GUARDIAN multisig across all chains.

4. **Single Ethereum ProxyAdmin:** There is one shared ProxyAdmin on Ethereum,
   deployed in Step 0 (`DeployXWellEthereum.s.sol`). MIP-X56 reuses it for the
   MultichainGovernorV2 and VotingPowerAggregator proxies (skips deployment if
   `PROXY_ADMIN` is already set in the addresses registry). ProxyAdmin ownership
   is transferred to MultichainGovernorV2 via PostDeployEthereumXWell.

5. **Moonbeam TemporalGovernor:** Deployed as a non-upgradeable contract (not
   behind a proxy). Trusted sender is set at deployment time to Ethereum
   MultichainGovernorV2.

6. **HybridProposal routing:** The framework routes Moonbeam actions directly,
   and Base/Optimism actions via Wormhole. It does **not** route Ethereum
   actions — hence why Ethereum configuration requires the separate
   PostDeployEthereumXWell script.

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
- **Deployer trust window:** Between MIP-X56 execution and
  PostDeployEthereumXWell completion, the deployer still controls Ethereum xWELL
  ecosystem contracts. This window should be minimized.
- **Two-step ownership gap:** Until the follow-up proposal calls
  `acceptOwnership()`, xWELL and WormholeBridgeAdapter on Ethereum have the
  deployer as actual owner and MultichainGovernorV2 as pending owner.
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
