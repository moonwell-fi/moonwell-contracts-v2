# wstETH Price Oracle for Ethereum Mainnet

## Status: Planning

## Created: 2026-01-20

## Last Updated: 2026-01-20

---

## Problem Statement

Moonwell needs a price oracle for wstETH on Ethereum mainnet. However:

- There is **no official Chainlink wstETH/stETH exchange rate feed** on Ethereum
  mainnet
- Chainlink only provides:
  - `stETH/ETH` feed
  - `stETH/USD` feed
  - `ETH/USD` feed
- The wstETH/stETH exchange rate feed exists on L2s (Base, Arbitrum, Optimism)
  but NOT on Ethereum mainnet

---

## Recommended Solution

Create a custom **WstETHExchangeRateAdapter** contract that:

1. Reads the exchange rate directly from the wstETH contract
2. Exposes it in Chainlink AggregatorV3Interface format
3. Use with Moonwell's existing `ChainlinkCompositeOracle`

### Price Calculation

```
wstETH/USD = ETH/USD × stETH/ETH × wstETH/stETH
```

### Feed Components

| Component    | Source             | Address (Ethereum Mainnet)                   |
| ------------ | ------------------ | -------------------------------------------- |
| ETH/USD      | Chainlink          | `0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419` |
| stETH/ETH    | Chainlink          | `0x86392dC19c0b719886221c78AB11eb8Cf5c52812` |
| wstETH/stETH | **Custom Adapter** | TBD (to be deployed)                         |

### wstETH Contract (Ethereum Mainnet)

- Address: `0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0`
- Function: `stEthPerToken()` returns the exchange rate

---

## Implementation Plan

### Step 1: Create WstETHExchangeRateAdapter Contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IWstETH {
  function stEthPerToken() external view returns (uint256);
}

/// @notice Adapter to read wstETH/stETH exchange rate in Chainlink AggregatorV3 format
/// @dev This reads directly from the wstETH contract - the canonical source of truth
contract WstETHExchangeRateAdapter {
  /// @notice The wstETH contract address
  IWstETH public immutable wstETH;

  /// @notice Decimals for the exchange rate (matches wstETH contract)
  uint8 public constant decimals = 18;

  /// @notice Description of this price feed
  string public constant description = "wstETH/stETH Exchange Rate";

  /// @notice Version of this adapter
  uint256 public constant version = 1;

  constructor(address _wstETH) {
    require(_wstETH != address(0), "Invalid wstETH address");
    wstETH = IWstETH(_wstETH);
  }

  /// @notice Get the latest exchange rate in Chainlink AggregatorV3 format
  /// @return roundId Always 0 (unused by Moonwell)
  /// @return answer The wstETH/stETH exchange rate (how much stETH per 1 wstETH)
  /// @return startedAt Always 0 (unused by Moonwell)
  /// @return updatedAt Current block timestamp
  /// @return answeredInRound Always 0 (unused by Moonwell)
  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    )
  {
    // stEthPerToken returns how much stETH you get per 1 wstETH (18 decimals)
    uint256 rate = wstETH.stEthPerToken();

    require(rate > 0, "Invalid exchange rate");

    return (
      0, // roundId (unused)
      int256(rate), // answer: wstETH/stETH rate
      0, // startedAt (unused)
      block.timestamp, // updatedAt
      0 // answeredInRound (unused)
    );
  }
}
```

**File location:** `src/oracles/WstETHExchangeRateAdapter.sol`

### Step 2: Create Deployment Script

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Script } from "forge-std/Script.sol";
import { WstETHExchangeRateAdapter } from "@protocol/oracles/WstETHExchangeRateAdapter.sol";

contract DeployWstETHExchangeRateAdapter is Script {
  // Ethereum Mainnet wstETH address
  address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

  function run() external returns (address) {
    vm.startBroadcast();

    WstETHExchangeRateAdapter adapter = new WstETHExchangeRateAdapter(WSTETH);

    vm.stopBroadcast();

    return address(adapter);
  }
}
```

**File location:** `script/DeployWstETHExchangeRateAdapter.s.sol`

