# Multichain Governance

The Multichain Governance aims to enable voting on all networks where Moonwell
is deployed, such as Moonbeam and Base. This system's primary goal is to execute
proposals on Moonbeam, and if they are cross-chain in nature, their payload will
be relayed to another chain for execution by the Temporal Governor.
Additionally, the new governance architecture seeks to improve governance
participation.

When the voting period ends, votes from external chains are emitted, but each
vote doesn't create a message back to Moonbeam. Instead, anyone can generate a
snapshot after the voting period has finished and before the cross-chain vote
collection period ends to emit the vote counts from an existing proposal to the
Governor contract on Moonbeam. The Governor contract will validate it and update
the vote counts.

The new period system of governance obviates the need for the queue function, as
the different periods are measured based on proposal creation timestamp.
Proposals are automatically considered queued if the voting period has ended and
it meets success criteria. Additional vote counts received between the voting
period end and proposal execution time could change the success status to
failure, which would block execution. Once the cross chain vote collection time
execution time has been reached, no more votes can be submitted and the proposal
status is final. If succeeded, it can be executed, if failed, it cannot. Votes
can only be counted before the final execution time, but not after. This means
that if 1 second before a proposal would pass, enough no votes from an external
chain are recorded, or vice versa, the proposal could become either failed or
succeeded from its previous state.
