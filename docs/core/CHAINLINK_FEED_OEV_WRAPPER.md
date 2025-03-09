# Chainlink OEV Wrapper Specification

This specification defines a contract architecture for capturing Oracle
Extractable Value (OEV) at the protocol level, fully on-chain.

## Objective

Create a wrapper contract for Chainlink price feeds that allows early price
updates through a fee-based mechanism, while ensuring the feed remains
functional even without early updates.

## Contract Architecture

1. Create a new contract `ChainlinkFeedOEVWrapper` that implements the
   `AggregatorV3Interface` and inherits from `Ownable`

   - Has a reference to the original Chainlink feed (immutable)
   - Maintains cached round ID
   - Configurable maximum round delay (default 10 seconds)
   - Configurable fee multiplier (default 99)
   - Configurable maximum decrements for finding valid rounds
   - WETH contract reference for handling fees (immutable)
   - ETH market reference for adding reserves (immutable)
   - Temporal Governor will own all deployed instances of
     `ChainlinkFeedOEVWrapper`

## Core Functionality

1. Implement `latestRoundData` function:

   - If current round ID matches cached round ID or if the round is too old
     (past maxRoundDelay), return latest data from Chainlink feed
   - Otherwise, attempt to find most recent valid round by checking previous
     rounds up to maxDecrements times
   - Validate round data before returning (price must be positive, round ID must
     match answeredInRound)

2. Implement `updatePriceEarly` function:

   - Requires payment based on: `(tx.gasprice - block.basefee) * feeMultiplier`
   - Fetches latest round data from Chainlink feed
   - Validates the round data
   - Updates cached round ID
   - Wraps received ETH into WETH
   - Adds WETH to ETH market reserves
   - Emits ProtocolOEVRevenueUpdated event

3. Administrative functions:

   - `setFeeMultiplier`: Update the fee calculation multiplier
   - `setMaxDecrements`: Update maximum number of round decrements
   - `setMaxRoundDelay`: Update maximum round delay

4. Standard AggregatorV3Interface functions:

   - `decimals`: Returns the number of decimals from the underlying Chainlink
     price feed
   - `description`: Returns the description string from the underlying Chainlink
     price feed
   - `version`: Returns the version number from the underlying Chainlink price
     feed
   - `getRoundData`: Returns the price data for a specific round from the
     underlying Chainlink price feed
   - `latestRound`: Returns the latest round ID from the underlying Chainlink
     price feed

## References

1. [Priority Is All You Need](https://www.paradigm.xyz/2024/06/priority-is-all-you-need)
