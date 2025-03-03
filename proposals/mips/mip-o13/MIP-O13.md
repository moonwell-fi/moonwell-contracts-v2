# MIP-O13: Accept Ownership of Flagship Moonwell USDC Vault on OP Mainnet

**Author(s):** Block Analitica and B.Protocol **Related Discussions:**
[Moonwell MetaMorpho Vaults - Next Gen DeFi Lending](https://forum.moonwell.fi/t/introducing-moonwell-metamorpho-vaults-next-gen-defi-lending/960/16)
[Superchain Expansion Proposal](
https://forum.moonwell.fi/t/proposal-to-launch-moonwell-flagship-usdc-vault-on-OP
Mainnet/1540) **Submission Date:** March 3, 2025

## Proposal Summary

Following the success of Moonwell Flagship and Frontier vaults on Base, which
currently hold more than $85M in total value locked (TVL) across ETH, USDC,
EURC, and cbBTC, this proposal seeks to expand our strategic footprint by
accepting ownership of the Flagship Moonwell USDC Vault on OP Mainnet (OP
Mainnet).

With this initiative, we aim to attract USDC depositors, deepen network
liquidity for this important stablecoin, and further establish Moonwell as a
leading contributor in the Morpho and Superchain ecosystems. The USDC vault is
proposed with the same role assignments as those present for existing Flagship
vaults. A 15% performance fee will be implemented, with the Moonwell DAO's share
being directed to Moonwell's USDC Core Market protocol reserves.

This MIP proposes:

1. Accepting ownership of the Flagship Moonwell USDC Vault, expanding Moonwell's
   Morpho vault offerings on OP Mainnet.

## Background and Rationale

Last summer,
[MIP-B21](https://boardroom.io/moonwell/proposal/cHJvcG9zYWw6bW9vbndlbGw6b25jaGFpbi11cGdyYWRlOjIx)
kicked off Moonwell DAO's collaboration with Block Analitica and B.Protocol,
paving the way for the development of the Moonwell Flagship and Frontier series
of Morpho vaults. Today, these vaults stand among the largest by TVL in the Base
ecosystem, highlighting their strong adoption and significance.

Building on this successful model, we propose expanding to OP Mainnet to attract
new capital and USDC users seeking risk-adjusted yield. By being the first to
offer a fully integrated Morpho vault experience on OP Mainnet—where the Morpho
frontend is currently unavailable—we position ourselves to capture early market
share and pave the way for future expansion across Superchain-aligned networks.

This proposal aligns with the Morpho Everywhere expansion plan, which aims to
establish Morpho infrastructure across multiple Ethereum L1 and L2 networks,
including OP Mainnet. This could be the first of multiple vaults launched by
Moonwell DAO and Block Analytica/B.Protocol on Superchain-aligned networks,
supporting our broader vision of scaling Ethereum lending infrastructure across
the Superchain.

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
- **Allocator:** Block Analitica & B.Protocol
- **Guardian:** Moonwell Security Council
- **Timelock period:** 4 days
- **Vault name:** Moonwell Flagship USDC Vault
- **Symbol:** mwUSDC

## Proposed Markets

Block Analitica has proposed listing two markets for the USDC vault on OP
Mainnet:

### wstETH/USDC Market

- **Loan token:** USDC -
  [0x0b2c639c533813f4aa9d7837caf62653d097ff85](https://optimistic.etherscan.io/address/0x0b2c639c533813f4aa9d7837caf62653d097ff85)
- **Collateral token:** wstETH -
  [0x1F32b1c2345538c0c6f582fCB022739c4A194Ebb](https://optimistic.etherscan.io/address/0x1F32b1c2345538c0c6f582fCB022739c4A194Ebb)
- **Oracle:** Morpho Chainlink -
  [0x1ec408D4131686f727F3Fd6245CF85Bc5c9DAD70](https://optimistic.etherscan.io/address/0x1ec408D4131686f727F3Fd6245CF85Bc5c9DAD70)
- **IRM:** Adaptive Curve IRM -
  [0x8cD70A8F399428456b29546BC5dBe10ab6a06ef6](https://optimistic.etherscan.io/address/0x8cD70A8F399428456b29546BC5dBe10ab6a06ef6)
- **LLTV:** 86%
- **Supply Cap:** 30M USDC

### WETH/USDC Market

- **Loan token:** USDC -
  [0x0b2c639c533813f4aa9d7837caf62653d097ff85](https://optimistic.etherscan.io/address/0x0b2c639c533813f4aa9d7837caf62653d097ff85)
- **Collateral token:** WETH -
  [0x4200000000000000000000000000000000000006](https://optimistic.etherscan.io/address/0x4200000000000000000000000000000000000006)
- **Oracle:** Morpho Chainlink -
  [0x1ec408D4131686f727F3Fd6245CF85Bc5c9DAD70](https://optimistic.etherscan.io/address/0x1ec408D4131686f727F3Fd6245CF85Bc5c9DAD70)
- **IRM:** Adaptive Curve IRM -
  [0x8cD70A8F399428456b29546BC5dBe10ab6a06ef6](https://optimistic.etherscan.io/address/0x8cD70A8F399428456b29546BC5dBe10ab6a06ef6)
- **LLTV:** 86%
- **Supply Cap:** 30M USDC

These market listings were executed on February 19, 2025, at 10:50:31 AM +UTC
and 10:50:17 AM +UTC respectively.

## Performance Fee and Incentives

This proposal implements a **15% performance fee** for the USDC Flagship Vault,
to be split between Block Analitica/B.Protocol and the Moonwell DAO. The
Moonwell DAO's portion will be added to Moonwell's USDC Core Market protocol
reserves on OP Mainnet.

Note that the launch of this new vault does not imply a new WELL token grant for
liquidity incentives. However, there may be opportunities to receive OP
incentives through initiatives such as Season 7 OP Mainnet Grants Council
Grants, which focus on bolstering Superchain TVL.

## Implementation

If this proposal passes, the following onchain actions will be executed:

1. Moonwell DAO will accept ownership of the Moonwell Flagship USDC Vault on OP
   Mainnet.

## Voting Options

- **For:** Accept ownership of Moonwell Flagship USDC Morpho vault on OP
  Mainnet.
- **Against:** Reject ownership of Moonwell Flagship USDC Morpho vault on OP
  Mainnet.
- **Abstain**

## Conclusion

The addition of a USDC Flagship Vault represents a strategic expansion of
Moonwell's offerings on OP Mainnet. By leveraging Morpho infrastructure and the
risk management expertise of Block Analitica and B Protocol, we aim to replicate
the success of our existing vaults and tap into the growing demand for yield
opportunities on OP Mainnet.

By being the first to offer a Morpho-integrated lending experience on OP
Mainnet, Moonwell has the potential to capture early market share and expand its
influence across the Superchain. Approving this proposal will expand vault
offerings, attract new users, and reinforce Moonwell's position as a leading
DeFi app on the Superchain.
