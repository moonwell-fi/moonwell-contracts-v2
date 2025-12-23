# OEV Liquidation Specification

This document explains how to use the `ChainlinkOEVWrapper` and
`ChainlinkOEVMorphoWrapper` contracts to perform liquidations with early price
access in the Moonwell protocol.

---

## Deployed Contract Addresses

### Base

#### Core Market OEV Wrapper (ChainlinkOEVWrapper)

| Asset | Contract                      | Address                                      |
| ----- | ----------------------------- | -------------------------------------------- |
| WETH  | CHAINLINK_ETH_USD_OEV_WRAPPER | `0xeb083d234ec636A10325ea42bCbbE09Aa56d1547` |

#### WETH Core Market Addresses

| Contract      | Address                                      | Description         |
| ------------- | -------------------------------------------- | ------------------- |
| WETH          | `0x4200000000000000000000000000000000000006` | Underlying token    |
| MOONWELL_WETH | `0x628ff693426583D9a7FB391E54366292F509D457` | mToken (collateral) |

#### Morpho Market OEV Wrapper (ChainlinkOEVMorphoWrapper)

| Asset | Contract                        | Address                                      |
| ----- | ------------------------------- | -------------------------------------------- |
| WELL  | CHAINLINK_WELL_USD_ORACLE_PROXY | `0xAEeE6335f50e1f8aF924DF0742b1879C9761F5f5` |

#### WELL/USDC Morpho Market Parameters

```solidity
MarketParams memory params = MarketParams({
    loanToken: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,        // USDC
    collateralToken: 0xA88594D404727625A9437C3f886C7643872296AE,  // xWELL
    oracle: 0x71FBaD6c2200C8A5B89380f9B6bb8a35d411c852,           // MORPHO_CHAINLINK_WELL_USD_ORACLE
    irm: 0x46415998764C29aB2a25CbeA6254146D50D22687,              // MORPHO_ADAPTIVE_CURVE_IRM
    lltv: 625000000000000000                                      // 0.625e18 (62.5%)
});
```

| Parameter         | Value                                        | Description             |
| ----------------- | -------------------------------------------- | ----------------------- |
| `loanToken`       | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | USDC on Base            |
| `collateralToken` | `0xA88594D404727625A9437C3f886C7643872296AE` | xWELL (wrapped WELL)    |
| `oracle`          | `0x71FBaD6c2200C8A5B89380f9B6bb8a35d411c852` | Morpho Chainlink Oracle |
| `irm`             | `0x46415998764C29aB2a25CbeA6254146D50D22687` | Adaptive Curve IRM      |
| `lltv`            | `625000000000000000`                         | 62.5% Liquidation LTV   |

### Optimism

#### Core Market OEV Wrapper (ChainlinkOEVWrapper)

| Asset | Contract                      | Address                                      |
| ----- | ----------------------------- | -------------------------------------------- |
| WETH  | CHAINLINK_ETH_USD_OEV_WRAPPER | `0x531f69127bB04Ebb0Fd321b8092d34a4C2B4E0f1` |

#### WETH Core Market Addresses

| Contract      | Address                                      | Description         |
| ------------- | -------------------------------------------- | ------------------- |
| WETH          | `0x4200000000000000000000000000000000000006` | Underlying token    |
| MOONWELL_WETH | `0xb4104C02BBf4E9be85AAa41a62974E4e28D59A33` | mToken (collateral) |

### Configuration Parameters (MIP-X38)

| Parameter          | Value | Description                         |
| ------------------ | ----- | ----------------------------------- |
| `liquidatorFeeBps` | 4000  | Liquidator keeps 40% of profit      |
| `maxRoundDelay`    | 10    | Seconds before price becomes public |
| `maxDecrements`    | 10    | Max rounds to search backwards      |

---

## Overview

Both OEV wrapper contracts implement a mechanism that:

1. **Delays price updates** by default (returns previous round data)
2. **Allows liquidators to access fresh prices** by calling
   `updatePriceEarlyAndLiquidate()`
3. **Splits liquidation profits** between the liquidator and the protocol

This captures value that would otherwise go to MEV searchers/block builders.

---

## ChainlinkOEVWrapper (Moonwell Core Markets)

### Contract Purpose

Used for liquidations in Moonwell's Core lending markets (mToken markets).

### Key Parameters

| Parameter          | Description                                                    |
| ------------------ | -------------------------------------------------------------- |
| `liquidatorFeeBps` | Percentage of profit (in basis points) that goes to liquidator |
| `maxRoundDelay`    | Time window (seconds) during which prices are delayed          |
| `maxDecrements`    | Maximum previous rounds to check for valid price data          |
| `feeRecipient`     | Address receiving protocol's share of profits                  |

