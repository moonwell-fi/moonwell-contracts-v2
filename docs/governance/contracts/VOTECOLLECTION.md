# Vote Collection

For every chain external to Moonbeam, a single vote collection contract will be
created. Users can put their votes on these contracts, and they will be relayed
back to Moonbeam for governance counting. The Vote Collection is only live on
the Base chain since it has the Moonwell contracts deployed, apart from
Moonbeam.

## Overview

When a proposal is created on Moonbeam, a message is sent to the Vote Collection
contract via Wormhole. The message holds the proposal id, the start and end
timestamps of the voting period, the voting snapshot timestamp, and the
cross-chain vote collection end timestamp. The Vote Collection contract collects
proposal votes throughout the voting period. After the voting period ends,
anyone can relay the votes back to Moonbeam for counting. Although the relay of
votes can happen multiple times, they will only get counted once on Moonbeam.

## Permissionless Actions

### Vote

Any address can vote on a proposal by calling the `castVote` function. Users can
vote `for`, `against`, or `abstain` on a proposal.

The following tokens are used for voting:

- xWELL: The Moonwell bridged token
- Staked xWELL: The Moonwell staked token

### Emit Votes

Anyone can emit votes to Moonbeam by calling the `emitVotes` function. The
caller must provide the proposal id they are relaying the votes for and pay for
the Wormhole bridge cost (bridgeCost function is available to check needed
amount). Wormhole will then relay the votes to Moonbeam for counting. Although
the relay of votes can happen multiple times, they will only get counted once on
Moonbeam.

## View Only Functions

- `getReceipt`: Returns the vote receipt of a voter for a proposal
- `proposalInformation`: Returns the proposal information for a given proposal
  id. Includes the proposer, vote snapshot timestmap, vote start timestamp, vote
  end timestamp, corss chain vote collection end timestamp, for votes, against
  votes and abstain votes.
- `proposalVotes`: Returns the vote count for a proposal
- `getVotes`: Returns the total voting power for an address at a given block
  number and timestamp. well, xWell, stkWell and distributor

## Only Owner Functions

The Vote Collection is owned by the [Temporal Governor](TEMPORALGOVERNOR.md)
contract. Only the Temporal Governor can call the functions below. This means
that a proposal must be created on Moonbeam and passed to the Temporal Governor
to update these parameters.

- `setGasLimit`: Sets the gas limit for the emitVotes function
- `setNewStakeWell`: Update the staked WELL token address
