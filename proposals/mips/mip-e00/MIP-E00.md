# MIP-E00: Deploy Moonwell Protocol to Ethereum Mainnet

## Summary

This proposal deploys the Moonwell Protocol to Ethereum Mainnet (Chain ID: 1),
establishing a new lending and borrowing market on the world's largest smart
contract platform.

## Proposal Details

### Markets to Deploy

| Market | Collateral Factor | Reserve Factor | Supply Cap  | Borrow Cap |
| ------ | ----------------- | -------------- | ----------- | ---------- |
| WETH   | 80%               | 10%            | 50,000      | 35,000     |
| USDC   | 85%               | 10%            | 100,000,000 | 80,000,000 |
| USDT   | 80%               | 10%            | 50,000,000  | 40,000,000 |
| cbBTC  | 75%               | 15%            | 1,000       | 500        |

### MetaMorpho Vaults

- WETH Flagship Vault (mwETH)
- USDC Flagship Vault (mwUSDC)
- USDT Flagship Vault (mwUSDT)

### Oracle Configuration

- **WETH**: Chainlink ETH/USD
- **USDC**: Chainlink USDC/USD
- **USDT**: Chainlink USDT/USD
- **cbBTC**: Chainlink cbBTC/USD

### Governance

The deployment includes a TemporalGovernor contract that receives governance
actions from Moonbeam via Wormhole. This enables cross-chain governance of the
Ethereum deployment from the Moonwell governance hub on Moonbeam.

### Risk Parameters

- Liquidation Incentive: 10%
- Close Factor: 50%
- Protocol Seize Share: 3%

## Deployment Contracts

1. TemporalGovernor - Cross-chain governance receiver
2. Unitroller + Comptroller - Risk management
3. MultiRewardDistributor - Reward distribution
4. ChainlinkOracle - Price feed aggregator
5. MErc20Delegate - mToken implementation
6. MErc20Delegator - mToken proxy per market
7. JumpRateModel - Interest rate models
8. WETHRouter - ETH deposit convenience
9. MetaMorpho Vaults - ERC4626 vaults

## Security Considerations

- Guardian addresses match Base deployment for consistent security posture
- Capped price feeds provide additional protection for stablecoins and LSTs
- Standard 30-day permissionless unpause time for governance safety
