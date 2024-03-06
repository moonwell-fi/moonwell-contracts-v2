# MIP-M18-B: Multichain Governor Migration - Deploy Vote Collection to Base

## Overview

Moonwell is shifting to a multichain governance model. This is the second of five
deployment scripts that are needed to migrate the protocol to the new governor system
contracts. This script will deploy the new vote collection, ecosystem reserve, and staked well contracts. The new staked well contract has checkpoints based on timestamps instead of block numbers.

## Specification

- Deploy Ecosystem Reserve proxy, implementation and controller to Base
- Deploy staked well proxy and implementation based on timestamp to Base
- Deploy Vote collection implementation and proxy to Base

### Motivation

Vote collection is a contract on Base to place votes to be relayed back to
Moonbeam for counting in governance. This contract will sum users' votes from
two sources, xWELL and stkWELL, which is also deployed to Base on this proposal.
When a new proposal is created on Moonbeam, the Moonbeam governor contract will
broadcast a message that will be sent to the vote collection contract to enable
xWELL and stkWELL holders to cast their vote on the proposal. All users are
allowed to permissionlessly call into the vote collection contract and generate
a snapshot of for, against and abstain votes that can be relayed back to the
Moonbeam Governor Contract once the voting period has finished.
