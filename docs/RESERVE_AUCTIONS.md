# Moonwell Reserve Auctions Documentation

## Introduction

Moonwell Reserve Auctions is a on-chain system designed to facilitate the
exchange of reserve tokens for WELL tokens. This automated mechanism enables
participants to acquire reserve tokens at dynamic discount rates through a
structured auction process.

## Technical Specifications

### Auction Parameters

- **Total Duration**: 2 weeks (336 hours)
- **Mini-Auction Structure**: 84 individual 4-hour periods
- **Market Isolation**: Each supported market operates through its dedicated
  auction contract
- **Guardian Protection**: Built-in delay mechanism before auction initiation to
  allow Guardian intervention if necessary

## Auction Mechanics

### Dynamic Pricing System

The auction implements a sophisticated dynamic pricing mechanism:

1. **Initial Price**: Begins at a premium (defined by `startingPremium`)
2. **Price Decay**: Linear decrease over each 4-hour mini-auction period
3. **Price Floor**: Maximum discount capped by `maxDiscount` parameter
4. **Price Calculation**:
   ```
   discounted_price = initial_price * (1 - (time_elapsed / 4_hours * maximum_discount))
   ```

## Participation Guide

### 1. Pre-participation Requirements

- Sufficient WELL token balance
- WELL tokens approved for ReserveAutomation contract spending

### 2. Auction Monitoring

Monitor active auctions through the following contract methods:

- `saleStartTime`: Auction initiation timestamp
- `saleWindow`: Duration of the current auction window
- `getCurrentPeriodStartTime()`: Start time of the current mini-auction
- `getCurrentPeriodRemainingReserves()`: Available reserve tokens in current
  period

### 3. Output Calculation

Calculate expected returns using:

```solidity
function getAmountOut(uint256 amountWellIn) public view returns (uint256)
```

This function provides the precise amount of reserve tokens you'll receive for
your WELL tokens.

### 4. Transaction Execution

```solidity
function getReserves(
    uint256 amountWellIn,
    uint256 minAmountOut
) external returns (uint256)
```

Parameters:

- `amountWellIn`: Amount of WELL tokens to exchange
- `minAmountOut`: Minimum acceptable amount of reserve tokens

## Supported Networks and Markets

### Base Network Markets

