# Chainlink OEV Wrapper Specification

This specification defines a contract architecture for capturing Oracle
Extractable Value (OEV) at the protocol level, fully on-chain.

## Objective

Create a wrapper contract for Chainlink price feeds that allows early price
updates through a fee-based mechanism, while ensuring the feed remains
functional even without early updates.

## Contract Architecture

1. Create a new contract `ChainlinkFeedOEVWrapper` that implements the
   `AggregatorV3Interface`

   - Has a reference to the original Chainlink feed
   - Maintains cached price and timestamp
   - Configurable early update window (default 30 seconds)
   - Configurable fee multiplier (default 99)
   - WETH contract reference for handling fees
   - ETH market reference for adding reserves

## Core Functionality

1. Implement `latestRoundData` function:

   - If current time is past the early update window, return latest data from
     Chainlink feed
   - Otherwise, return the cached data (price and timestamp)

2. Implement `updatePriceEarly` function:

   - Requires payment based on: `(tx.gasprice - block.basefee) * feeMultiplier`
   - Verifies new timestamp is greater than cached timestamp
   - Fetches and caches latest price from Chainlink
   - Wraps received ETH into WETH
   - Adds WETH to ETH market reserves

3. Administrative functions:

   - `setFeeMultiplier`: Update the fee calculation multiplier
   - `setEarlyUpdateWindow`: Modify the early update time window
   - `setETHMarket`: Update the ETH market address

4. Standard AggregatorV3Interface functions:

   - `decimals`: Returns the number of decimals from the underlying Chainlink
     price feed
   - `description`: Returns the description string from the underlying Chainlink
     price feed
   - `version`: Returns the version number from the underlying Chainlink price
     feed
   - `getRoundData`: Returns the price data for a specific round from the
     underlying Chainlink price feed

## References

1. [Priority Is All You Need](https://www.paradigm.xyz/2024/06/priority-is-all-you-need)
