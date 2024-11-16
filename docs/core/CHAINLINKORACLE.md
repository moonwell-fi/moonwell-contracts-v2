# ChainlinkOracle

The `ChainlinkOracle` contract functions as a price oracle, retrieving prices
from Chainlink and allowing for admin price overrides. The after deploy function
in ProtocolDeploymentTemplate will set the TemporalGovenor as the admin.

## Contract Variables

- `admin` (public): This address acts as an administrator of the contract,
  capable of changing prices and setting feeds. set to contract deployer
  initially.
- `nativeToken` (public): The symbol of the network's native token. However,
  this is deprecated and won't be used.
- `prices` (internal): A mapping to store prices set by the admin, overriding
  Chainlink values. If not set, it's assumed that Chainlink values will be used.
- `feeds` (internal): Stores Chainlink feeds for assets. Maps the hash of a
  token symbol to the corresponding Chainlink feed.

## Events

- `PricePosted`: Triggered when a new price override is posted by the admin.
- `NewAdmin`: Triggered when a new admin is set.
- `FeedSet`: Triggered when a new feed is set.

## Functions

### Constructor

Sets the initial admin to the contract deployer and hashes the native token
symbol for future checks.

### Modifiers

- `onlyAdmin`: Allows only the `admin` to call the function.

### Public/External Functions

- `getUnderlyingPrice(MToken mToken)`: Returns the underlying price of the given
  mToken. If a price override is not set, it fetches the price from Chainlink.
- `setUnderlyingPrice(MToken mToken, uint256 underlyingPriceMantissa)`: Allows
  the admin to override the underlying price of the given mToken.
- `setDirectPrice(address asset, uint256 price)`: Allows the admin to directly
  set the price of a given asset.
- `setFeed(string calldata symbol, address feed)`: Allows the admin to set the
  Chainlink feed for a given token symbol.
- `getFeed(string memory symbol)`: Returns the Chainlink feed for a given token
  symbol.
- `assetPrices(address asset)`: Returns the price of an asset from the override
  configuration.
- `setAdmin(address newAdmin)`: Allows the admin to change the admin address.

### Internal Functions

- `getPrice(MToken mToken)`: Returns the underlying price of a token, taking
  into account price overrides and decimal adjustments.
- `getChainlinkPrice(AggregatorV3Interface feed)`: Fetches the price from a
  given Chainlink feed, adjusting the price to the standard 1e18 scale.

## Important Considerations

- Prices set by the admin override Chainlink prices.
- Prices are scaled by 1e18.
- During an emergency override of the chainlink feed, prices for assets are
  stored in mappings and are fetched based on the asset's symbol.
- The contract uses SafeMath for arithmetic operations to prevent overflows and
  underflows, although this is redundant in the contract's solidity 0.8.0
  version.
- The contract does not support native tokens in its current deployment and it
  is expected to have some unused contract code.
