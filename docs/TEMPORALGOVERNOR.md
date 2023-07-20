# TemporalGovernor

## Overview
The `TemporalGovernor` smart contract is designed to govern the Base deployment of Moonwell by leveraging the Wormhole bridge as the source of truth. The contract receives actions from the Moonbeam chain through the Wormhole bridge and executes them on the Base chain. It ensures that the execution of actions is performed securely and in a timely manner.

### Assumptions
There are several assumptions made in this contract:

1. The Wormhole bridge is secure and will not send malicious messages or be deactivated.
2. Moonbeam is secure.
3. Governance on Moonbeam cannot be compromised.

If any of these assumptions are untrue, it can impact the functionality of the contract. For example:
- If the Wormhole bridge is deactivated, the contract will be unable to upgrade the Base instance.
- If the Wormhole bridge sends malicious messages, the contract will be paused, and a new governor will need to be assigned to regain control.
- If Moonbeam is not secure, the contract will be paused until the security issue is resolved.
- If Moonbeam governance is compromised, the contract will be paused until governance control is restored.

## High-Level Architecture

The `TemporalGovernor` contract is implemented in Solidity and follows the ERC-20 standard. It utilizes several external libraries and contracts for various functionalities.

### External Libraries and Contracts Used
- `EnumerableSet` from the OpenZeppelin library is used for managing sets of trusted senders.
- `SafeCast` from the OpenZeppelin library is used for safely casting between different integer types.
- `Pausable` from the OpenZeppelin library is used to implement the pausing functionality.
- `Ownable` from the OpenZeppelin library is used to provide ownership and access control.

### Contract Structure
The contract is divided into the following sections:

1. **Immutable Variables:** These are variables that cannot be changed once the contract is deployed. They include references to the Wormhole bridge and the proposal delay duration.
2. **Storage Variables:** These are variables that store the contract state and are stored in a single storage slot. They include the last pause time and a flag to indicate whether the guardian can pause the contract.
3. **Mappings:** These mappings store the trusted senders and record processed messages to prevent replaying.
4. **Constructor:** The contract constructor initializes the contract by setting the immutable variables and populating the trusted senders mapping.
5. **View Functions:** These functions provide read-only access to the contract state, such as checking if an address is a trusted sender or retrieving the list of trusted senders for a chain.
6. **Governor/Guardian Only Functions:** These functions can only be called by the governor or guardian of the contract. They include revoking the guardian's ability, granting/rejecting guardian pause, and executing proposals.
7. **Permissionless APIs:** These functions can be called by anyone and do not require special permissions. They include queuing proposals, executing proposals, and permissionless unpause.
8. **Helper Functions:** These are internal functions used for queueing and executing proposals, as well as sanity checks for payload parameters.

## Permissioning System

The `TemporalGovernor` contract utilizes a permissioning system to control access and ensure the security of the governance process. The key components of the permissioning system are:

1. **Trusted Senders:** Each chain has a list of trusted senders. Only messages from these trusted senders are accepted and processed by the contract. The contract owner can update the list of trusted senders through governance proposals.
2. **Governor:** The governor has the authority to control the contract, execute proposals, and manage the trusted senders. Initially, the contract owner acts as the governor. However, the governance process can revoke the guardian's ability, preventing them from pausing the contract or fast-tracking proposals.
3. **Guardian Pause:** The guardian has the ability to pause the contract temporarily. When the guardian pauses the contract, all proposal executions are halted. The contract can only be unpaused by a governance proposal after a specified time delay.
4. **Permissionless Unpause:** After a certain time period has passed since the contract was paused, anyone can trigger a permissionless unpause. This allows the contract to be unpaused without requiring governance intervention.

## Contract Usage

The `TemporalGovernor` contract provides several functions to interact with its functionalities. Here are the main functions categorized by access level:

### View Only APIs
- `isTrustedSender(uint16 chainId, bytes32 addr)`: Checks if the given address is a trusted sender for the specified chain ID.
- `allTrustedSenders(uint16 chainId)`: Retrieves the list of trusted senders for the specified chain ID.

### Governor/Guardian Only APIs
- `revokeGuardian()`: Revokes the guardian's ability to pause the contract and transfers ownership to address(0).
- `grantGuardiansPause()`: Grants the guardians the pause ability and resets the last pause time.
- `setTrustedSenders(TrustedSender[] calldata _trustedSenders)`: Adds the specified addresses as trusted senders for their respective chain IDs.
- `unSetTrustedSenders(TrustedSender[] calldata _trustedSenders)`: Removes the specified addresses from the trusted senders list.

### Permissionless APIs
- `queueProposal(bytes memory VAA)`: Queues a proposal by adding it to the list of pending proposals.
- `executeProposal(bytes memory VAA)`: Executes a proposal that has been queued and passed the time delay.
- `permissionlessUnpause()`: Unpauses the contract permissionlessly after the specified time delay.
- `fastTrackProposalExecution(bytes memory VAA)`: Allows the guardian to fast-track the execution of a proposal during emergencies.
- `togglePause()`: Toggles the pause status of the contract. Can only be called by the contract owner (governor).

### Helper Functions
- `addressToBytes(address addr)`: Converts an Ethereum address to a bytes32 representation.
- `_sanityCheckPayload()`: Performs an arity check for payload parameters.

## Deployment Information
The `TemporalGovernor` contract requires the following parameters during deployment:
- `wormholeCore`: Address of the Wormhole bridge contract.
- `_proposalDelay`: Amount of time (in seconds) that a proposal must wait before being processed.
- `_permissionlessUnpauseTime`: Amount of time (in seconds) until the contract can be unpaused permissionlessly.
- `_trustedSenders`: Array of `TrustedSender` structures containing the chain ID and addresses of trusted senders.

## Security Considerations
The `TemporalGovernor` contract should be used with caution and the following security considerations should be taken into account:

1. Ensure that the Wormhole bridge contract is secure and cannot be deactivated or compromised.
2. Verify the security of the Moonbeam chain to ensure that it cannot be compromised.
3. Safeguard the private keys associated with the trusted senders to prevent unauthorized access.
4. Use the contract's pause functionality judiciously and only during emergencies or when necessary.
5. Regularly review and update the list of trusted senders to maintain the integrity of the governance process.
6. Ensure that the ownership of the contract is transferred to a reliable and trusted governor to prevent unauthorized access and control.
7. Never revoke all of the trusted senders unless governance is being deprecated and the markets are shut down and all users have left the protocol, or ownership of the Moonwell instance has been handed to another governance instance.
