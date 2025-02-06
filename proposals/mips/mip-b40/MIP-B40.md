# MIP-B40: Add LBTC Market to Moonwell on Base

## Summary

This proposal seeks to onboard LBTC, [Lombard’s](https://www.lombard.finance/)
liquid-staked Bitcoin (LST), as a new collateral asset on Moonwell’s Base
deployment. LBTC combines Bitcoin’s secure, decentralized store of value with
[Babylon’s](https://babylonlabs.io/) PoS yield capabilities, unlocking new
opportunities for BTC lending and borrowing. By activating a market for LBTC on
Base, we aim to strengthen BTC liquidity, enable leveraged LBTC positions, and
introduce looping opportunities with Pendle PT tokens, further enhancing
engagement with Moonwell and the broader DeFi ecosystem. LBTC’s integration will
allow Moonwell users to benefit from Babylon Points, Lombard’s Lux program, and
robust liquidity in BTC-pegged assets. This strategic addition supports
Moonwell’s mission to bring the world onchain through powerful, accessible DeFi
tools. For additional details, please review the
[LBTC token documentation](https://docs.lombard.finance),
[Dune dashboard](ttps://dune.com/lombard_protocol/lombard), and
[LBTC asset listing forum post](https://forum.moonwell.fi/t/add-lbtc-to-moonwell-core-market-on-base/1454/).

## Token Information

- **Name:** LBTC
- **Token Standard:** ERC20
- **Total Supply:** 11,600 LBTC
- **Circulating Supply (Base):** 1,263.55 LBTC
- **Token Contract:**
  [0xecAc9C5F704e954931349Da37F60E39f515c11c1](https://basescan.io/address/0xecAc9C5F704e954931349Da37F60E39f515c11c1)
- **Price Feed:** Redstone PoR Oracle (BTC/LBTC) ×
  [Chainlink BTC/USD](https://basescan.org/address/0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F)

## Gauntlet's Risk Analysis and Recommendations

### Initial Risk Parameters

| **Parameter**          | **Value** |
| ---------------------- | --------- |
| Collateral Factor (CF) | 81%       |
| Supply Cap             | 95 LBTC   |
| Borrow Cap             | 38 LBTC   |
| Protocol Seize Share   | 30%       |
| Reserve Factor         | 10%       |

### Interest Rate Model

| **Parameter**   | **Value** |
| --------------- | --------- |
| Base Rate       | 0%        |
| Multiplier      | 7%        |
| Jump Multiplier | 2x        |
| Kink            | 35%       |

#### Interest Rate Curve

| **Utilization** | **Borrow APR** | **Supply APR** |
| --------------- | -------------- | -------------- |
| 0%              | 0%             | 0%             |
| 35% (Kink)      | 2.45%          | 0.77%          |
| 100%            | 131.5%         | 118.4%         |

The interest rate curve features a kink at 35%, ensuring competitive rates while
incentivizing balanced utilization.

## Supporting Data

- **Volatility:** Annualized 30-day log volatility of 0.92% reflects LBTC’s high
  parity with its underlying BTC.
- **Liquidity:** On-chain liquidity supports trading up to 95 LBTC with 15%
  slippage, providing sufficient buffer for supply caps.

## Voting Options

- **Aye:** Approve the proposal to activate a core lending market for LBTC on
  Base with Gauntlet's specified initial risk parameters.
- **Nay:** Reject the proposal.
- **Abstain:** Abstain from voting on this proposal.
