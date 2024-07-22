# MIP-X01 - Cross-Chain WELL Activation and System Upgrade

## Proposal Overview

This governance proposal aims to activate the WELL token on the Optimism (OP
Mainnet) network and facilitate its cross-network transfer capabilities,
alongside upgrades to the Multichain Governor on Moonbeam and Vote Collection
contract on Base.

The proposal includes the following key actions:

1. **WELL Token Activation on Optimism:** Enable the WELL token to be
   transferred and used on OP Mainnet.
2. **Multichain Vote Collection Contract:** Add the Multichain Vote Collection
   contract on OP Mainnet as a trusted sender on Moonbeam. This allows the WELL
   token to participate in governance on Optimism and ensures that new proposals
   are broadcast to this network.
3. **Governor and Vote Collection Contract Upgrade:** Upgrade the Multichain
   Governor on Moonbeam and the Vote Collection contract on Base to refund
   excess native tokens when proposing or emitting votes.
4. **WELL Token Implementation Upgrade:** Upgrade the WELL token implementation
   on both Base and Moonbeam to allow the contract owner the ability to unpause
   the contracts. Following a successful governance proposal, the community can
   vote to unpause the xWELL token if it has previously been paused by the
   guardian.

## Multi-Network Proposal

This proposal, designated as MIP-X01, marks a significant milestone as the first
of its kind. Typically, MIP proposals are network-specific, indicated by a
letter representing the network where updates will be executed (e.g., 'B' for
Base, 'M' for Moonbeam, 'R' for MoonRiver). However, the 'X' in MIP-X01
signifies that this is a "multi-network" proposal, executing changes across
multiple networks.

## Testing and Security

These changes have undergone rigorous testing and auditing processes to ensure
their safety and reliability:

- **Unit and Integration Testing:** Comprehensive tests have been conducted to
  verify the functionality and performance of the proposed changes.
- **Audit by Halborn:** A thorough audit was performed by Halborn to identify
  and mitigate potential security risks.
- **Review by Solidity Labs Engineer:** An independent review was carried out by
  a Solidity Labs engineer to validate the code and its implications.
- **Formal Proofs:** Formal proofs were executed again to demonstrate the safety
  and correctness of the code changes.

## Voting Options

- **Yay:** Vote in favor of the proposal to activate the WELL token on OP
  Mainnet, upgrade the Multichain Governor and Vote Collection contracts, and
  allow for the unpausing of the xWELL token by community vote.
- **Nay:** Vote against the proposal and maintain the current state of the WELL
  token and related contracts.