### Function Signature

```solidity
function updatePriceEarlyAndLiquidate(
    address borrower,
    uint256 repayAmount,
    address mTokenCollateral,
    address mTokenLoan
) external nonReentrant
```

### Parameters

| Parameter          | Type    | Description                                       |
| ------------------ | ------- | ------------------------------------------------- |
| `borrower`         | address | Address of the underwater borrower to liquidate   |
| `repayAmount`      | uint256 | Amount of loan tokens to repay                    |
| `mTokenCollateral` | address | mToken market address for collateral being seized |
| `mTokenLoan`       | address | mToken market address for the loan being repaid   |

### Liquidation Flow

```
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│   Liquidator    │────▶│  ChainlinkOEVWrapper │────▶│  Moonwell Pool  │
│                 │     │                      │     │   (Comptroller) │
└─────────────────┘     └──────────────────────┘     └─────────────────┘
        │                        │                           │
        │  1. Transfer loan      │                           │
        │     tokens             │                           │
        │───────────────────────▶│                           │
        │                        │  2. Update cachedRoundId  │
        │                        │     (unlock fresh price)  │
        │                        │                           │
        │                        │  3. Execute liquidation   │
        │                        │─────────────────────────▶│
        │                        │                           │
        │                        │  4. Receive mToken        │
        │                        │     collateral            │
        │                        │◀─────────────────────────│
        │                        │                           │
        │  5. Receive mToken     │  6. Send protocol fee    │
        │     (repay + bonus)    │     to feeRecipient      │
        │◀───────────────────────│                           │
```

### Example Usage (Solidity)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IChainlinkOEVWrapper {
  function updatePriceEarlyAndLiquidate(
    address borrower,
    uint256 repayAmount,
    address mTokenCollateral,
    address mTokenLoan
  ) external;
}

contract OEVLiquidator {
  IChainlinkOEVWrapper public oevWrapper;

  constructor(address _oevWrapper) {
    oevWrapper = IChainlinkOEVWrapper(_oevWrapper);
  }

  function liquidate(
    address borrower,
    uint256 repayAmount,
    address mTokenCollateral,
    address mTokenLoan,
    address loanToken
  ) external {
    // 1. Transfer loan tokens from caller
    IERC20(loanToken).transferFrom(msg.sender, address(this), repayAmount);

    // 2. Approve OEV wrapper to spend loan tokens
    IERC20(loanToken).approve(address(oevWrapper), repayAmount);

    // 3. Execute liquidation with early price access
    oevWrapper.updatePriceEarlyAndLiquidate(
      borrower,
      repayAmount,
      mTokenCollateral,
      mTokenLoan
    );

    // 4. mToken collateral is now in this contract
    // Transfer to caller or redeem for underlying
  }
}
```

### Collateral Distribution

After liquidation, the seized mTokens are split:

- **Liquidator receives**: Repayment value + (Profit × `liquidatorFeeBps`
  / 10000)
- **Protocol receives**: Remaining profit (Profit × (10000 - `liquidatorFeeBps`)
  / 10000)

---

## ChainlinkOEVMorphoWrapper (Moonwell Isolated Markets)

### Contract Purpose

Used for liquidations in Morpho Blue isolated lending markets.

### Key Differences from ChainlinkOEVWrapper

| Aspect                | ChainlinkOEVWrapper | ChainlinkOEVMorphoWrapper |
| --------------------- | ------------------- | ------------------------- |
| Market Type           | Moonwell Core       | Morpho Blue               |
| Collateral Received   | mTokens             | Underlying tokens         |
| Market Identification | mToken addresses    | MarketParams struct       |
| Slippage Protection   | Fixed repay amount  | maxRepayAmount parameter  |
| Upgradeable           | No                  | Yes (reinitializer)       |

### Function Signature

```solidity
function updatePriceEarlyAndLiquidate(
    MarketParams memory marketParams,
    address borrower,
    uint256 seizedAssets,
    uint256 maxRepayAmount
) external
```

### Parameters

| Parameter        | Type         | Description                                                |
| ---------------- | ------------ | ---------------------------------------------------------- |
| `marketParams`   | MarketParams | Morpho market identification struct                        |
| `borrower`       | address      | Address of the underwater borrower                         |
| `seizedAssets`   | uint256      | Amount of collateral to seize                              |
| `maxRepayAmount` | uint256      | Maximum loan tokens willing to repay (slippage protection) |

### MarketParams Struct

```solidity
struct MarketParams {
  address loanToken;
  address collateralToken;
  address oracle; // Must use this OEV wrapper as BASE_FEED_1
  address irm; // Interest rate model
  uint256 lltv; // Liquidation LTV
}
```

### Liquidation Flow

```
┌─────────────────┐     ┌────────────────────────────┐     ┌─────────────────┐
│   Liquidator    │────▶│  ChainlinkOEVMorphoWrapper │────▶│   Morpho Blue   │
└─────────────────┘     └────────────────────────────┘     └─────────────────┘
        │                           │                              │
        │  1. Transfer max loan     │                              │
        │     tokens                │                              │
        │──────────────────────────▶│                              │
        │                           │  2. Update cachedRoundId     │
        │                           │                              │
        │                           │  3. Approve & call liquidate │
        │                           │─────────────────────────────▶│
        │                           │                              │
        │                           │  4. Receive collateral       │
        │                           │     tokens                   │
        │                           │◀─────────────────────────────│
        │                           │                              │
        │  5. Return excess loan    │                              │
        │     tokens                │                              │
        │◀──────────────────────────│                              │
        │                           │                              │
        │  6. Receive collateral    │  7. Send protocol fee        │
        │     (repay + bonus)       │     to feeRecipient          │
        │◀──────────────────────────│                              │
