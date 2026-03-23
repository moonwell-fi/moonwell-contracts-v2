# MIP-X47: Accept Ownership of Flagship and Frontier MetaMorpho Vaults

## Summary

This proposal accepts ownership of four MetaMorpho vaults on Base, transferring
control from the Anthias Multisig to the Temporal Governor (Moonwell
governance).

## Vaults

| Vault          | Address                                    |
| -------------- | ------------------------------------------ |
| WETH Flagship  | 0x89BeDBB1C4837444Da215A377275Ff96A84D6f53 |
| USDC Flagship  | 0x48a90E85be5C56b0A669985A12ee7C449fC79965 |
| EURC Flagship  | 0x5083b1387Ec3d4Ee6467B83890D98f1AF93F7c48 |
| cbBTC Frontier | 0xdbA76Bc542bb07538e046B40F2e8a215B409F7A8 |

## Motivation

These vaults are currently owned by the Anthias Multisig
(0x08eDEbFFaE68970DCf751baa826182b3a4aCFC05). To bring them under full
governance control, ownership is being transferred to the Temporal Governor via
the two-step Ownable2Step pattern:

1. Anthias Multisig calls `transferOwnership(TEMPORAL_GOVERNOR)` on each vault
2. This governance proposal calls `acceptOwnership()` on each vault

## Actions

- Accept ownership of the WETH Flagship MetaMorpho Vault
- Accept ownership of the USDC Flagship MetaMorpho Vault
- Accept ownership of the EURC Flagship MetaMorpho Vault
- Accept ownership of the cbBTC Frontier MetaMorpho Vault
