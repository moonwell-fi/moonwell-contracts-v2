# MultichainGovernorV2 — Frontend & Indexer Integration Guide

This document lists **only what is new or changed** relative to V1 (the
Moonbeam-based `MultichainGovernor`). Anything not mentioned here keeps its
existing V1 signature and semantics. The companion design doc
(`MULTICHAIN_GOVERNOR_V2.md`) explains the motivation.

## 1. Summary of changes

- **Hub chain moved from Moonbeam to Ethereum.** Moonbeam becomes a remote vote
  collector (`MultichainVoteCollectionMoonbeam`) alongside Base and Optimism
  (`MultichainVoteCollectionV2`).
- **Two-phase `propose()`** with IPFS `descriptionUri` instead of an inline
  `description` string.
- **New `ProposalState.Init`** for proposals that exist but are not yet
  finalized — no voting while in this state.
- **Voting power is read through the new `VotingPowerAggregator`** (one per
  chain). Sources: `xWELL` (always included) + snapshot sources implementing
  `SnapshotInterface`. Currently only `stkWELL`; **WELL and distributor are no
  longer voting sources.**
- **Proposals expire.** `execute()` reverts if
  `block.timestamp > crossChainVoteCollectionEndTimestamp + _executionWindow` (7
  days).
- **Custom errors replace string reverts.** Clients parsing revert reasons need
  a selector-based lookup.
- **Event renamed:** `QuroumVotesChanged` → `QuorumVotesChanged`.

## 2. Deployed contracts

Addresses will be filled in after mip-x52 executes. Resolve by label:

| Label                          | Chain                              | Notes                                         |
| ------------------------------ | ---------------------------------- | --------------------------------------------- |
| `MULTICHAIN_GOVERNOR_V2_PROXY` | Ethereum                           | New hub governor                              |
| `VOTING_POWER_AGGREGATOR`      | Ethereum, Moonbeam, Base, Optimism | New, one per chain                            |
| `VOTE_COLLECTION_V2_PROXY`     | Moonbeam                           | `MultichainVoteCollectionMoonbeam` (upgraded) |
| `VOTE_COLLECTION_V2_PROXY`     | Base, Optimism                     | `MultichainVoteCollectionV2` (upgraded)       |

Wormhole chain IDs: Ethereum = 2, Moonbeam = 16, Base = 30, Optimism = 24.

## 3. New / changed events

### 3.1 `MultichainGovernorV2` — `src/governance/multichain/IMultichainGovernorV2.sol`

| Status  | Signature                                                                                                                                                                      | Purpose                                                                                 |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------- |
| NEW     | `ProposalInitialized(address proposer, uint256 proposalId, string descriptionUri)`                                                                                             | First `propose()` call in chunk mode; proposal is in `Init`.                            |
| NEW     | `ProposalAppended(address proposer, uint256 proposalId)`                                                                                                                       | Additional targets/calldatas appended (still `Init`).                                   |
| CHANGED | `ProposalCreated(uint256 id, address proposer, address[] targets, uint256[] values, bytes[] calldatas, uint256 votingStartTime, uint256 votingEndTime, string descriptionUri)` | Fires once on `finalize=true`. Last arg is now `descriptionUri` (V1 was `description`). |
| RENAMED | `QuorumVotesChanged(uint256 oldValue, uint256 newValue)`                                                                                                                       | V1 typo fixed — `QuroumVotesChanged` is gone.                                           |

### 3.2 `VotingPowerAggregator` — `src/governance/multichain/IVotingPowerAggregator.sol` (new contract)

| Signature                               | Purpose                                                                 |
| --------------------------------------- | ----------------------------------------------------------------------- |
| `SnapshotSourceAdded(address source)`   | A `SnapshotInterface` source was added (owner = governor after deploy). |
| `SnapshotSourceRemoved(address source)` | Source removed.                                                         |

### 3.3 Vote collection contracts — `IMultichainVoteCollection.sol`

| Status  | Signature                                 | Purpose                                                                      |
| ------- | ----------------------------------------- | ---------------------------------------------------------------------------- |
| REMOVED | `NewStakedWellSet(address newStakedWell)` | stkWELL is no longer tracked directly — it's now a source on the aggregator. |

All other vote-collection events (`ProposalCreated`, `VoteCast`, `VotesEmitted`)
are unchanged in shape — indexers only need to point at the new addresses on
each chain.

## 4. New / changed external functions

### 4.1 `MultichainGovernorV2`

**New writes:**

- `propose(address[] targets, uint256[] values, bytes[] calldatas, string descriptionUri, bool finalize) payable returns (uint256 proposalId)`
  — initial chunk. If `finalize=true`, emits `ProposalCreated` and bridges to
  remotes; otherwise leaves proposal in `Init`.
