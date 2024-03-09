# MIP-M19: Upgrade Wormhole Bridge Adapter on Moonbeam

## Overview

Currently, the Wormhole Bridge Adapter on Moonbeam gives users xWELL. Users will
then likely have to unwrap xWELL to get WELL. This is a two-step process that is
not user-friendly. This proposal aims to upgrade the Wormhole Bridge Adapter on
Moonbeam to give users WELL directly. This new logic contract works by minting
xWELL to the adapter, and then using the lockbox contract to burn these tokens
and transfer WELL to the user. This will make the process of bridging xWELL from
other chains to Moonbeam much more user-friendly.

## Security

In order to ensure no storage slot collisions, the slither tool was used to view
the storage offset changes in the new logic contract. No storage slot collisions
were found, and a single variable `lockbox` was added to the
`WormholeUnwrapperAdapter` contract, which inherits the `WormholeBridgeAdapter`.

### Wormhole Adapter Unwrapper

`slither src/xWELL/WormholeUnwrapperAdapter.sol  --print variable-order  --solc-remaps '@openzeppelin-contracts/=lib/openzeppelin-contracts/ @openzeppelin/=lib/openzeppelin-contracts/ @openzeppelin-contracts-upgradeable/=lib/openzeppelin-contracts-upgradeable/ @protocol=src/ @proposals=src/proposals/'`

```
WormholeUnwrapperAdapter:
+---------------------------------------+---------------------------------------------+------+--------+
|                  Name                 |                     Type                    | Slot | Offset |
+---------------------------------------+---------------------------------------------+------+--------+
|       Initializable._initialized      |                    uint8                    |  0   |   0    |
|      Initializable._initializing      |                     bool                    |  0   |   1    |
|        ContextUpgradeable.__gap       |                 uint256[50]                 |  1   |   0    |
|       OwnableUpgradeable._owner       |                   address                   |  51  |   0    |
|        OwnableUpgradeable.__gap       |                 uint256[49]                 |  52  |   0    |
| Ownable2StepUpgradeable._pendingOwner |                   address                   | 101  |   0    |
|     Ownable2StepUpgradeable.__gap     |                 uint256[49]                 | 102  |   0    |
|       xERC20BridgeAdapter.xERC20      |                   IXERC20                   | 151  |   0    |
|  WormholeTrustedSender.trustedSenders | mapping(uint16 => EnumerableSet.Bytes32Set) | 152  |   0    |
|     WormholeBridgeAdapter.gasLimit    |                    uint96                   | 153  |   0    |
| WormholeBridgeAdapter.wormholeRelayer |               IWormholeRelayer              | 153  |   12   |
| WormholeBridgeAdapter.processedNonces |           mapping(bytes32 => bool)          | 154  |   0    |
|  WormholeBridgeAdapter.targetAddress  |          mapping(uint16 => address)         | 155  |   0    |
|    WormholeUnwrapperAdapter.lockbox   |                   address                   | 156  |   0    |
+---------------------------------------+---------------------------------------------+------+--------+

```

### Original Wormhole Bridge Adapter

```
slither src/xWELL/WormholeBridgeAdapter.sol  --print variable-order  --solc-remaps '@openzeppelin-contracts/=lib/openzeppelin-contracts/ @openzeppelin/=lib/openzeppelin-contracts/ @openzeppelin-contracts-upgradeable/=lib/openzeppelin-contracts-upgradeable/ @protocol=src/ @proposals=src/proposals/'
```

```
WormholeBridgeAdapter:
+---------------------------------------+---------------------------------------------+------+--------+
|                  Name                 |                     Type                    | Slot | Offset |
+---------------------------------------+---------------------------------------------+------+--------+
|       Initializable._initialized      |                    uint8                    |  0   |   0    |
|      Initializable._initializing      |                     bool                    |  0   |   1    |
|        ContextUpgradeable.__gap       |                 uint256[50]                 |  1   |   0    |
|       OwnableUpgradeable._owner       |                   address                   |  51  |   0    |
|        OwnableUpgradeable.__gap       |                 uint256[49]                 |  52  |   0    |
| Ownable2StepUpgradeable._pendingOwner |                   address                   | 101  |   0    |
|     Ownable2StepUpgradeable.__gap     |                 uint256[49]                 | 102  |   0    |
|       xERC20BridgeAdapter.xERC20      |                   IXERC20                   | 151  |   0    |
|  WormholeTrustedSender.trustedSenders | mapping(uint16 => EnumerableSet.Bytes32Set) | 152  |   0    |
|     WormholeBridgeAdapter.gasLimit    |                    uint96                   | 153  |   0    |
| WormholeBridgeAdapter.wormholeRelayer |               IWormholeRelayer              | 153  |   12   |
| WormholeBridgeAdapter.processedNonces |           mapping(bytes32 => bool)          | 154  |   0    |
|  WormholeBridgeAdapter.targetAddress  |          mapping(uint16 => address)         | 155  |   0    |
+---------------------------------------+---------------------------------------------+------+--------+

```

## Gas Costs

In order to ensure that the gas costs of the new logic contract are not
significantly higher than the old logic contract, integration and unit tests
were run to ensure the 300k gas limit was not breached, which would require
changes on the base chain to the amount of gas needed.

On an unwrap transaction, the gas cost `167148` to mint new tokens on moonbeam
on a chainforked integration test, so the gas costs are within the 300k limit.
