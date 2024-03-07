# MIP-M18: Multichain Governor Migration - Transfer powers to new governor

## Overview

Moonwell is shifting to a multichain model. This proposal is the first of two
proposals that are needed to migrate the protocol to the new governor system
contracts. This proposal will deploy the new governor contracts to the Moonwell
mainnet and transfer the governance powers from the current governor to the new
governor. In cases where a full migration is not possible in a single proposal,
the pending administrator or owner will be set to the new governor contract so
that the migration can be completed in a subsequent proposal.

## Specification

- Set pending admin of all mToken contracts
- Set pending admin of the Comptroller
- Set new admin of the chainlink price oracle
- Set new owner of the Wormhole Bridge Adapter in the xWELL contract on both
  Base and Moonbeam
- Add the new governor as a trusted sender in Temporal Governor

### Motivation

Once we have deployed and initialized the new contracts, it's necessary to
transfer the governance powers from the current governor to the new governor.
This includes setting the pending admin of all mToken contracts, the
Comptroller, the chainlink price oracle admin, the Wormhole Bridge Adapter in
the xWELL contract on both Base and Moonbeam and adding the new governor as a
trusted sender in Temporal Governor. This will allow the new governor to control
the protocol and the wormhole bridge adapter to relay messages from the new
Moonbeam governor to the Base governor and vice versa.