- `propose(uint256 proposalId, address[] targets, uint256[] values, bytes[] calldatas, bool finalize) payable`
  — append to an `Init` proposal. The final call with `finalize=true` triggers
  bridging.
- `rebroadcastProposal(uint256 proposalId) payable` — re-bridge a proposal to
  remotes if Wormhole was paused at the original finalize time. Emits
  `ProposalRebroadcasted`.

**Changed writes:**

- `execute(uint256 proposalId) payable` — now reverts if past the execution
  window.

**New reads:**

- `getProposalData(uint256 proposalId) returns (address[] targets, uint256[] values, bytes[] calldatas)`
- `liveProposals() returns (uint256[])`
- `getNumLiveProposals() returns (uint256)`
- `proposalActive(uint256 proposalId) returns (bool)`
- `isWhitelistedCalldata(bytes data) returns (bool)`
- `chainAddressVotes(uint256 proposalId, uint16 chainId) returns (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes)`
- `votingPower() returns (address)` — the `VotingPowerAggregator` address.

**Removed / internalized (clients must stop calling):**

- `getUserLiveProposals(address)` — use `currentUserLiveProposals(address)`.
- public `whitelistedCalldatas(bytes)` — use `isWhitelistedCalldata(bytes)`.
- direct `xWell()`, `well()`, `stkWell()`, `distributor()` getters — all go
  through `votingPower()`.
- `useTimestamps` flag — V2 is always timestamp-based.
- `maxUserLiveProposals` setter — now an internal constant (3).

### 4.2 `VotingPowerAggregator` (new contract, full surface)

**Reads:**

- `getVotes(address account, uint256 timestamp) returns (uint256)` — **use this
  for "votes at snapshot".** Pass `proposal.voteSnapshotTimestamp`.
- `getCurrentVotes(address account) returns (uint256)` — live weight.
- `isSnapshotSource(address source) returns (bool)`
- `xWell() returns (address)`
- `owner() returns (address)` — governor after mip-x52.

**Permissioned (owner = governor):**

- `addSnapshotSource(address source)`
- `removeSnapshotSource(address source)`

### 4.3 Vote collection contracts

**Changed reads:**

- `getVotes(address account, uint256 timestamp) returns (uint256)` — now
  delegates to the local `VotingPowerAggregator` (V1 queried stkWELL directly).
- `votingPower() returns (address)` — new getter replacing the V1 stkWELL
  reference.

All other vote-collection externals (`castVote`, `emitVotes`, `getReceipt`,
`proposalInformation`, `proposalVotes`, `bridgeCost`, `wormhole`) keep their V1
shape.

## 5. New / changed structs & enums

### `ProposalState` — NEW `Init` variant

```solidity
enum ProposalState {
  Active, // 0
  CrossChainVoteCollection, // 1
  Canceled, // 2
  Defeated, // 3
  Succeeded, // 4
  Executed, // 5
  Init // 6 — NEW; created but not finalized
}
```

### `InitializeData` — new (deploy/validator tooling only)

```solidity
struct InitializeData {
  address votingPower;
  uint256 proposalThreshold;
  uint256 votingPeriodSeconds;
  uint256 crossChainVoteCollectionPeriod;
  uint256 quorum;
  uint128 pauseDuration;
  uint128 startingProposalCount;
  address pauseGuardian;
  address breakGlassGuardian;
  address wormholeCore;
}
```

`Receipt`, `MultichainVotes`, `ProposalInformation`, and `TrustedSender` are
unchanged.

## 6. Migration checklist

### Indexer

- Switch primary source of proposal lifecycle from the Moonbeam V1 governor to
  the Ethereum V2 governor. Keep V1 read-only for history.
- Schema updates: `description` → `descriptionUri`; add `finalized: bool`;
  extend state enum with `Init`; add `ProposalInitialized` / `ProposalAppended`;
  rename `QuroumVotesChanged` → `QuorumVotesChanged`; drop `NewStakedWellSet`.
- For per-chain vote breakdowns, prefer reading
  `chainAddressVotes(proposalId, chainId)` over summing events.

### Frontend

- **Voting power:** always read
  `VotingPowerAggregator.getVotes(account, proposal.voteSnapshotTimestamp)` (or
  `VoteCollection.getVotes(...)` on remotes). Stop calling xWELL / stkWELL
  directly.
- **Tokens shown as "your voting power":** xWELL + stkWELL only. Direct WELL
  holders to migrate to xWELL.
- **Error toasts:** parse custom-error selectors. Common ones: `ZeroAddress()`,
  `OnlyGovernor()`, `OnlyBreakGlassGuardian()`, `CalldataAlreadyApproved()`,
  `CalldataNotApproved()`, `InvalidProposalState(...)`,
  `BreakGlassGuardianNotNull()`, `BreakGlassCallFailed()`.
