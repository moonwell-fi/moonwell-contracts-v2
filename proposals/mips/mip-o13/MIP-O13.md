# MIP-O13: Accept Ownership of Flagship Moonwell USDC Vault on Optimism

**Author(s):** Block Analitica and B.Protocol **Related Discussions:**
[Moonwell MetaMorpho Vaults - Next Gen DeFi Lending](https://forum.moonwell.fi/t/introducing-moonwell-metamorpho-vaults-next-gen-defi-lending/960/16)  
**Submission Date:** March 3, 2025

## Proposal Summary

After the established collaboration between the Moonwell DAO, Morpho DAO, Block
Analitica, and B.Protocol to
[deploy, manage, and incentivize Moonwell Flagship ETH and USDC Morpho Vaults](https://moonwell.fi/governance/proposal/moonbeam?id=100),
this proposal seeks to expand vault listings by accepting ownership of a new
Flagship USDC Vault on Optimism. With this initiative, we aim to attract new
capital and activity to the Moonwell ecosystem, targeting USDC users seeking
risk-adjusted yield on Optimism. The USDC vault is proposed with the same role
assignments as the ones present for existing Flagship vaults. A 15% performance
fee will be implemented, with the Moonwell DAO's share being directed to
Moonwell's USDC Core Market protocol reserves.

This MIP proposes:

1. Accepting ownership of the Flagship Moonwell USDC Vault, expanding Moonwell's
   Morpho vault offerings on Optimism.

## Background and Rationale

Building on the successful collaboration between the Moonwell DAO, Block
Analitica, B.Protocol, and Morpho DAO, this proposal seeks to attract new
capital and USDC users seeking risk-adjusted yield on Optimism. Our
[existing vaults](https://moonwell.fi/vaults) have already attracted significant
TVL, and the addition of a USDC Flagship Vault on Optimism creates yield
opportunities for USDC users, potentially attracting substantial new capital and
users to the Moonwell ecosystem on Optimism.

## Contract Addresses

- **USDC Token:**
  [0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85](https://optimistic.etherscan.io/address/0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85)
- **USDC Flagship Vault:**
  [0x3520e1a10038131a3c00bf2158835a75e929642d](https://optimistic.etherscan.io/address/0x3520e1a10038131a3c00bf2158835a75e929642d)
- **USDC Flagship Vault Fee Splitter:**
  [0x50d3E1BD46235ce1cCf133a74e10cfdc58d49E90](https://optimistic.etherscan.io/address/0x50d3E1BD46235ce1cCf133a74e10cfdc58d49E90)

## Vault Configuration and Roles

The USDC Flagship Vault will be configured as follows:

- **Owner:** Moonwell DAO (via the Moonwell Temporal Governor contract)
- **Curator:** Block Analitica & B.Protocol
- **Allocator:** Public allocator contract and Risk Manager Multisig
- **Guardian:** Moonwell Security Council
- **Timelock period:** 4 days
- **Vault name:** Moonwell Flagship USDC Vault
- **Symbol:** mwUSDC

## Performance Fee and Incentives

This proposal implements a **15% performance fee** for the USDC Flagship Vault,
to be split between Block Analitica/B.Protocol and the Moonwell DAO. The
Moonwell DAO's portion will be added to Moonwell's USDC Core Market protocol
reserves on Optimism.

## Implementation

If this proposal passes, the following onchain actions will be executed:

1. Moonwell DAO will accept ownership of the Moonwell Flagship USDC Vault on
   Optimism.

## Voting Options

- **For:** Accept ownership of Moonwell Flagship USDC Morpho vault on Optimism.
- **Against:** Reject ownership of Moonwell Flagship USDC Morpho vault on
  Optimism.
- **Abstain**

## Conclusion

The addition of a USDC Flagship Vault represents a strategic expansion of
Moonwell's offerings on Optimism. By leveraging Morpho infrastructure and the
risk management expertise of Block Analitica and B Protocol, we aim to replicate
the success of our existing vaults and tap into the growing demand for yield
opportunities on Optimism.

Approving this proposal will expand vault offerings, attract new users, and
reinforce Moonwell's position as a leading DeFi app on Optimism.