```

### Example Usage (Solidity)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct MarketParams {
  address loanToken;
  address collateralToken;
  address oracle;
  address irm;
  uint256 lltv;
}

interface IChainlinkOEVMorphoWrapper {
  function updatePriceEarlyAndLiquidate(
    MarketParams memory marketParams,
    address borrower,
    uint256 seizedAssets,
    uint256 maxRepayAmount
  ) external;
}

contract MorphoOEVLiquidator {
  IChainlinkOEVMorphoWrapper public oevWrapper;

  constructor(address _oevWrapper) {
    oevWrapper = IChainlinkOEVMorphoWrapper(_oevWrapper);
  }

  function liquidate(
    MarketParams calldata marketParams,
    address borrower,
    uint256 seizedAssets,
    uint256 maxRepayAmount
  ) external {
    address loanToken = marketParams.loanToken;

    // 1. Transfer max loan tokens from caller
    IERC20(loanToken).transferFrom(msg.sender, address(this), maxRepayAmount);

    // 2. Approve OEV wrapper
    IERC20(loanToken).approve(address(oevWrapper), maxRepayAmount);

    // 3. Execute liquidation - excess tokens returned automatically
    oevWrapper.updatePriceEarlyAndLiquidate(
      marketParams,
      borrower,
      seizedAssets,
      maxRepayAmount
    );

    // 4. Collateral tokens (not mTokens) are now in this contract
    // Transfer to caller
    uint256 collateralBalance = IERC20(marketParams.collateralToken).balanceOf(
      address(this)
    );
    IERC20(marketParams.collateralToken).transfer(
      msg.sender,
      collateralBalance
    );

    // 5. Return any remaining loan tokens
    uint256 loanBalance = IERC20(loanToken).balanceOf(address(this));
    if (loanBalance > 0) {
      IERC20(loanToken).transfer(msg.sender, loanBalance);
    }
  }
}
```

### Important Requirement

The market's Morpho oracle must have this OEV wrapper as `BASE_FEED_1`:

```solidity
require(
    address(IMorphoChainlinkOracleV2(marketParams.oracle).BASE_FEED_1()) == address(this),
    "ChainlinkOEVMorphoWrapper: oracle must be the same as the base feed 1"
);
```

---

## Price Delay Mechanism

Both wrappers implement the same delay logic in `latestRoundData()`:

```solidity
// Pseudo-code
if (roundId != cachedRoundId && block.timestamp < updatedAt + maxRoundDelay) {
    // Return PREVIOUS round data (delayed price)
    return getPreviousRoundData();
} else {
    // Return current round data (fresh price available to everyone)
    return currentRoundData;
}
```

**Key Insight**: After `maxRoundDelay` seconds, the fresh price becomes
available to everyone. The OEV window is only valuable during this delay period.

---

## Profitability Calculation

### For Liquidators

```
Gross Profit = Collateral Value - Repayment Value
Liquidator Bonus = (Gross Profit × liquidatorFeeBps) / 10000
Total Received = Repayment Value + Liquidator Bonus
```

### Example

- Repayment: 1,000 USDC
- Collateral seized value: 1,100 USDC (10% liquidation incentive)
- Gross profit: 100 USDC
- `liquidatorFeeBps`: 5000 (50%)
- Liquidator bonus: 50 USDC
- **Liquidator receives**: 1,050 USDC worth of collateral
- **Protocol receives**: 50 USDC worth of collateral

---
