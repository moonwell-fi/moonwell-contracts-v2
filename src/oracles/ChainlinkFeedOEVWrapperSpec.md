# Chainlink OEV Wrapper Specification

This specification defines a contract architecture for capturing OEV at the
protocol level, fully on-chain.

## Objective

Create a wrapper contract for Chainlink price feeds that allows early price
updates through a bidding mechanism, while ensuring the feed remains functional
even without bids.

## Contract Architecture

1. Create a new contract `ChainlinkFeedOEVWrapper` that:

   - Implements the `AggregatorV3Interface`
   - Inherits from
     [MEVTax](https://github.com/0xfuturistic/mev-tax/blob/main/src/MEVTax.sol)

2. Key components of the wrapper contract:
   - Reference to the original Chainlink feed
   - Cached price and timestamp
   - Time window for early updates (30 seconds)
   - Receiver address is passed to the MEVTax contract
   - [Optional] override the getTaxAmount function

## Core Functionality

3. Implement `latestRoundData` function:

   - If current time is past the next update time, return latest data from
     Chainlink feed
   - Otherwise, return the cached data

4. Implement `updatePriceEarly` function:
   - Use the `applyTax` modifier
   - If conditions are met, fetch latest price from Chainlink and update cache
   - Tax is wrapped to WETH and added to Moonwell ETH Market reserves

## References

1. [Priority Is All You Need](https://www.paradigm.xyz/2024/06/priority-is-all-you-need)
