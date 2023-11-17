# Overview

The xWELL token is an xERC20 compatible token that is meant to be used as a cross chain fungible token. It relies on trusted bridge contracts that are given a rate limit in the MintLimits class. Each bridge has a different rate limit to prevent infinite mints when a single bridge is compromised. A lockbox contract is used on the source chain to allow migration of existing WELL holders over to the new WELL token.

## xWELL Token xERC20 Differences

xERC20 enforces a global rate limit per second on each bridge, meaning all bridge's buffers refill at the same speed once depleted. The xWELL implementation allows each bridge to have a different rate limit, allowing for more flexibility in the bridge setup. The xWELL implementation also allows for a bridge to be disabled, preventing any further minting from that bridge. This is useful if a bridge is compromised and needs to be disabled.

### Guardians

The xWELL token has a guardian system that allows for the token to be paused, which disables all bridging functionality. The guardian address is meant to be a multisig contract that requires a quorum of guardians to approve a transaction before it can be executed. The guardian system is meant to be used as a failsafe in case of a bridge compromise or other emergency. Once the guardian pauses the contract, then the pause timer starts. The pause duration is specified in the initializer of the xWELL token, and once the pause duration has passed, the contract automatically unpauses itself. Only the mint and burn functions of the token are disabled while the contract is paused.

The owner can change the pause duration, even while the contract is paused. This allows the owner to extend the pause duration if needed during an emergency situation.

### Ownership

The contract is owned by the Temporal Governor on Base, and by the Moonwell Artemis Timelock on Moonwell. The owner can change the guardian address, and add, remove and change the rate limits on the bridges. The owner can also change the pause duration, even while the contract is paused.


### Constants

The xWELL token has a few constants that are used to configure the contract. These constants are:
- max rate limit per second: The maximum rate limit that a bridge can have is 10k tokens per second. This is used to prevent a bridge from having an unlimited rate limit.
- max pause duration: The maximum pause duration is 30 days. This is used to prevent the contract from being paused indefinitely.
