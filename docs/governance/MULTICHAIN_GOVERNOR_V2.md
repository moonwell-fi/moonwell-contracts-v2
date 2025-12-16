# MultichainGovernorV2

## Overview

The `propose()` function consumes the most gas because we have no cap on the
calldatas/targets and because we pass the full description string.

This refactor contains a few major changes

1. `propose()` function signature allows users to specify subsequent calls to
   append targets/calldatas
2. proposal `description` ~> `descriptionUri`
3. proposals must be executed before they expire
4. new contract `VotingPowerAggregator` to handle vote sources

## Changes in detail

### propose

There are now two `propose` functions. A new function argument `finalize` allows
the proposer to chunk their proposal targets.

For example the proposer can

1. pass `finalize=false` to the first call
2. receive the `proposalId` in the response or event data
3. subsequently call the other `propose` function as many times with the
   targets/calldatas before finally passing `finalize=true` which will emit the
   `ProposalCreated` event and relay the proposal information payload to other
   chains

A new `finalized` boolean has been added to the `Proposal` struct to support
this new flow.

### descriptionUri

The full proposal description can go on IPFS and the uri onchain.

Since we only accept the `descriptionUri` in the first `propose()` step, we now
store it in the `Proposal` struct so it can be referenced in the finalize step
for the `ProposalCreated` event.

### proposals expire

A new governance-controlled variable `executeExpirationWindow` defines the time
(in seconds) that a succeeded proposal has to be executed. This prevents old
proposals from being executed at any point in the future after it's succeeded.

We use an internal mapping `_proposalExecutionExpiries` to track this per
proposal
(`proposal.crossChainVoteCollectionEndTimestamp + executeExpirationWindow`).
Including this value in the `Proposal` struct caused stack trace too deep
errors. Alternatively, we could dynamically calculate this value in the
`execute()` function - knowing that the `executeExpirationWindow` is the only
variable that would change with a governance proposal.

### VotingPowerAggregator

A new contract `VotingPowerAggregator` handles voting sources and tallying up a
user's voting power using those sources.

The two view functions `getVotes()` and `getCurrentVotes` are fully supported,
and can read from the same sources as before (well, xWell, stkWell,
distributor). We generalize the adding and removing of sources that implement
the `SnapshotInterface`, and so these sources are not included in the contract
initializer, but added with `addSnapshotSource`. The exception to this is
`xWell` and we treat it as a custom source.

The ideal way to support new sources in the future is by creating a wrapper
contract around the source that implements `SnapshotInterface` and adding it as
a snapshot source.

For custom sources, we'd have to upgrade the contract and modify the internal
funtions to get custom votes.

**NOTE**: v1 governor contract has `useTimestamps` to determine whether the
source `stkWell` uses timestamp or block number

```solidity
uint256 stkWellVotes = stkWell.getPriorVotes(
    account,
    useTimestamps ? timestamp : blockNumber
);
```

The onchain value for this is `false` - and given the value is updated by
governance, it was assumed this value could remain false - which would mean all
snapshot sources use `block.number` when getting the vote snapshot.
