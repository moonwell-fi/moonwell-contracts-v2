# MIP-M18-B: Multichain Governor Migration - initialize Multichain Governor Contract

## Overview

Moonwell is shifting to a multichain model. This proposal is the third of five
proposals that are needed to migrate the protocol to the new governor system
contracts. This proposal will initialize the MultichainGovernor contract on
Moonbeam.

## Specification

- Build approved break glass calldatas
- Build initialize data struct
- Build trusted senders struct with base vote collection as the only trusted
  sender
- Call MultichainGovernor initialize with the above parameters

### Motivation

Once we have deployed the MultichainGovernor contract to Moonbeam and the Vote
Collection contract to Base, as well the staked well and reserve contracts to
base, it's necessary to initialize the MultichainGovernor contract with the
parameters to allow it to function correctly. This includes setting the
break-glass approved calldatas, the trusted senders, which in this case is only
the vote collection address and the base chain id and pass the
MultichainGovernor.InitializeData parameters which includes: well, xwell,
stkwell, vesting well addresses, the proposal threshold, the voting period, the
cross chain vote collection period, quorum, max user live proposals, pause
duration, pause guardian, break glass guardian and the wormhole relayer.
