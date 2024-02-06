# MIP-M18: Multichain Governor Migration Part 2

## Overview

Moonwell is shifting to a multichain model. This proposal is the second of two proposals that migrates the protocol to the new governor system contracts. This proposal will see the new Multichain Governor contract accept governance powers, transferring admin and owner from the current governor to the new governor. This proposal will also remove the timelock on Moonbeam from the set of trusted senders on the Temporal Governor contract on Base.

## Specification

- Accept pending admin of all mToken contracts
- Accept pending admin of the Comptroller
- Accept new owner of the Wormhole Bridge Adapter in the xWELL Wormhole Bridge Adapter contract on both Base and Moonbeam
- Remove old governor as a trusted sender in Temporal Governor

### Motivation
In order to allow WELL token holders on all chains to participate in governance, the xWELL token has been deployed to Base and Moonbeam. This means, that as an xWELL holder on Base, you can vote on proposals on Moonbeam and vice versa. However, the current governor contract is only deployed to Moonbeam and only supports WELL, stkWELL and vesting WELL for participation in governance.
