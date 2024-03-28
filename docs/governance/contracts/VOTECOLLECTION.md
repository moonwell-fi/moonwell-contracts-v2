# Vote Collection

For every chain external to Moonbeam, a single vote collection contract will be
created. Users can place their votes in these contracts, and their votes will be
relayed back to Moonbeam where they will be tallied in the Multichain Governor.
The Vote Collection contract is only live on the Base chain. In the future, if
xWELL is deployed to other chains, a Vote Collection contract could be deployed
on those chains also, and if the DAO votes to register that Vote Collection
contract in the Multichain Governor on Moonbeam, then the votes from that chain
will be relayed back to Moonbeam and counted in governance votes.

## Overview

When a proposal is created on Moonbeam, a message is sent to the Vote Collection
contract via Wormhole. This message holds the proposal identifier, the start and
end timestamps of the voting period, the voting snapshot timestamp, and the
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
- Staked xWELL: WELL tokens staked in the Safety Module

### Emit Votes

Anyone can emit votes to Moonbeam during the Vote Collection Period by calling
the `emitVotes` function. The caller must provide the proposal id they are
relaying the votes for and pay the Wormhole bridge cost. The `bridgeCost`
function is available to check the amount. Wormhole will then relay the votes to
Moonbeam for counting. Although the relay of votes can happen multiple times,
they will only get counted once on Moonbeam. All subsequent calls to that
register the result of emitVotes on Moonbeam will be ignored and the
transactions will revert.

## View Only Functions

- `getReceipt`: Returns the vote receipt of a voter for a proposal
- `proposalInformation`: Returns the proposal information for a given proposal
  id. Includes the proposer, vote snapshot timestmap, vote start timestamp, vote
  end timestamp, cross chain vote collection end timestamp, for votes, against
  votes and abstain votes.
- `proposalVotes`: Returns the vote count for a proposal
- `getVotes`: Returns the total voting power for an address at a given block
  number and timestamp. well, xWell, stkWell and distributor

## Only Owner Functions

The Vote Collection is owned by the [Temporal Governor](TEMPORALGOVERNOR.md)
contract. Only the Temporal Governor can call the functions below. This means
that a proposal must be created on Moonbeam and passed to the Temporal Governor
to update these parameters.

- `setGasLimit`: Sets the gas limit for the emitVotes function. Can be used if
  gas costs on Moonbeam or Base change.
- `setNewStakeWell`: Update the staked WELL token address. Can be used to set a
  new Safety Module address when the Safety Module is upgraded.

## Security Considerations

The Vote Collection contract makes many assumptions.

1. The voting source contracts do not change.

   - The Vote Collection contract was originally designed to work on L2's and
     other chains, and synchronizing block numbers across multiple chains in a
     rapidly changing environment could be difficult and create unintended
     consequences if block times change.

2. The block timestamp does not differ by more than 45 seconds between Moonbeam
   and the external chain.

   - at a larger time difference than 45 seconds, the vote collection contract
     is at risk of allowing users to register double votes by first voting on
     Moonbeam, and then briding to and voting on an external chain.

3. The Wormhole bridge is live and working properly.

   - if Wormhole is paused or offline, the Vote Collection contract will still
     be able to collect votes, however, votes will not be able to be sent to the
     Multichain Governor.
   - if Wormhole becomes malicious, it could prevent the Vote Collection
     contract from collecting votes by blocking a new valid proposal from being
     registered.
