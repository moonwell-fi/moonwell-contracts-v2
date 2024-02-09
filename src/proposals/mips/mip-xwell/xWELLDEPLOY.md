# Proposal: Create the xWELL Token

## Summary

This proposal is to create the xWELL token, a token that represents the value of the Well Protocol. The xWELL token will be used to govern the Well Protocol. This is a cross chain token that will go live on both Base and Moonbeam to start. Wormhole relayers will be used in the bridge software to allow for the token to be transferred between chains permissionlessly by end users.

## Motivation

In order to enable cross chain governance for the Moonwell community, and allow representation of tokenholders on all chains to particpate in governance, a cross chain token is needed. This token will be used to govern the Well Protocol, and will be used to vote on proposals and other governance actions.

## Specification

The xWELL token will be created on both Base and Moonbeam. The token will be created with a fixed hardcap on supply of 5,000,000,000. No tokens will be minted initially, and a lockbox contract will be deployed on Moonbeam to allow users to migrate their WELL tokens to the xWELL token.

Name: xWELL Token
Symbol: xWELL
Decimals: 18
Max Supply: 5,000,000,000
Trusted Bridge: Wormhole
Rate Limit Parameters: 38m buffer cap, 219.907 well replenishes per second, 19m well replenishes per day.
Maximum bridge amount possible: 38m well.
Maximum bridge amount at launch: 19m well.

## Security

The midpoint libraries in the rate limiting library have been audited by halborn as well as formally verified to ensure the security of the protocol.

Every part of the xWELL token that could be formally verified was, with the exception of the Wormhole relayer contracts. The Wormhole relayer contracts are not formally verified, but are audited by Halborn, and have been extensively unit and integration tested.

Halborn has been engaged to audit the entire xWELL token. The audit will be completed before the token is deployed.

## Privileged Actors

### Base

- **xWELL proxy admin**: MultiRewardDistributor Proxy Admin - Responsible for upgrading the xWELL token and other contracts as needed.
- **xWELL proxy admin owner**: Temporal Governor - Responsible for changing the owner of the proxy admin and upgrading contracts as needed.
- **xWELL admin**: Temporal Governor - Responsible for setting rate limits and other parameters of the xWELL token. Can add and remove bridges as needed.
- **xWELL pause guardian**: Base Pause Guardian - Responsible for pausing the xWELL mint and burn functionality in the event of an emergency.

### Moonbeam

- **xWELL proxy admin**: stkWELL Proxy Admin - Responsible for upgrading the xWELL token and other contracts as needed.
- **xWELL proxy admin owner**: Artemis Timelock - Responsible for changing the owner of the proxy admin and upgrading contracts as needed.
- **xWELL admin**: Artemis Timelock - Responsible for setting rate limits and other parameters of the xWELL token. Can add and remove bridges as needed.
- **xWELL pause guardian**: Moonbeam Pause Guardian Multisig - Responsible for pausing the xWELL mint and burn functionality in the event of an emergency. Pausing on Moonbeam will also pause the lockbox contract as it will no longer be able to mint or burn.

## System Deployment
Because these smart contracts are immutable and permissionless. Anyone in the community can choose to deploy them, and if their version is accepted, and configured correctly, then that will become the new canonical xWELL token. Once a token has been defined as canonical by the community, no new tokens will be created, and the community will be able to use the xWELL token to govern the Well Protocol in future releases.

## Scripts

In order to deploy the protocol, a fresh EOA is needed with the same nonce on both moonbeam and base. The following scripts will be used:

**base deployment:**
```
DO_DEPLOY=true DO_VALIDATE=true forge script src/proposals/mips/mip-xwell/xwellDeployBase.sol:xwellDeployBase --fork-url base
```

Once the base system has been deployed, add all the newly deployed addresses to [Addresses.json](./../../../../utils/Addresses.json) with the base network id, and then run the following script to deploy the system on moonbeam:

**moonbeam deployment:**
```
DO_DEPLOY=true DO_VALIDATE=true forge script src/proposals/mips/mip-xwell/xwellDeployMoonbeam.sol:xwellDeployMoonbeam --fork-url moonbeam
```

Once the moonbeam system has been deployed, add all the newly deployed addresses to [Addresses.json](./../../../../utils/Addresses.json) with the moonbeam network id.

After all the addresses are added to the addresses.json file, do a manual test run going back and forth between base and moonbeam to ensure that the system is working correctly. Ensure that the rate limits are set correctly, and that the bridge and lockbox is working correctly.

Manually inspect the trusted senders and system rate limits, and ensure that they are set correctly. Once the system has been manually tested and the addresses.json file has been updated, create a PR to the main repository, ensuring all contributor guidelines have been followed.

## Invariant Tests

To run the invariant tests for xWELL, run the following command:

```
forge test --match-path test/invariant/xWELLInvariant.t.sol
```

## Integration Tests

To run the integration tests for xWELL, run the following command:

```
forge test --match-contract DeployxWellLiveSystemBaseTest --fork-url base -vvv
```

```
forge test --match-contract DeployxWellLiveSystemMoonbeamTest --fork-url moonbeam -vvv
```