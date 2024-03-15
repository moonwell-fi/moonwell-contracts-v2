# MIP-M18: Multichain Governor Migration - Accept ownership on the new governor

## Overview

Moonwell is shifting to a multichain model. This proposal is the second of two
roposals that migrates the protocol to the new governor system contracts. This
proposal will see the new Multichain Governor contract accept governance powers,
transferring admin and owner from the current governor to the new governor. This
proposal will also remove the Timelock contract as a trusted senders on the
Temporal Governor contract on Base.

## Specification

- Accept pending admin of all mToken contracts
- Accept pending admin of the Comptroller
- Accept Womrhole Bridge Adapter ownership
- Accept xWELL ownership
- Remove old governor as a trusted sender in Temporal Governor

### Motivation

After starting the contracts ownership change in Proposal D, it's necessary to
finalize the ownership transfer on the new governor. This includes accepting the
pending admin of all mToken contracts, Comptroller, Wormhole Bridge Adapter,
xWELL contracts and removing the old governor as a trusted sender in Temporal
Governor. This will allow the new governor to control the Moonwell protocol and
the Moonwell tokens.
