# Overview

The xWELL token is an xERC20 compatible token that is meant to be used as a cross chain fungible token. It relies on trusted bridge contracts that are given a rate limit in the MintLimits class. Each bridge has a different rate limit to prevent infinite mints when a single bridge is compromised. A lockbox contract is used on the source chain to allow migration of existing WELL holders over to the new WELL token.

## Frontend Integration

In order to allow token holders to seamlessly use the bridge, the frontend will need to understand the following flows for end users when moving between chains. To go from chain A to chain B, a user must first approve the wormhole or relevant bridge adapter contract the ability to spend their xWELL. Once approved, the user can then call the bridge adapter's `bridge(uint256 dstChainId,uint256 amount,address to)` function. The destination chain id should be the wormhole chainId of the destination chain. The amount should be the amount of xWELL the user wants to bridge. The to address should be the address of the receiving user on the destination chain. The bridge adapter will then transfer the xWELL from the user to the bridge contract, and then the bridge contract will mint the same amount of xWELL on the destination chain. The user will then be able to use the xWELL on the destination chain.

To find out the required amount of gas to be spent to ensure a transaction is successful, the frontend can call the `bridgeCost(uint16 dstChainId)` function on the bridge adapter. This function takes only the destination wormhole chain id the parameter, and returns the maximum amount of gas that should be spent to ensure the transaction is successful. The frontend can then use this value to set the amount native asset to pay for the transaction. This amount of native tokens should be sent in the call to bridge.

### Router Contract

In order to use the router to simplify users migrating from WELL to xWELL, the frontend will need to talk to the router contract. Users will approve the router to spend their WELL and then call `bridgeToBase(address to, uint256 amount)` if to is different from sender, or `bridgeToBase(uint256 amount)` if to is the same as sender. The router will then transfer the WELL from the user to the lockbox contract, and then the lockbox contract will mint the same amount of xWELL to the router, which will then migrate those tokens to xWELL the base chain through the WormholeAdapter. The user must pass the correct amount of GLMR to the router to cover the gas costs of the transaction. The amount can be found by calling the `bridgeCost()` function on the router contract which returns a uint256.

### Events

When a user uses the WormholeBridgeAdapter contract to move tokens from one chain to another, the following events will be emitted

from the xWELL token:

On Mint:
```Transfer(address(0), to, amount);```
```BufferUsed(amount, newBufferStored);```

On Burn:
```Transfer(from, address(0), amount);```
```BufferReplenished(amount, newBufferStored);```

from the WormholeBridgeAdapter:

on Mint:
```BridgedIn(chainId, user, amount)```
```BridgedIn(uint256 indexed srcChainId, address indexed tokenReceiver, uint256 amount);```

on Burn:
```TokensSent(targetChainId, to, amount);```
```BridgedOut(uint256 indexed dstChainId, address indexed bridgeUser, address indexed tokenReceiver, uint256 amount);```

## xWELL Token xERC20 Differences

xERC20 enforces a global rate limit per second on each bridge, meaning all bridge's buffers refill at the same speed once depleted. The xWELL implementation allows each bridge to have a different rate limit, allowing for more flexibility in the bridge setup. The xWELL implementation also allows for a bridge to be disabled, preventing any further minting from that bridge. This is useful if a bridge is compromised and needs to be disabled.

### Guardians

The xWELL token has a guardian system that allows for the token to be paused, which disables all bridging functionality. The guardian address is meant to be a multisig contract that requires a quorum of guardians to approve a transaction before it can be executed. The guardian system is meant to be used as a failsafe in case of a bridge compromise or other emergency. Once the guardian pauses the contract, then the pause timer starts. The pause duration is specified in the initializer of the xWELL token, and once the pause duration has passed, the contract automatically unpauses itself. Only the mint and burn functions of the token are disabled while the contract is paused.

The owner can change the pause duration, even while the contract is paused. This allows the owner to extend the pause duration if needed during an emergency situation.

The owner can only grant a new pause guardian if the contract is not paused, and the owner can unpause the contract, which enables them to assign a new pause guardian.

### Ownership

The contract is owned by the Temporal Governor on Base, and by the Moonwell Artemis Timelock on Moonwell. The owner can change the guardian address, and add, remove and change the rate limits on the bridges. The owner can also change the pause duration, even while the contract is paused.


### Constants

The xWELL token has a few constants that are used to configure the contract. These constants are:
- max rate limit per second: The maximum rate limit that a bridge can have is 10k tokens per second. This is used to prevent a bridge from having an unlimited rate limit.
- max pause duration: The maximum pause duration is 30 days. This is used to prevent the contract from being paused indefinitely.
