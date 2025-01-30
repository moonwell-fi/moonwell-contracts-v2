# MIP-B41: Add VIRTUAL Market to Moonwell on Base

## Summary

This proposal seeks to onboard $VIRTUAL, the governance and utility token of the
[Virtuals Protocol](https://app.virtuals.io/), as a new collateral asset on
Moonwell’s Base deployment. $VIRTUAL powers the onchain co-ownership of AI
agents, enabling tokenized interactions across Base and Ethereum while aligning
incentives for participants in the AI agent economy. Adding $VIRTUAL to Moonwell
introduces an innovative, high-utility asset tied to the rapidly expanding
onchain AI sector. For additional details, please review the
[Virtuals Protocol documentation](https://docs.virtuals.io) and the
[Virtuals asset listing forum post](https://forum.moonwell.fi/t/virtual-asset-listing/1505/).

## Token Information

- **Name:** VIRTUAL
- **Token Standard:** ERC20
- **Total Supply:** 1,000,000,000 VIRTUAL
- **Circulating Supply (Base):** 486,900,666 VIRTUAL
- **Token Contract:**
  [0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b](https://basescan.org/token/0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b)
- **Price Feed:**
  [Chainlink VIRTUAL/USD](https://basescan.org/address/0xEaf310161c9eF7c813A14f8FEF6Fb271434019F7)

## Gauntlet's Risk Analysis and Recommendations

### Initial Risk Parameters

| **Parameter**          | **Value**         |
| ---------------------- | ----------------- |
| Collateral Factor (CF) | 65%               |
| Supply Cap             | 4,500,000 VIRTUAL |
| Borrow Cap             | 2,300,000 VIRTUAL |
| Protocol Seize Share   | 30%               |
| Reserve Factor         | 30%               |

### Interest Rate Model

| **Parameter**   | **Value** |
| --------------- | --------- |
| Base Rate       | 0%        |
| Multiplier      | 23%       |
| Jump Multiplier | 5x        |
| Kink            | 45%       |

#### Interest Rate Curve

| **Utilization** | **Borrow APR** | **Supply APR** |
| --------------- | -------------- | -------------- |
| 0%              | 0%             | 0%             |
| 45% (Kink)      | 10.35%         | 3.26%          |
| 100%            | 285.35%        | 199.7%         |

Gauntlet recommends an IR curve with a borrow APR of 10.35% at kink.

### Supporting Data

- **Volatility:** Over the past 180 days, VIRTUAL’s daily log returns ranged
  from +102.88% to -36.8%. The annualized 30-day log volatility stands at
  246.93%, indicating extended periods of high price fluctuation. In light of
  this volatility, Gauntlet recommends setting the Collateral Factor at a more
  conservative 65%.
- **Liquidity:** The total DEX TVL of VIRTUAL on Base currently stands at $132M.
  However, we’ve discounted other sources of liquidity such as AGENT-VIRTUAL
  pairs. Virtuals'
  [recent announcement](https://x.com/virtuals_io/status/1883107553183162507) of
  its expansion to Solana may introduce short-term variance to DEX TVL on Base.

### Liquidity Sources

| **Exchange**         | **Pair**             | **TVL (USD)** | **24H Volume (USD)** |
| -------------------- | -------------------- | ------------- | -------------------- |
| Aerodrome (Base)     | VIRTUAL / cbBTC      | $34.6M        | $7.93M               |
| Aerodrome (Base)     | VIRTUAL / WETH       | $34.6M        | $2.39M               |
| Uniswap V2 (Base)    | VIRTUAL / WETH       | $11.96M       | $10.99M              |
| Aerodrome Slipstream | VIRTUAL / WETH 0.7%  | $4.76M        | $17.19M              |
| Uniswap V3 (Base)    | VIRTUAL / WETH 0.3%  | $2.44M        | $2.36M               |
| Uniswap V3 (Base)    | VIRTUAL / WETH 0.05% | $2.07M        | $23.29M              |
| Aerodrome Slipstream | VIRTUAL / WETH 0.05% | $0.49M        | $11.77M              |

## Voting Options

- **Aye:** Approve the proposal to activate a core lending market for $VIRTUAL
  on Base with Gauntlet's specified initial risk parameters.
- **Nay:** Reject the proposal.
- **Abstain:** Abstain from voting on this proposal.
