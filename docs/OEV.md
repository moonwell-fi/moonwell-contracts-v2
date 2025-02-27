# How to use Moonwell OEV system to update Chainlink feed earlier and liquidate users

## TLDR

- Moonwell's Oracle Extracted Value (OEV) system allows early price updates for
  liquidations
- Each Chainlink feed has a 10-second delay by default
- To update price early: call `updatePriceEarly()` and pay MEV tax (99x your
  priority fee)
- Example: If you set 0.1 GWEI priority fee, you'll pay 9.9 GWEI as MEV tax
- If no early updates occur, the price will automatically update to the latest
  value after the 10-second delay

## Technical Overview

The Moonwell OEV system is implemented through the `ChainlinkFeedOEVWrapper`
contract, which wraps Chainlink price feeds and adds the ability to update
prices early by paying a MEV tax. This system is designed to create a fair and
efficient liquidation market while ensuring the protocol captures value from MEV
opportunities.

## Key Components

1. **Price Feed Wrapper**: Each Chainlink oracle is wrapped in a
   `ChainlinkFeedOEVWrapper` contract
2. **Delay Mechanism**: 10-second delay on regular price updates
3. **MEV Tax**: 99x multiplier on the transaction priority fee
4. **Fallback System**: Default liquidation mechanism if no early updates occur

## How to Participate

### 1. Monitor Price Feeds

- Track the wrapped Chainlink price feeds for potential liquidation
  opportunities
- Compare current prices with liquidation thresholds
- Monitor user positions that are close to liquidation thresholds

### 2. Early Price Updates

To update a price feed early:

1. Calculate the required priority fee based on your expected profit
2. Call `updatePriceEarly()` on the relevant `ChainlinkFeedOEVWrapper` contract
3. Include a competitive priority fee that makes economic sense (remember it
   will be multiplied by 99)
4. Execute the liquidation in the same transaction

### 3. Transaction Structure

Your transaction should:

1. Include sufficient priority fee to outbid competitors
2. Update the price feed early
3. Execute the liquidation
4. Ensure total gas costs + MEV tax < expected profit

## Successful Examples

Recent successful OEV liquidations on OP Mainnet:

- [Example 1](https://optimistic.etherscan.io/tx/0x1e41a6e70674c421dc27a96cc29f6b201b589eeb9e8ce374d21df8f105448051)
- [Example 2](https://optimistic.etherscan.io/tx/0x44aea3f66f5a938645616ee7159b18ee1c081d965caafcbf3331a2af123206c0)
- [Example 3](https://basescan.org/tx/0x41f632ac09cee6c8107edd091627e20bdd27c704de4f01be5b0b65d8c3c2fbc4)
- [Example 4](https://basescan.org/tx/0xc04990567c3637ba3250831e805b99cbb6cee5d353ea5154e8e17d05ac62b3a6)

## Additional Resources

- [MIP-X14 Proposal](https://moonwell.fi/governance) - Full details of the OEV
  implementation
- [Optimism's Recognition](https://x.com/Optimism/status/1886505186853839014) -
  Thread about Moonwell's OEV implementation

## OEV Wrapper Contract Addresses

### Optimism

- ETH/USD:
  [`0x502510FA35Da0db798452a7A33138F14343FebAc`](https://optimistic.etherscan.io/address/0x502510FA35Da0db798452a7A33138F14343FebAc)
- USDC/USD:
  [`0x6F0cC02e5a7640B28F538fcc06bCA3BdFA57d1BB`](https://optimistic.etherscan.io/address/0x6F0cC02e5a7640B28F538fcc06bCA3BdFA57d1BB)
- DAI/USD:
  [`0x48F86A23aDE243F7a1028108aA65274FC84f382F`](https://optimistic.etherscan.io/address/0x48F86A23aDE243F7a1028108aA65274FC84f382F)
- USDT/USD:
  [`0x1E0E8bcFb5FFa86749B8b89fb6e055337Ba74A39`](https://optimistic.etherscan.io/address/0x1E0E8bcFb5FFa86749B8b89fb6e055337Ba74A39)
- WBTC/USD:
  [`0xAeC8E8E3696fc5fcd954eb3ebC26B72FC2FE8E8e`](https://optimistic.etherscan.io/address/0xAeC8E8E3696fc5fcd954eb3ebC26B72FC2FE8E8e)
- OP/USD:
  [`0x94423903EaAf8638bDE262c417fEEf5E2Ec507E5`](https://optimistic.etherscan.io/address/0x94423903EaAf8638bDE262c417fEEf5E2Ec507E5)
- VELO/USD:
  [`0x6aa41dF8FB0deC976B59bf0824FC5fFB88ccA958`](https://optimistic.etherscan.io/address/0x6aa41dF8FB0deC976B59bf0824FC5fFB88ccA958)
- WELL/USD:
  [`0xfeA5a5927645C0DC5C1E740Ec1B24AD320c7e58f`](https://optimistic.etherscan.io/address/0xfeA5a5927645C0DC5C1E740Ec1B24AD320c7e58f)

### Base

- ETH/USD:
  [`0xc2dA00D538237822e3c7dcb95114FA1474e4c884`](https://basescan.org/address/0xc2dA00D538237822e3c7dcb95114FA1474e4c884)
- BTC/USD:
  [`0x6F0cC02e5a7640B28F538fcc06bCA3BdFA57d1BB`](https://basescan.org/address/0x6F0cC02e5a7640B28F538fcc06bCA3BdFA57d1BB)
- EURC/USD:
  [`0x48F86A23aDE243F7a1028108aA65274FC84f382F`](https://basescan.org/address/0x48F86A23aDE243F7a1028108aA65274FC84f382F)
- WELL/USD:
  [`0x1E0E8bcFb5FFa86749B8b89fb6e055337Ba74A39`](https://basescan.org/address/0x1E0E8bcFb5FFa86749B8b89fb6e055337Ba74A39)
- USDS/USD:
  [`0xAeC8E8E3696fc5fcd954eb3ebC26B72FC2FE8E8e`](https://basescan.org/address/0xAeC8E8E3696fc5fcd954eb3ebC26B72FC2FE8E8e)
- TBTC/USD:
  [`0x94423903EaAf8638bDE262c417fEEf5E2Ec507E5`](https://basescan.org/address/0x94423903EaAf8638bDE262c417fEEf5E2Ec507E5)
- VIRTUAL/USD:
  [`0x6aa41dF8FB0deC976B59bf0824FC5fFB88ccA958`](https://basescan.org/address/0x6aa41dF8FB0deC976B59bf0824FC5fFB88ccA958)
