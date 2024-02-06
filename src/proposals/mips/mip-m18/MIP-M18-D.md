# MIP-M18: Multichain Governor Migration Part 1

## Overview

Moonwell is shifting to a multichain model. This proposal is the first of two proposals that are needed to migrate the protocol to the new governor system contracts. This proposal will deploy the new governor contracts to the Moonwell mainnet and transfer the governance powers from the current governor to the new governor. In cases where a full migration is not possible in a single proposal, the pending administrator or owner will be set to the new governor contract so that the migration can be completed in a subsequent proposal.

## Specification

- Set pending admin of all mToken contracts
- Set pending admin of the Comptroller
- Set new admin of the chainlink price oracle
- Set new owner of the Wormhole Bridge Adapter in the xWELL Wormhole Bridge Adapter contract on both Base and Moonbeam
- Add the new governor as a trusted sender in Temporal Governor

### Motivation
In order to allow WELL token holders on all chains to participate in governance, the xWELL token has been deployed to Base and Moonbeam. This means, that as an xWELL holder on Base, you can vote on proposals on Moonbeam and vice versa. However, the current governor contract is only deployed to Moonbeam and only supports WELL, stkWELL and vesting WELL for participation in governance.
