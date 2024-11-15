# MIP-B36: Enabling Public Allocator Functionality for the Moonwell Flagship EURC Vault

## Summary:

This proposal requests approval to enable the
[Public Allocator](https://docs.morpho.org/public-allocator/concepts/) function
for the
[Moonwell Flagship EURC Vault](https://moonwell.fi/vaults/deposit/base/mweurc).
This functionality will authorize a designated Public Allocator to manage
liquidity within the EURC vault, improving access to liquidity for borrowers by
reallocating funds within the vault as necessary. The Public Allocator's
management will facilitate efficient liquidity distribution, enabling borrowers
to access needed liquidity quickly and enhancing the overall user experience of
the Moonwell Flagship EURC Vault.

## Background:

The **Public Allocator** is an audited smart contract that optimizes liquidity
across vaults by reallocating assets when borrowing needs arise. It's designed
to reduce liquidity fragmentation across markets and make it easier for
borrowers to access the liquidity they need.

The Public Allocator's role is to:

1. **Rebalance Liquidity**: Allow borrowers to pull liquidity from multiple
   markets.
2. **Reduce Fragmentation**: Improve liquidity distribution across markets,
   ensuring that lenders' capital is utilized optimally without unnecessary
   fragmentation.
3. **Enable On-demand Liquidity**: By allowing the Public Allocator to
   reallocate liquidity in real-time, borrowers experience greater access to
   funds without needing manual interventions.

## Rationale:

Enabling the Public Allocator for the Moonwell Flagship EURC Vault will bring
several benefits:

- **Increased Borrower Accessibility**: With the Public Allocator, EURC
  borrowers can access a higher amount of liquidity than previously possible,
  improving their experience.
- **Efficient Liquidity Management**: By minimizing idle funds and ensuring
  liquidity is readily available across markets, the Public Allocator can
  optimize the utilization of assets within the EURC Vault.
- **Risk Management**: Flow caps on the Public Allocator ensure that liquidity
  can be redistributed within safe bounds, preserving the Vault's health and
  stability.

## Proposed Action:

To enable the Public Allocator, this proposal would execute the `setIsAllocator`
function on the EURC vault contract, providing authorization to the Public
Allocator address. The specific details are as follows:

- **Vault Address**: `0xf24608E0CCb972b0b0f4A6446a0BBf58c701a026`
- **Function Call**: `setIsAllocator`
- **Parameters**:
  - **Allocator Address**: `0xA090dD1a701408Df1d4d0B85b716c87565f90467`
  - **Enabled**: `true`

## Voting Options:

- **For**: Approve enabling the Public Allocator for the EURC vault, authorizing
  the allocator address `0xA090dD1a701408Df1d4d0B85b716c87565f90467` to manage
  liquidity within the vault.
- **Against**: Reject enabling the Public Allocator for the EURC vault, leaving
  liquidity management as is without the Public Allocator functionality.
- **Abstain**: Choose not to vote either for or against the proposal.
