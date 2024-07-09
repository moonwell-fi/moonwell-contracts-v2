# MIP-M21: Upgrade Wormhole Bridge Adapter on Moonbeam

## Overview

In preparation for the upcoming upgrade of the WELL token to the [xERC20 standard](https://www.xerc20.com/), which will
enable the token to be natively used on the Base network for voting and staking, the Wormhole Bridge Adapter on Moonbeam
needs to be upgraded. While the upgraded WELL token is not yet in use, it is governed by the
[Moonwell governor](https://moonscan.io/address/0xfc4DFB17101A12C5CEc5eeDd8E92B5b16557666d), so this upgrade must be
performed through governance.

This upgraded Wormhole Bridge Adapter will support a more user-friendly experience by automatically unwrapping the
xERC20 version of WELL back to the
[original Moonbeam native WELL token](https://moonscan.io/token/0x511ab53f793683763e5a8829738301368a2411e3) on transfer,
which will reduce the number of steps required to transfer tokens between Moonbeam and Base.

## Security

This change has been audited by Halborn Security as part of the xERC20 upgrade, and no security issues were found. The
audit report can be found
[here](https://github.com/HalbornSecurity/PublicReports/blob/master/Solidity%20Smart%20Contract%20Audits/Moonwell_Finance_XWell_Token_Rate-Limiting_Smart_Contract_Security_Assessment_Report_Halborn_Final.pdf).

In order to ensure no storage slot collisions, the slither tool was used to view the storage offset changes in the new
logic contract. No storage slot collisions were found, and a single variable `lockbox` was added to the
`WormholeUnwrapperAdapter` contract, which inherits the `WormholeBridgeAdapter`.

### Wormhole Adapter Unwrapper

`slither src/xWELL/WormholeUnwrapperAdapter.sol  --print variable-order  --solc-remaps '@openzeppelin-contracts/=lib/openzeppelin-contracts/OpenZeppelin Defender/=lib/openzeppelin-contracts/ @openzeppelin-contracts-upgradeable/=lib/openzeppelin-contracts-upgradeable/ @protocol=src/ @proposals=src/proposals/'`

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
slither src/xWELL/WormholeBridgeAdapter.sol  --print variable-order  --solc-remaps '@openzeppelin-contracts/=lib/openzeppelin-contracts/ @OpenZeppelin Defender/=lib/openzeppelin-contracts/ @openzeppelin-contracts-upgradeable/=lib/openzeppelin-contracts-upgradeable/ @protocol=src/ @proposals=src/proposals/'
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

In order to ensure that the gas costs of the new logic contract are not significantly higher than the old logic
contract, integration and unit tests were run to ensure the 300k gas limit was not breached, which would require changes
on the base chain to the amount of gas needed.

On an unwrap transaction, the gas cost `167148` to mint new tokens on moonbeam on a chainforked integration test, so the
gas costs are within the 300k limit.
