# Moonwell Governance Migration: MIP-X43 + MIP-X44 Audit Brief

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
| 1    | `mip-x43.sol` — deploy + submit      | Deployer   | Moonbeam, Base, OP, Ethereum       |
| 2    | `mip-x43.sol` — proposal executes    | Governance | Moonbeam → Base, OP (via Wormhole) |
| 3    | `mip-x44.sol` — deploy + afterDeploy | Deployer   | All 4 chains                       |
| 4    | `mip-x44.sol` — proposal executes    | Governance | Moonbeam → Base, OP (via Wormhole) |
| 5    | `PostDeployEthereumXWell.s.sol`      | Deployer   | Ethereum                           |

Step 0 is already complete (xWELL, stkWELL, WormholeBridgeAdapter, ProxyAdmin,
EcosystemReserve are live on Ethereum).

---

## MIP-X43: Prerequisite Upgrades

### Purpose

Prepare the existing system for migration by upgrading stkWELL across chains and
establishing Ethereum xWELL trust relationships.

### Actions

**Moonbeam (executed by MultichainGovernor):**

- `upgradeAndCall` stkWELL proxy to V2 with `initializeV2()` via
  `MOONBEAM_PROXY_ADMIN` — switches snapshot logic from block numbers to
  timestamps
- Call `setNewStakedWell(stkWELL, toUseTimestamps=true)` on MultichainGovernor
  to enable timestamp-based voting
- Add Ethereum WormholeBridgeAdapter as a trusted sender on Moonbeam's
  WormholeBridgeAdapter

**Base (via Wormhole from MultichainGovernor):**

- Upgrade stkWELL to V2 — removes faulty `configureAssets` function
- Add Ethereum WormholeBridgeAdapter as a trusted sender on Base's
  WormholeBridgeAdapter

**Optimism (via Wormhole from MultichainGovernor):**

- Upgrade stkWELL to V2 — same as Base
- Add Ethereum WormholeBridgeAdapter as a trusted sender on Optimism's
  WormholeBridgeAdapter

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

## MIP-X44: Governance Migration

### Purpose

Deploy the new governance infrastructure on Ethereum and migrate all contract
ownership from the Moonbeam MultichainGovernor to the new system.

### Deployment Phase (deployer-run)

**Ethereum:**

- Deploy MultichainGovernorV2 (impl + proxy via ProxyAdmin)
- Deploy VotingPowerAggregator (impl + proxy via ProxyAdmin)
- Set EMISSIONS_ADMIN = MultichainGovernorV2 proxy

**Moonbeam:**

- Deploy TemporalGovernor (non-upgradeable) — trusted sender: Ethereum
  MultichainGovernorV2
- Deploy VotingPowerAggregator (impl + proxy via MOONBEAM_PROXY_ADMIN)
- Deploy MultichainVoteCollectionMoonbeam (impl + proxy via
  MOONBEAM_PROXY_ADMIN)

**Base:**

- Deploy VotingPowerAggregator (impl + proxy via MRD_PROXY_ADMIN)
- Deploy MultichainVoteCollectionV2 implementation (upgrade target for existing
  proxy)

**Optimism:**

- Same as Base

### afterDeploy Phase (deployer-run)

**Ethereum:**

- Read `proposalCount` from Moonbeam MultichainGovernor
- Initialize MultichainGovernorV2 with
  `startingProposalCount = moonbeam.proposalCount + 1`
- Configure trusted senders: Moonbeam VoteCollectionV2, Base VoteCollection, OP
  VoteCollection
- Configure break glass guardian with 8 whitelisted calldatas (3
  publishMessage + 5 admin functions)
- Configure VotingPowerAggregator: `setXWell`, `addSnapshotSource(stkWELL)`,
  transfer ownership to governor

### Proposal Actions (executed by old Moonbeam MultichainGovernor)

**Moonbeam (executed by MultichainGovernor):**

1. Upgrade MultichainGovernor to v1.1 (adds `recoverETH()` function)
2. Call `recoverETH(WELL_FOUNDATION_MULTISIG)` to recover stuck ETH
3. Add stkWELL as snapshot source on Moonbeam VotingPowerAggregator
4. Transfer VotingPowerAggregator ownership to Moonbeam TemporalGovernor
5. Transfer ownership of ~20+ contracts from MultichainGovernor to
   TemporalGovernor:
   - Ownable contracts → `transferOwnership(temporalGovernor)`
   - mTokens/Unitroller → `_setPendingAdmin(temporalGovernor)`
   - ChainlinkOracle → `setAdmin(temporalGovernor)`
   - stkWELL → `setEmissionsManager(temporalGovernor)`

**Base (via Wormhole from Moonbeam):**

1. Upgrade MultichainVoteCollection proxy to V2 implementation
2. Call `initializeV2(votingPowerAggregator, ethChainId, ethGovernorV2)` — sets
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

These actions cannot be completed during MIP-X43/X44 and must be handled via a
subsequent governance proposal from the new Ethereum MultichainGovernorV2:

### 1. acceptOwnership() on Ethereum contracts

MultichainGovernorV2 must call `acceptOwnership()` on:

- **xWELL** (Ownable2Step — pendingOwner is set by PostDeployEthereumXWell)
- **WormholeBridgeAdapter** (Ownable2Step — pendingOwner is set by
  PostDeployEthereumXWell)

Until these calls are made, ownership transfer is incomplete (deployer is still
current owner).

### 2. \_acceptAdmin() on Moonbeam contracts

MIP-X44 calls `_setPendingAdmin(temporalGovernor)` on Moonbeam mTokens and
Unitroller. To complete the admin transfer, TemporalGovernor must call
`_acceptAdmin()` on each contract. This requires a Wormhole message from the
Ethereum governor → Moonbeam TemporalGovernor → `_acceptAdmin()`.

**Why this can't be in MIP-X44:** `_acceptAdmin()` requires
`msg.sender == pendingAdmin` (TemporalGovernor). TemporalGovernor can only
execute via Wormhole from the Ethereum governor, which has no proposals yet
during MIP-X44 execution.

### 3. VotingPowerAggregator ownership on Ethereum

The VotingPowerAggregator uses Ownable (1-step transfer), and ownership is
transferred to MultichainGovernorV2 in `afterDeploy`. This is already complete —
no follow-up needed.

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
   deployed in Step 0 (`DeployXWellEthereum.s.sol`). MIP-X44 reuses it for the
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

---

## Risk Considerations

- **Wormhole dependency:** All cross-chain communication relies on Wormhole. If
  Wormhole is unavailable, satellite chain governance execution is delayed.
- **Deployer trust window:** Between MIP-X44 execution and
  PostDeployEthereumXWell completion, the deployer still controls Ethereum xWELL
  ecosystem contracts. This window should be minimized.
- **Two-step ownership gap:** Until the follow-up proposal calls
  `acceptOwnership()`, xWELL and WormholeBridgeAdapter on Ethereum have the
  deployer as actual owner and MultichainGovernorV2 as pending owner.
- **Moonbeam admin gap:** Until the follow-up proposal calls `_acceptAdmin()`,
  Moonbeam mTokens and Unitroller have MultichainGovernor (old, now defunct) as
  admin and TemporalGovernor as pendingAdmin. The old governor can't create new
  proposals, so this state is safe but should be resolved promptly.
