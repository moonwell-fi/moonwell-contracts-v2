# TemporalGovernor Smart Contract

This document provides an overview of the `TemporalGovernor` smart contract written in Solidity.

## Features

1. **Safe Casting Operations**: The contract leverages the OpenZeppelin `SafeCast` library to perform safe casting
   operations.

2. **Pause Functionality**: The contract uses the `Pausable` contract from OpenZeppelin to add pausing mechanisms. This
   allows certain functionalities of the contract to be paused and unpaused.

3. **Owner Permissions**: The contract inherits from OpenZeppelin's `Ownable` contract which restricts certain functions
   to be executable only by the contract owner.

4. **Wormhole Bridge Reference**: The contract holds an immutable reference to the Wormhole bridge. Wormhole is a
   cross-chain communication protocol.

5. **Proposal Delay and Permissionless Unpause Time**: The contract keeps track of the time a proposal must wait before
   being processed and the time until this contract can be unpaused without permission.

6. **Trusted Senders**: The contract maintains a mapping of chain ids to trusted senders to validate incoming requests.

7. **Queued Transactions**: The contract also maintains a mapping of message hashes to `ProposalInfo` objects. This
   mechanism is in place to prevent transaction replay and enforce time limits.

## States

1. **Wormhole Bridge**: An immutable reference to the Wormhole bridge contract.

2. **Proposal Delay**: An immutable variable which keeps the amount of time a proposal must wait before it can be
   processed.

3. **Permissionless Unpause Time**: An immutable variable which defines the amount of time until the contract can be
   unpaused without any permission.

4. **Last Pause Time**: The contract maintains a timestamp of when it was last paused.

5. **Guardian Pause Allowed**: A Boolean variable indicating whether or not the guardian can pause the contract. It
   starts as true and then is set to false when the guardian pauses. It can be set to true again only by a governance
   proposal that grants the guardian the ability to pause again and sets the new guardian address.

6. **Trusted Senders**: A mapping from chain id to a trusted sender (in bytes32 format). This mapping is used to
   validate incoming requests, ensuring only trusted contracts from the right chains are allowed to send requests to
   this contract.

7. **Queued Transactions**: A mapping from message hashes to `ProposalInfo` objects. This mapping is used to ensure
   transactions aren't processed more than once, and that a timelock on all proposals are enforced. This timelock can be
   bypassed by the guardian in case of an emergency, immediately executing a proposal if the contract has already been
   paused and the caller is the pause guardian.

## Functionality

The contract provides various functionalities:

-   Managing trusted senders: The contract maintains a list of trusted senders and provides a function to update this
    list.

-   Proposal queueing and execution: Proposals can be queued and later executed.

-   Pausing and unpausing: The contract can be paused and unpaused. After a certain delay, it can be unpaused without
    any permission (permissionless unpause).

-   Guardian management: The contract allows for a guardian who can pause the contract. This ability can be granted,
    revoked, and its status can be toggled. The guardian's ability to pause is revoked when the contract is paused.

-   Emergency actions: In case of an emergency, the contract provides a fast-track mechanism for proposals to be
    executed only when the contract is paused. A proposal cannot be fast tracked when the contract is unpaused.

-   Helper functions: There are several private helper functions used internally by the contract for queueing proposals,
    executing proposals, and performing payload sanity checks.

## Security Considerations

The Temporal Governor makes trust assumptions that the governor contract(s) on external chains are not malicious. Should
the owner of the Temporal Governor turn malicious, the following are the destructive actions they can take:

-   A malicious proposal from a trusted sender can remove all trusted senders, making the contract inoperable. Without
    trusted senders, no VAA's are valid.
-   A malicious pause from the pause guardian can prevent valid governance proposals from being executed for a period of
    ten days, until the contract automatically unpauses.
-   There are no payable functions on Temporal Governor, so it cannot send Ether as part of its governance proposals
    unless a contract with Ether is self-destructed to give Ether to the Temporal Governor. If self-destruct is removed,
    there is no way to send Ether to the Temporal Governor.
-   If enough Wormhole signers become malicious, then they can create valid VAA's that have malicious payloads. Wormhole
    is assumed to be trusted and secure.

If any of these assumptions are violated, it becomes hard to reason about the state the system should be in.
