# MIP-M18: Multichain Governor Migration - Accept ownership on the new governor

## Overview

Moonwell is shifting to a multichain model. This proposal is the second of two
proposals that migrates the protocol to the new governor system contracts. This
proposal will see the new Multichain Governor contract accept governance powers,
transferring admin and owner from the current governor to the new governor. This
proposal will also remove the timelock on Moonbeam from the set of trusted
senders on the Temporal Governor contract on Base.

## Specification

- Accept pending admin of all mToken contracts
- Accept pending admin of the Comptroller
- Accept new owner of the Wormhole Bridge Adapter in the xWELL Wormhole Bridge
  Adapter contract on both Base and Moonbeam
- Remove old governor as a trusted sender in Temporal Governor

### Motivation

After asking for changing the ownership of the contracts on Proposal D, we need
to accept the ownership on the new governor. This includes accepting the pending
admin of all mToken contracts, the Comptroller, the Wormhole Bridge Adapter in
the xWELL contract on both Base and Moonbeam and removing the old governor as a
trusted sender in Temporal Governor. This will allow the new governor to control
the protocol and the wormhole bridge adapter to relay messages from the new
Moonbeam governor to the Base governor and vice versa.
