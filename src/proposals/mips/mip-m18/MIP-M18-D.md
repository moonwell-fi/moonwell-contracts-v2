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
- Set Chainlink price oracle admin
- Set Wormhole Bridge Adapter pending owner
- Set xWELL pending owner
- Set trusted sender in Temporal Governor
- Set the Staked Well emission manager
- Set the Ecosystem Reserve Controller owner
- Set the the Proxy Admin owner

### Motivation

Once we have deployed and initialized the new contracts, it's necessary to
transfer the governance powers from the current governor to the new governor.
This includes setting the pending admin of all mToken contracts, the
Comptroller, the Chainlink price oracle admin, the Wormhole Bridge Adapter
pending owner, the xWELL pending owner, the trusted sender in Temporal Governor,
the Staked Well emission manager, the Ecosystem Reserve Controller owner, and
the Proxy Admin owner. This will allow the new governor to control the Moonwell
protocol and the Moonwell tokens.
