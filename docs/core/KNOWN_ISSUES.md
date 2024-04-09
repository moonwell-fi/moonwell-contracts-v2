# Multichain Governor Known Issues

Here is a list of known issues for the Multichain Governor and Vote Collector
smart contracts.

## Wormhole Dependency

If wormhole goes offline, or pauses their relayer or wormhole core contracts,
the Multichain Governor and Vote Collector will not be able to function. This is
because the Multichain Governor passes messages to the Wormhole contract, and
the Vote Collector receives messages from the Wormhole Relayer. If Wormhole is
offline, on either chain, the system is considered broken and will not function.

## System Parameters

System parameters are very important, and if set incorrectly, they can cause the
system to not function properly.

Here is a collection of edge cases that can occur if the system parameters are
incorrect:

If maximum user live proposals is set to zero, users will be unable to create
proposals. This is mitigated by the `_setMaxUserLiveProposals` function, which
checks that the new value is greater than zero and less than or equal to the
maximum proposal count. If users have proposals in flight, and the max user live
proposals variable is updated to be less than its current value, the system
invariant `live proposals <= maxUserLiveProposals` can be temporarily violated.

Quorum can be updated to zero, and if it is, then a proposal with a single for
vote can pass.

Setting too high of a quorum also means that a proposal is unlikely to ever be
able to pass. This is because the system will not be able to reach quorum, and
all proposals will go to the `Defeated` state.

Gas limit can be updated through a governance proposal, and if an external chain
has their opcodes reprice higher, and the governance contract does not update
its gas limit, then the system can be broken. This is because the system will
not be able to process any transactions on the external chain, and the system
will be unable to process any governance proposals. To mitigate this, the
governor would use the break glass guardian to recover system ownership.

## Timestamp Difference Between Chains

Because this governance system straddles two chains, it is important that the
timestamps on both chains are within one minute of each other to prevent issues
around double voting. If an external chain has timestamps more than one minute
behind Moonbeam, then a user could propose a change on Moonbeam, and then bridge
their tokens to the external chain. This would mean once voting opened up, it
would look like this user has double the voting power than they should have.
This is because the system would register their votes on both Moonbeam and the
external chain as valid.

Consider the following scenario, on Moonbeam, timestamp is 100. On external
chain, the time is 2. A user has 1,000,000 votes on Moonbeam. They then take
those tokens, a proposal is created on Moonbeam at time 2. Then, once the
proposal is created, the user takes their tokens and bridges them to external
chain, they arrive at time 52 on the external chain. They then delegate to
themselves. Once voting starts, that user can now cast 1,000,000 votes on
Moonbeam, and 1,000,000 votes on the external chain. This is because the system
will see that the user has 1,000,000 votes on Moonbeam, and 1,000,000 votes on
the external chain, and will allow them to vote on both chains. The reason we
consider this to be infeasible is that Moonbeam and the external chain would
have to be more than one minute out of sync for this to occur. In the future,
this could change if the wormhole relayer supports faster relaying of messages,
which would mean that xWELL would be able to travel across chains faster and
make this issue more likely to occur.

Consider a scenario where a user has xWELL delegated to themselves on a
blockchain that is more than 1 minute further in the future than Moonbeam. They
then see the proposal get created on Moonbeam and bridge back to moonbeam. In
this scenario, by the time they got back to Moonbeam, they would have jumped
forward in time, and been unable to vote on the proposal twice.
