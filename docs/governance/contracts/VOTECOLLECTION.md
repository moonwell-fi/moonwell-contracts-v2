# Vote Collection

On chains external to Moonbeam, there will be one vote collection contract per
chain where users are allowed to place votes to be relayed back to moonbeam for
counting in governance. Vote Collection is live only on Base because is the only
chain besides Moonbeam that has the Moonwell contracts deployed.

## Overview

When a proposal is created on Moonbeam, a message is deliver y to the vote
collection contract through Wormhole. The message payload contains the proposal
id, the start and end timestamp for the voting period, the voting snapshot
timestamp and the cross chain vote collection end timestamp. The vote collection
contract will collect votes for the proposal during the voting period. After the
voting period has ended, anyone can relay the votes back to Moonbeam for
counting. Votes can be relayed back to Moonbeam as many times as users want but
votes will only be counted on Moonbeam once.

## Permissionless Actions

### Vote

Any address can vote on a proposal by calling the `castVote` function. Users can
vote `for`, `against`, or `abstain` on a proposal.

The following tokens are used for voting:

- xWELL: The Moonwell bridged token
- Staked xWELL: The Moonwell staked token

### Emit Votes

Any address can emit votes to Moonbeam by calling the `emitVotes` function. The
caller must provide the proposal id they are relaying votes for. Wormhole will
relay the votes to Moonbeam for counting. Votes can be relayed back to Moonbeam
as many times as users want but votes will only be counted on Moonbeam once.

## View Only Functions
