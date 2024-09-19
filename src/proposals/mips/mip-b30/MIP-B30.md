# MIP-B30: Accept Ownership of EURC Flagship Vault and Update Performance Fees

**Author(s):** Block Analitica and B.Protocol **Related Discussions:**
[Moonwell MetaMorpho Vaults - Next Gen DeFi Lending](https://forum.moonwell.fi/t/introducing-moonwell-metamorpho-vaults-next-gen-defi-lending/960/16)  
**Submission Date:** September 10, 2024

## Proposal Summary

After the established collaboration between the Moonwell DAO, Morpho DAO, Block
Analitica, and B.Protocol to
[deploy, manage, and incentivize Moonwell Flagship ETH and USDC Morpho Vaults](https://moonwell.fi/governance/proposal/moonbeam?id=100),
this proposal seeks to expand vault listings by creating a new Flagship Vault on
Base that would accept
[EURC](https://basescan.org/address/0x60a3e35cc302bfa44cb288bc5a4f316fdb1adb42).
With this initiative, we aim to attract new capital and activity to the Moonwell
ecosystem, targeting EUR-based stablecoin users seeking risk-adjusted yield. The
new EURC vault is proposed with the same role assignments as the ones present
for existing USDC and ETH Flagship vaults. A 15% performance fee will be
implemented, with the Moonwell DAO's share being directed to Moonwell's EURC
Core Market protocol reserves.

This MIP proposes:

1. Accepting ownership of a new EURC Flagship Vault, expanding Moonwell's Morpho
   vault offerings on Base.
2. Updating performance fees for existing ETH and USDC Flagship Vaults from 10%
   to 15%.

## Background and Rationale

Building on the successful collaboration between the Moonwell DAO, Block
Analitica, B.Protocol, and Morpho DAO, this proposal seeks to attract new
capital and EUR-based stablecoin users seeking risk-adjusted yield. Our
[existing vaults](https://moonwell.fi/vaults) have already attracted ~$38m TVL,
representing over 55% of total supply on Morpho (Base) at the time of writing.
The addition of an EURC Flagship Vault creates yield opportunities for EUR-based
stablecoin users, potentially attracting substantial new capital and users to
the Moonwell ecosystem.

## Vault Configuration and Roles

The EURC Flagship Vault will be configured as follows:

- **Owner:** Moonwell DAO (via the Moonwell Temporal Governor contract)
- **Curator:** Block Analitica & B.Protocol
- **Allocator:** Public allocator contract and Risk Manager Multisig
- **Guardian:** Moonwell Security Council
- **Timelock period:** 4 days
- **Vault name:** Moonwell Flagship EURC
- **Symbol:** mwEURC

## Performance Fee and Incentives

This proposal seeks to implement a **15% performance fee** for the new EURC
Flagship Vault, to be split between Block Analitica/B.Protocol and the Moonwell
DAO. The Moonwell DAO's portion will be added to Moonwell's EURC Core Market
protocol reserves.

This MIP will also adjust performance fees for existing ETH and USDC Flagship
Vaults from 10% to 15%.

### Impact of Performance Fee Updates

The proposed increase in performance fees is expected to have a minimal impact
on user rates:

- USDC vault: Approximately 0.06% drop in current rates
- ETH vault: Approximately 0.04% drop in current rates

These adjustments align the fee structure across all Moonwell Flagship Vaults
and are expected to enhance protocol revenue without significantly affecting
user yields.

### Liquidity Incentives

While an additional WELL token grant is not being proposed for the EURC Vault,
the Morpho DAO will be able allocate a portion of the existing 50m WELL grant
for the USDC and ETH Flagship Vaults to incentivize and support the new EURC
Flagship Vault.

## Implementation

If this proposal passes, the following onchain actions will be executed:

1. Moonwell DAO will accept ownership of the Moonwell Flagship EURC Vault.
2. Performance fees for the ETH and USDC vaults will be updated to 15%.

## Voting Options

- **For:** Accept ownership of Moonwell Flagship EURC Morpho vault and proposed
  markets, and update performance fees as described.
- **Against:** Reject ownership of Moonwell Flagship EURC Morpho vault and
  proposed markets, and maintain current performance fee structure.
- **Abstain**

## Conclusion

The addition of an EURC Flagship Vault represents a strategic expansion of
Moonwell's offerings on Base. By leveraging Morpho infrastructure and the risk
management expertise of Block Analitica and B Protocol, we aim to replicate the
success of our existing vaults and tap into the growing demand for
euro-denominated DeFi opportunities.

Updating the performance fees across all Flagship Vaults will also harmonize our
fee structure and potentially increase protocol revenue, with minimal impact on
user yields.

Approving this proposal will diversify vault offerings, attract new users, and
reinforce our Moonwell's position as a leading DeFi app on Base.