| Asset  | Contract Address                             | Explorer Link                                                                   |
| ------ | -------------------------------------------- | ------------------------------------------------------------------------------- |
| USDC   | `0x8373155335839e3D078f3F224E8B6618Fc26eF17` | [View](https://basescan.org/address/0x8373155335839e3D078f3F224E8B6618Fc26eF17) |
| USDBC  | `0x89b89c30E2f60Bd30059c3924eF5b8c0Fcd1B64A` | [View](https://basescan.org/address/0x89b89c30E2f60Bd30059c3924eF5b8c0Fcd1B64A) |
| DAI    | `0x9f2ca3c6Cd1dddb7aD473a0a893C3104E2af15Ad` | [View](https://basescan.org/address/0x9f2ca3c6Cd1dddb7aD473a0a893C3104E2af15Ad) |
| WETH   | `0x064D8Cb3B7a22F4cFBdd602eBC7E722Bb71405D8` | [View](https://basescan.org/address/0x064D8Cb3B7a22F4cFBdd602eBC7E722Bb71405D8) |
| cbETH  | `0x48bc4876D33Db30929c373c3B949b66CB8d641F3` | [View](https://basescan.org/address/0x48bc4876D33Db30929c373c3B949b66CB8d641F3) |
| wstETH | `0xbd22DaFeF550094A32f388CD256FE133a0A14387` | [View](https://basescan.org/address/0xbd22DaFeF550094A32f388CD256FE133a0A14387) |
| rETH   | `0xEfE30785362225106367039971d82715dcB35192` | [View](https://basescan.org/address/0xEfE30785362225106367039971d82715dcB35192) |
| AERO   | `0xc7840e86A0aa22c23BCbC153CE61f6009733bf2C` | [View](https://basescan.org/address/0xc7840e86A0aa22c23BCbC153CE61f6009733bf2C) |
| weETH  | `0x75494780E76bB41c0fDf29DBA4b2Ce82501c12b0` | [View](https://basescan.org/address/0x75494780E76bB41c0fDf29DBA4b2Ce82501c12b0) |
| cbBTC  | `0x83D37e3df05F1507667AF4dfc83Ec8A38Cf2dA08` | [View](https://basescan.org/address/0x83D37e3df05F1507667AF4dfc83Ec8A38Cf2dA08) |
| EURC   | `0x7bBe5972e01BAc64fE3AD7EFfBa6D164f0a1F15f` | [View](https://basescan.org/address/0x7bBe5972e01BAc64fE3AD7EFfBa6D164f0a1F15f) |
| wrsETH | `0xe34D7D109B97e1b1DAc9A9920e6A6769814Ac7eE` | [View](https://basescan.org/address/0xe34D7D109B97e1b1DAc9A9920e6A6769814Ac7eE) |
| USDS   | `0xA078017f827DC7B8540C98A3bF7b2153B2aF6cB3` | [View](https://basescan.org/address/0xA078017f827DC7B8540C98A3bF7b2153B2aF6cB3) |
| TBTC   | `0x84C74431200Bcd3Ba4b557024734891857b43354` | [View](https://basescan.org/address/0x84C74431200Bcd3Ba4b557024734891857b43354) |
| LBTC   | `0xf8f7b937a4CC6Cc16b600B3611ce0c1152a5b3F9` | [View](https://basescan.org/address/0xf8f7b937a4CC6Cc16b600B3611ce0c1152a5b3F9) |

### Optimism Network Markets

| Asset  | Contract Address                             | Explorer Link                                                                              |
| ------ | -------------------------------------------- | ------------------------------------------------------------------------------------------ |
| USDC   | `0x475d7c6999dc27E640d260aBf9f2fA9333E472CF` | [View](https://optimistic.etherscan.io/address/0x475d7c6999dc27E640d260aBf9f2fA9333E472CF) |
| USDT   | `0x9E58891D8DF4e6Dd8bAfD3082A59B72C51202841` | [View](https://optimistic.etherscan.io/address/0x9E58891D8DF4e6Dd8bAfD3082A59B72C51202841) |
| DAI    | `0xE6Aea947c0F082c5Dc751BB9C7f44Ce059590962` | [View](https://optimistic.etherscan.io/address/0xE6Aea947c0F082c5Dc751BB9C7f44Ce059590962) |
| WETH   | `0x080D64570a58FF87E14CC5Cb91d1aaB26b15CFDc` | [View](https://optimistic.etherscan.io/address/0x080D64570a58FF87E14CC5Cb91d1aaB26b15CFDc) |
| cbETH  | `0x8455D94e412A498Df8727D904252892Fb111a4cD` | [View](https://optimistic.etherscan.io/address/0x8455D94e412A498Df8727D904252892Fb111a4cD) |
| wstETH | `0x01c369a6238226702E48C9C3fBB1de33F4b05D74` | [View](https://optimistic.etherscan.io/address/0x01c369a6238226702E48C9C3fBB1de33F4b05D74) |
| rETH   | `0x9E530e9F3f9b1046e223cc3eB97fA0bBab5Dd993` | [View](https://optimistic.etherscan.io/address/0x9E530e9F3f9b1046e223cc3eB97fA0bBab5Dd993) |
| OP     | `0x6427D36153dE11b694d70604B0715790769024f7` | [View](https://optimistic.etherscan.io/address/0x6427D36153dE11b694d70604B0715790769024f7) |
| VELO   | `0x589F59fBDB5952920fA557c924F6f5CFf184b155` | [View](https://optimistic.etherscan.io/address/0x589F59fBDB5952920fA557c924F6f5CFf184b155) |
| weETH  | `0x3B40085872eaEA59CF39FCafFb3dc36085aE48f6` | [View](https://optimistic.etherscan.io/address/0x3B40085872eaEA59CF39FCafFb3dc36085aE48f6) |
| wrsETH | `0xFfF466528fE1a18b95Fa910C96540A70EC2727FB` | [View](https://optimistic.etherscan.io/address/0xFfF466528fE1a18b95Fa910C96540A70EC2727FB) |
| WBTC   | `0x78a9C06188195CEE3cBf67303a1708cb8765b9ec` | [View](https://optimistic.etherscan.io/address/0x78a9C06188195CEE3cBf67303a1708cb8765b9ec) |
