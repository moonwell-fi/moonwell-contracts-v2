# MIP-B39: Add tBTC Market to Moonwell on Base

## Summary

This proposal seeks to onboard [tBTC](https://threshold.network/), a
decentralized Bitcoin-backed token, as a new collateral asset on Moonwell’s Base
deployment. Unlike traditional Bitcoin-pegged assets reliant on centralized
intermediaries, tBTC uses a decentralized threshold cryptography design secured
by the Threshold Network. This ensures trust minimization, censorship
resistance, and complete transparency, aligning with the core principles of
decentralized finance (DeFi). Listing tBTC on Moonwell will strengthen Bitcoin
liquidity, empower users with a decentralized option for earning yield on their
Bitcoin, and create collaboration opportunities with the Threshold Network DAO.
For additional details, please review the
[tBTC token documentation](https://docs.threshold.network/applications/tbtc-v2)
and the
[tBTC asset listing forum post](https://forum.moonwell.fi/t/tbtc-asset-listing/1497).

## Token Information

- **Name:** tBTC
- **Token Standard:** ERC20
- **Total Supply:** 4,651.88 BTC
- **Circulating Supply (Base):** 340 tBTC
- **Token Contract:**
  [0x236aa50979d5f3de3bd1eeb40e81137f22ab794b](https://basescan.org/token/0x236aa50979d5f3de3bd1eeb40e81137f22ab794b)
- **Price Feed:**
  [Chainlink tBTC/USD](https://basescan.org/address/0x6D75BFB5A5885f841b132198C9f0bE8c872057BF)

## Benefits to the Moonwell Community

1. **Decentralized Bitcoin Liquidity:** Strengthens Moonwell’s lending markets
   with a decentralized, censorship-resistant Bitcoin-backed token.
2. **Increased User Opportunity:** Empowers users to earn yield on their Bitcoin
   through Moonwell’s Base lending markets.
3. **Collaborative Growth:** Opens opportunities for co-marketing and ecosystem
   development with the Threshold Network DAO.
4. **Trust Minimization:** Fully permissionless and backed 1:1 with Bitcoin,
   tBTC reduces reliance on centralized entities.

## Gauntlet's Risk Analysis and Recommendations

### Initial Risk Parameters

| **Parameter**          | **Value** |
| ---------------------- | --------- |
| Collateral Factor (CF) | 81%       |
| Supply Cap             | 45 tBTC   |
| Borrow Cap             | 18 tBTC   |
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

- **Volatility:** Annualized 30-day log volatility of 1.47% reflects tBTC’s high
  parity with Bitcoin.
- **Liquidity:** On-chain liquidity supports trading up to 45 tBTC with 15%
  slippage. Caps are set conservatively and will be adjusted as market
  conditions evolve.

## Voting Options

- **Aye:** Approve the proposal to activate a core lending market for tBTC on
  Base with Gauntlet's specified initial risk parameters.
- **Nay:** Reject the proposal.
- **Abstain:** Abstain from voting on this proposal.