### Step 3: Deploy ChainlinkCompositeOracle for wstETH

```solidity
// Ethereum Mainnet addresses
address ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;      // Chainlink ETH/USD
address STETH_ETH = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;    // Chainlink stETH/ETH
address WSTETH_STETH_ADAPTER = <DEPLOYED_ADAPTER_ADDRESS>;         // Our adapter

new ChainlinkCompositeOracle(
    ETH_USD,              // base
    STETH_ETH,            // multiplier
    WSTETH_STETH_ADAPTER  // secondMultiplier
);
```

### Step 4: Write Tests

Create test file at `test/unit/oracles/WstETHExchangeRateAdapter.t.sol`:

1. Test `latestRoundData()` returns valid data
2. Test rate is always positive
3. Test decimals is 18
4. Fork test against real Ethereum mainnet wstETH contract
5. Compare result with expected exchange rate range (~1.16-1.20 stETH per
   wstETH)

### Step 5: Integration Test

Create integration test that:

1. Deploys the adapter
2. Deploys ChainlinkCompositeOracle with all 3 feeds
3. Verifies the final wstETH/USD price is reasonable
4. Compares against Aave's wstETH price as sanity check

---

## Security Considerations

### Why This Approach is Safe

1. **Canonical Source**: The exchange rate comes directly from the wstETH
   contract itself - this is the actual redemption rate, not a market price
2. **Immutable**: The adapter has no admin functions, no upgradability, no owner
3. **Battle-tested**: Same approach used by Aave (their CAPO calls
   `getPooledEthByShares()`)
4. **No Oracle Manipulation**: The rate is calculated from
   `totalPooledEther / totalShares` in Lido - cannot be flash-loan manipulated

### Potential Risks

1. **Lido Contract Risk**: If the wstETH contract is compromised, the rate could
   be wrong

   - Mitigation: wstETH is one of the most battle-tested contracts in DeFi

2. **No Staleness Check**: Unlike Chainlink, there's no heartbeat

   - Mitigation: The rate changes very slowly (staking rewards accrue ~4% APY)
   - The rate only goes up, never down (unless slashing event)

3. **No Circuit Breaker**: No bounds checking on the rate
   - Mitigation: Could add bounds checking in the adapter (optional)

---

## Alternative Approaches Considered

### Option 1: Use Aave's Oracle on Ethereum

- Address: `0xe1D97bF61901B075E9626c8A2340a7De385861Ef`
- **Rejected**: Has ACL_MANAGER dependency on Aave governance
- Risk/pool admins can modify cap parameters

### Option 2: Fork Aave's CAPO

- Deploy Moonwell's own WstETHPriceCapAdapter
- **More complex**: Requires own ACL_MANAGER or governance integration
- Could be considered for additional safety (price capping)

### Option 3: Wait for Chainlink Feed

- **Rejected**: No timeline for Chainlink to deploy wstETH/stETH on mainnet
- Already available on L2s, unclear why not on mainnet

---

## References

- [Lido wstETH Contract](https://etherscan.io/address/0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0)
- [Lido wsteth-eth-price-feed Repo](https://github.com/lidofinance/wsteth-eth-price-feed)
- [Aave CAPO Implementation](https://github.com/bgd-labs/aave-capo)
- [Chainlink stETH/ETH Feed](https://data.chain.link/ethereum/mainnet/crypto-eth/steth-eth)

---

## Checklist

- [ ] Create `WstETHExchangeRateAdapter.sol`
- [ ] Create deployment script
- [ ] Write unit tests
- [ ] Write integration tests (fork tests)
- [ ] Deploy adapter to Ethereum mainnet
- [ ] Deploy `ChainlinkCompositeOracle` for wstETH
- [ ] Add addresses to `chains/1.json`
- [ ] Create governance proposal to add wstETH market

---

## Notes

- Current wstETH/stETH rate is approximately **1.18** (as of Jan 2026)
- Rate increases slowly over time as staking rewards accrue
- Moonwell already uses `ChainlinkCompositeOracle` for similar assets (cbETH,
  rETH)
