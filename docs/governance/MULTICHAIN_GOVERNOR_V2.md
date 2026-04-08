# MultichainGovernorV2

## Overview

The `propose()` function consumes the most gas because we have no cap on the
calldatas/targets and because we pass the full description string.

This refactor contains a few major changes

1. `propose()` function signature allows users to specify subsequent calls to
   append targets/calldatas
2. proposal `description` ~> `descriptionUri`
3. proposals must be executed before they expire
4. new contract `VotingPowerAggregator` to handle vote sources. used by
   `MultichainGovernorV2` and `MultichainVoteCollectionV2`
5. custom revert errors
6. reducing contract size: removing unused `getUserLiveProposals()` view
   function and changing `whitelistedCalldatas` from public to private
7. changes in vote sources, only using timestamps now and assuming that stkwell
   will be upgraded, and well + distributor contracts on moonbeam will not be
   used

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

A new variable `_executionWindow` defines the time (in seconds) that a succeeded
proposal has to be executed. This prevents old proposals from being executed at
any point in the future after it's succeeded.

We dynamically calculate this value in the `execute()` function by checking the
current block timestamp is within
`proposal.crossChainVoteCollectionEndTimestamp + _executionWindow`

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

Moonbeam version of stkWell is old and using blocknumber for the snapshots. We
must preserve this functionality on Moonbeam.

### custom revert errors

Instead of `require()` with string literals, we use the more gas efficient
custom revert errrors introduced in solidity `v0.8.4`

### reducing contract size

To further reduce contract size, we did the following:

- It does not seem we needed public functions for `getUserLiveProposals()` and
  `whitelistedCalldatas` as they were not referenced anywhere in the repo,
  moonwell client, or indexer.
- We removed the governance-only setter for `maxUserLiveProposals` in favor of a
  constant (the same onchain value it is now - `2`)
- Remove uncecessary `proposalInformation()` view function when storage variable
  for `proposals` is public

### MultichainVoteCollectionV2

For consistency, the `MultichainVoteCollectionV2` has been updated to use the
new `VotingPowerAggregator` contract. An instance of this contract should have
`stkWell` sources added via `addSnapshotSource`.

The already deployed instances (ie on Base, Optimism) of this contract need to
be re initialized.

### changes in vote sources

Given that we are standardizing the `VotingPowerAggregator` contract for voting
sources across all chains, we realized that the Moonbeam voting sources included
contracts (well, distributor) that relied on the `block.number` for the
snapshots, while the rest of the chains only used timestamps. Since the new
governor will be on Ethereum, and cannot rely on the blocknumber on Moonbeam for
these contracts.

Furthermore, most holders have migrated to the xWell token. The plan is to
upgrade the stkWell contract on all chains to a) remove a faulty function
(unrelated) and b) switch the snapshot logic to use timestamps.

For these reasons, we will be

1. removing the well and distributor contracts as voting sources on Moonbeam
   (most users have migrated to xWell and can use timelock contract for voting.
   as for distributor, most tokens have vested)
2. assuming that stkWell will be upgraded to use timestamps for snapshot voting
3. removing any use of block numbers from `MultichainVoteCollectionV2` and
   `VotingPowerAggregator`
