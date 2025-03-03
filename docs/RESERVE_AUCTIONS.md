# Moonwell Reserve Auctions

This provides a guide on how to participate in Moonwell's markets reserve token
auctions.

## Overview

Moonwell Reserve Auctions is an automated on-chain system that facilitates the
exchange of reserve tokens for WELL tokens, offering searchers a opportunity to
bid and sell WELL tokens at a discounted rate.

## Auction Structure

- Total Auction Duration: 2 weeks
- Mini-Auction Periods: 84 separate 4-hour auctions
- Each market has its own dedicated auction contract

## How to Participate in Auctions

### 1. Monitoring Active Auctions

Active auctions can be monitored by:

- Checking the `saleStartTime` and `saleWindow` in the ReserveAutomation
  contract
- Using `getCurrentPeriodStartTime()` to find the current mini-auction period
- Using `getCurrentPeriodRemainingReserves()` to check available reserves

### 2. Understanding Price Mechanics

The price for reserve assets follows a sophisticated dynamic pricing mechanism:

- Each mini-auction period (4 hours) starts with a premium above market price
- Premium decays linearly to a maximum discount over the period
- Pricing parameters:
  - `startingPremium`: Initial premium rate (must be > 1e18, representing >100%)
  - `maxDiscount`: Maximum discount reached (must be < 1e18, representing <100%)

The price calculation involves these steps:

1. Get normalized prices (18 decimals) from Chainlink oracles for both WELL and
   reserve assets
2. Calculate current discount rate:
   ```solidity
   decayDelta = startingPremium - maxDiscount
   periodDuration = periodEnd - periodStart
   timeRemaining = periodEnd - block.timestampe
   currentDiscount = maxDiscount + (decayDelta * timeRemaining) / periodDuration
   ```
3. Calculate final amount:

   ```solidity
   // Convert WELL to USD value
   wellAmountUSD = amountWellIn * normalizedWellPrice

   // Apply discount to reserve asset price
   discountedReservePrice = normalizedReservePrice * currentDiscount / 1e18

   // Calculate output amount
   amountOut = wellAmountUSD / discountedReservePrice
   ```

### 3. Calculating Expected Output

Before bidding, you can calculate the expected output using:

- `getAmountOut(uint256 amountWellIn)`: Returns how many reserve tokens you'll
  receive for a given WELL amount
- Prices are determined using Chainlink price feeds for both WELL and the
  reserve asset

### 4. Placing a Bid

To participate in an auction:

1. Approve the ReserveAutomation contract to spend your WELL tokens
2. Call the `getReserves(uint256, uint256)` function with your desired WELL
   amount and the expected reserve amount
3. You'll receive reserve tokens immediately if the transaction succeeds

### 5. Best Practices

- Monitor price feeds to find optimal bidding opportunities
- Check remaining reserves in the current period before bidding
- Be aware of the current discount rate based on time elapsed
- Ensure you have sufficient WELL tokens before bidding

## Contract Addresses

### Base Network

