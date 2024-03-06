# MIP-M18-C: Multichain Governor Migration - initialize Multichain Governor Contract

## Overview

Moonwell is shifting to a multichain model. This is the third of five
deployment scripts that are needed to migrate the protocol to the new governor system
contracts. This scrip will initialize the MultichainGovernor contract on
Moonbeam.

## Specification

- Build approved break glass calldatas
- Build initialize data struct
- Build trusted senders struct with base vote collection as the only trusted
  sender
- Call MultichainGovernor initialize with the above parameters

### Motivation

Once we have deployed the MultichainGovernor contract to Moonbeam and the Vote
Collection contract, staked well and reserve contracts to Base, it's necessary
to initialize the MultichainGovernor contract with the correct parameters. This
includes setting the break-glass approved calldatas, the trusted senders and the
MultichainGovernor InitializeData parameters which includes: well, xwell,
stkwell, vesting well addresses, proposal threshold, voting period, 
cross chain vote collection period, quorum, max user live proposals, pause
duration, pause guardian, break glass guardian and the wormhole relayer.
