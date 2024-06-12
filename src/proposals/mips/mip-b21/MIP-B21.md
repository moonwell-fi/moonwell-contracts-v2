# MIP-B21 Accepting Ownership and Incentivizing Moonwell MetaMorpho Vaults

**Author(s):** Block Analitica and B.Protocol

**Related Discussions:**
[Moonwell MetaMorpho Vaults - Next Gen DeFi Lending](https://forum.moonwell.fi/t/introducing-moonwell-metamorpho-vaults-next-gen-defi-lending/960)

**Related Snapshot Proposal:**
[Temp Check Snapshot Proposal](https://snapshot.moonwell.fi/#/proposal/0x8d297b61bdc0361c3ff9d26f591b2758c7d6c821b61ee98788b51927cb613051)

**Submission Date:** June 12, 2024

## Summary

This proposal seeks to establish a collaboration between the Moonwell DAO, Block
Analitica, B.Protocol, and the Morpho DAO to deploy, manage, and incentivize
Moonwell MetaMorpho vaults. These optimized lending vaults will bring the next
generation of optimized lending to the Moonwell ecosystem and offer Moonwell
users enhanced capital efficiency, flexibility, and risk management. Through
this collaboration, we aim to attract substantial new capital and users to the
Moonwell ecosystem, setting a new standard for risk-conscious DeFi lending.
Initial vaults will support USDC and ETH, with WELL incentives distributed over
a 6-month period to incentivize TVL growth. A 10% performance fee will be
implemented, with the Moonwell DAO’s share being directed to existing USDC and
ETH protocol reserves.

## Vault Configuration

Following the community’s overwhelming support for and passage of our
[temperature check Snapshot proposal](https://snapshot.moonwell.fi/#/proposal/0x8d297b61bdc0361c3ff9d26f591b2758c7d6c821b61ee98788b51927cb613051),
we have deployed USDC and ETH MetaMorpho vaults with specific configurations for
ownership, curation, allocation, guardianship, performance fees, timelock
periods, and vault names/symbols. Through the passage of MIP-B21, ownership of
the two vaults will be assigned to the Moonwell DAO (Moonwell Temporal Governor
contract).

### Roles

- **Owner:** Moonwell DAO
- **Curator:** Block Analitica & B.Protocol
- **Allocator:** Public allocator contract and Risk Manager Multisig
- **Guardian:** Moonwell Security Council

### Performance Fee

A 10% performance fee will be implemented and split between Block
Analitica/B.Protocol and the Moonwell DAO. The Moonwell DAO's portion will be
added to the existing USDC and ETH Moonwell protocol reserves in regular
intervals, allowing the Moonwell protocol to recognize income as fees.

- **Timelock period:** 4 days
- **Vault names:** Moonwell Flagship USDC, Moonwell Flagship ETH
- **Symbols:** mwUSDC, mwETH

## Liquidity Incentives

As part of this proposal, we are requesting a grant from the Moonwell DAO of 50m
WELL tokens to be utilized as liquidity incentives. Initial WELL liquidity
incentives will be distributed to the vaults over a 6-month period through
Morpho's URD (Universal Reward Distributor) contract at the vault level,
enabling reward visibility on both Morpho and Moonwell applications. These
substantial incentives, coupled with MORPHO rewards, will be pivotal in
attracting new capital and distinguishing Moonwell MetaMorpho vaults from
competitor vaults.

### Incentive Distribution Schedule

- **1/6 (8.33m WELL)** over the first 2 months
- **2/6 (16.66m WELL)** over the following 2 months
- **3/6 (25m WELL)** over the last 2 months

The proposed initial breakdown is 50/50% between the two vaults, subject to
adjustment based on TVL fluctuations. This incentive distribution will be
operationally handled by the Morpho DAO. This
[gradual distribution method](https://forum.morpho.org/t/standard-method-for-distributing-incentives-on-morpho-blue-markets/412)
has been tried and tested by the Morpho DAO on Ethereum mainnet.

## Implementation

If this proposal passes, the following onchain actions will be executed:

1. Moonwell DAO accepts ownership of Moonwell Flagship USDC Vault
2. Moonwell DAO accepts ownership of Moonwell Flagship ETH Vault
3. A grant of 50m WELL tokens to be utilized as Morpho liquidity incentives will
   be sent to the Moonwell MetaMorpho URD for distribution through merkle roots
   according to the proposed schedule, with operational handling by the Morpho
   DAO.

## Voting

- **Yay:** Accept ownership of Moonwell Flagship USDC and ETH MetaMorpho vaults
  and allocation and distribution of WELL incentives through the Moonwell
  MetaMorpho URD contract.
- **Nay:** Reject ownership of Moonwell Flagship USDC and ETH MetaMorpho vaults
  and allocation and distribution of WELL incentives through the Moonwell
  MetaMorpho URD contract.

## Conclusion

The deployment of Moonwell MetaMorpho vaults marks a pivotal moment for the
Moonwell ecosystem. Through this collaboration, we are ready to deliver a
superior, risk-optimized lending experience from day one of Morpho's Base
launch. MIP-B21's passage will help to ensure a successful launch, with 50
million WELL tokens allocated for liquidity incentives and a performance fee
structure that increasingly benefits the Moonwell DAO as vault TVLs grow. By
voting "Yay" on this proposal, you are helping to future proof and secure the
growth of the Moonwell ecosystem on Base.