| Market | Address                                      | Explorer                                                                                    |
| ------ | -------------------------------------------- | ------------------------------------------------------------------------------------------- |
| USDC   | `0x8373155335839e3D078f3F224E8B6618Fc26eF17` | [View on BaseScan](https://basescan.org/address/0x8373155335839e3D078f3F224E8B6618Fc26eF17) |
| USDBC  | `0x89b89c30E2f60Bd30059c3924eF5b8c0Fcd1B64A` | [View on BaseScan](https://basescan.org/address/0x89b89c30E2f60Bd30059c3924eF5b8c0Fcd1B64A) |
| DAI    | `0x9f2ca3c6Cd1dddb7aD473a0a893C3104E2af15Ad` | [View on BaseScan](https://basescan.org/address/0x9f2ca3c6Cd1dddb7aD473a0a893C3104E2af15Ad) |
| WETH   | `0x064D8Cb3B7a22F4cFBdd602eBC7E722Bb71405D8` | [View on BaseScan](https://basescan.org/address/0x064D8Cb3B7a22F4cFBdd602eBC7E722Bb71405D8) |
| cbETH  | `0x48bc4876D33Db30929c373c3B949b66CB8d641F3` | [View on BaseScan](https://basescan.org/address/0x48bc4876D33Db30929c373c3B949b66CB8d641F3) |
| wstETH | `0xbd22DaFeF550094A32f388CD256FE133a0A14387` | [View on BaseScan](https://basescan.org/address/0xbd22DaFeF550094A32f388CD256FE133a0A14387) |
| rETH   | `0xEfE30785362225106367039971d82715dcB35192` | [View on BaseScan](https://basescan.org/address/0xEfE30785362225106367039971d82715dcB35192) |
| AERO   | `0xc7840e86A0aa22c23BCbC153CE61f6009733bf2C` | [View on BaseScan](https://basescan.org/address/0xc7840e86A0aa22c23BCbC153CE61f6009733bf2C) |
| weETH  | `0x75494780E76bB41c0fDf29DBA4b2Ce82501c12b0` | [View on BaseScan](https://basescan.org/address/0x75494780E76bB41c0fDf29DBA4b2Ce82501c12b0) |
| cbBTC  | `0x83D37e3df05F1507667AF4dfc83Ec8A38Cf2dA08` | [View on BaseScan](https://basescan.org/address/0x83D37e3df05F1507667AF4dfc83Ec8A38Cf2dA08) |
| EURC   | `0x7bBe5972e01BAc64fE3AD7EFfBa6D164f0a1F15f` | [View on BaseScan](https://basescan.org/address/0x7bBe5972e01BAc64fE3AD7EFfBa6D164f0a1F15f) |
| wrsETH | `0xe34D7D109B97e1b1DAc9A9920e6A6769814Ac7eE` | [View on BaseScan](https://basescan.org/address/0xe34D7D109B97e1b1DAc9A9920e6A6769814Ac7eE) |
| USDS   | `0xA078017f827DC7B8540C98A3bF7b2153B2aF6cB3` | [View on BaseScan](https://basescan.org/address/0xA078017f827DC7B8540C98A3bF7b2153B2aF6cB3) |
| TBTC   | `0x84C74431200Bcd3Ba4b557024734891857b43354` | [View on BaseScan](https://basescan.org/address/0x84C74431200Bcd3Ba4b557024734891857b43354) |
| LBTC   | `0xf8f7b937a4CC6Cc16b600B3611ce0c1152a5b3F9` | [View on BaseScan](https://basescan.org/address/0xf8f7b937a4CC6Cc16b600B3611ce0c1152a5b3F9) |

### Optimism Network

| Market | Address                                      | Explorer                                                                                                           |
| ------ | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| USDC   | `0x475d7c6999dc27E640d260aBf9f2fA9333E472CF` | [View on Optimistic Etherscan](https://optimistic.etherscan.io/address/0x475d7c6999dc27E640d260aBf9f2fA9333E472CF) |
| USDT   | `0x9E58891D8DF4e6Dd8bAfD3082A59B72C51202841` | [View on Optimistic Etherscan](https://optimistic.etherscan.io/address/0x9E58891D8DF4e6Dd8bAfD3082A59B72C51202841) |
| DAI    | `0xE6Aea947c0F082c5Dc751BB9C7f44Ce059590962` | [View on Optimistic Etherscan](https://optimistic.etherscan.io/address/0xE6Aea947c0F082c5Dc751BB9C7f44Ce059590962) |
| WETH   | `0x080D64570a58FF87E14CC5Cb91d1aaB26b15CFDc` | [View on Optimistic Etherscan](https://optimistic.etherscan.io/address/0x080D64570a58FF87E14CC5Cb91d1aaB26b15CFDc) |
| cbETH  | `0x8455D94e412A498Df8727D904252892Fb111a4cD` | [View on Optimistic Etherscan](https://optimistic.etherscan.io/address/0x8455D94e412A498Df8727D904252892Fb111a4cD) |
| wstETH | `0x01c369a6238226702E48C9C3fBB1de33F4b05D74` | [View on Optimistic Etherscan](https://optimistic.etherscan.io/address/0x01c369a6238226702E48C9C3fBB1de33F4b05D74) |
| rETH   | `0x9E530e9F3f9b1046e223cc3eB97fA0bBab5Dd993` | [View on Optimistic Etherscan](https://optimistic.etherscan.io/address/0x9E530e9F3f9b1046e223cc3eB97fA0bBab5Dd993) |
| OP     | `0x6427D36153dE11b694d70604B0715790769024f7` | [View on Optimistic Etherscan](https://optimistic.etherscan.io/address/0x6427D36153dE11b694d70604B0715790769024f7) |
| VELO   | `0x589F59fBDB5952920fA557c924F6f5CFf184b155` | [View on Optimistic Etherscan](https://optimistic.etherscan.io/address/0x589F59fBDB5952920fA557c924F6f5CFf184b155) |
| weETH  | `0x3B40085872eaEA59CF39FCafFb3dc36085aE48f6` | [View on Optimistic Etherscan](https://optimistic.etherscan.io/address/0x3B40085872eaEA59CF39FCafFb3dc36085aE48f6) |
| wrsETH | `0xFfF466528fE1a18b95Fa910C96540A70EC2727FB` | [View on Optimistic Etherscan](https://optimistic.etherscan.io/address/0xFfF466528fE1a18b95Fa910C96540A70EC2727FB) |
| WBTC   | `0x78a9C06188195CEE3cBf67303a1708cb8765b9ec` | [View on Optimistic Etherscan](https://optimistic.etherscan.io/address/0x78a9C06188195CEE3cBf67303a1708cb8765b9ec) |
