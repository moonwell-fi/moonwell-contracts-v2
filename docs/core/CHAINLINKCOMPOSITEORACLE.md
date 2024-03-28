# ChainlinkCompositeOracle

## Overview

The `ChainlinkCompositeOracle` contract is a contract designed to combine
multiple Chainlink oracle prices together. It accommodates the combination of
either 2 or 3 Chainlink oracles. The contract uses SafeCast from the
OpenZeppelin contracts library for safe casting operations.

The `ChainlinkCompositeOracle` contract holds immutable references to a base
price feed Chainlink oracle and up to two multiplier oracles. The use of
immutables ensures gas efficiency. The base oracle typically represents a base
asset such as ETH/USD, while the multipliers represent conversion rates for
other assets.

The contract returns the scaling factor applied to the price with 18 decimal
places for consistency and to ensure compatibility with the ChainlinkOracle
contract.

## Constructor

The `ChainlinkCompositeOracle` contract constructor accepts the following
parameters:

- `baseAddress`: The base oracle address. Required
- `multiplierAddress`: The multiplier oracle address. Required
- `secondMultiplierAddress`: The second multiplier oracle address (if any).
  Optional and contract will function normally if this is set to address 0.

These addresses are assigned to their respective public immutable variables.

## Functions

### latestRoundData

This function returns the composite price calculated using either one or two
multipliers, based on whether the `secondMultiplier` address is zero or not. It
returns five parameters, three of which are always zero and are unused in
`ChainlinkOracle.sol`. The composite price is returned as an int256 value and
the block timestamp is returned.

### calculatePrice

This function accepts a base price, a price multiplier, and a scaling factor. It
calculates the price by multiplying the base price with the price multiplier and
dividing by the scaling factor. The function always returns a positive value or
reverts the transaction.

### getDerivedPrice

This function retrieves the price of the base and quote assets from their
respective oracles and calculates the derived price. The derived price is
calculated as the product of the base and quote prices, divided by the scaling
factor.

### getDerivedPriceThreeOracles

This function retrieves the price of the base asset and the two quote assets
from their respective oracles and calculates the derived price. The derived
price is calculated as the product of the base price, quote price 1, and quote
price 2, divided by the square of the scaling factor.

### getPriceAndScale

This function retrieves the price of an asset from its oracle and scales it to
the expected number of decimal places.

### getPriceAndDecimals

This function retrieves the latest round data from the Chainlink oracle. It
returns the asset price and the number of decimal places the price is accurate
to.

### scalePrice

This function scales an asset price up or down to the desired number of decimal
places.

## Notes

The contract will revert if an attempt is made to get the derived price from a
single oracle and the oracle returns an invalid or zero price. The same applies
for the `getDerivedPriceThreeOracles` function if any of the oracles return an
invalid or zero price.

The contract handles the scaling of prices diligently to cater to different
decimal precision returned by different oracles. It ensures that all
calculations are performed with the same decimal precision.

The contract includes multiple sanity checks, such as ensuring the derived price
is always positive and handling oracle data validity checks.
