# MIP-M18-A: Multichain Governor Migration - Deploy new governor to Moonbeam

## Overview

Moonwell is shifting to a multichain model. This proposal is the first of five
proposals that are needed to migrate the protocol to the new governor system
contracts. This proposal will deploy the new governor contract to the Moonwell
mainnet.

## Specification

- Deploy proxy admin to Moonbeam
- Deploy MultichainGovernor implementation and proxy

### Motivation

In order to allow WELL token holders on all chains to participate in governance,
the xWELL token has been deployed to Base and Moonbeam. This means, that as an
xWELL holder on Base, you can vote on proposals on Moonbeam and vice versa.
However, the current governor contract is only deployed to Moonbeam and only
supports WELL, stkWELL and vesting WELL for participation in governance.
Thefore, a new governance system is needed to support the new multichain model.

The Moonbeam governor contract will be the source of truth for all governance
actions in Moonwell. When a new proposal is created, it will broadcast a message
that will be sent to destination chains voting contracts to enable WELL and
stkWELL holders to cast their vote on proposals that are going to go live on
Moonbeam. The Moonbeam governor will accept WELL, stkWELL and Vesting Well as
valid voting tokens.
