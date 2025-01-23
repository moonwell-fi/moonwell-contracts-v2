# MIP-B38: Add USDS Market to Moonwell on Base

## Summary

This proposal seeks to onboard [USDS](https://sky.money/), the stablecoin of Sky
Protocol, as a new collateral asset on Moonwell’s Base deployment. USDS is a
decentralized and overcollateralized stablecoin designed to maintain a soft peg
to the U.S. dollar. With seamless 1:1 conversions to DAI and integration into
the Sky Protocol ecosystem, USDS provides users with a robust, stable, and
permissionless asset for lending, borrowing, and liquidity provisioning. Adding
USDS to Moonwell will enhance stablecoin liquidity, attract new users from the
Sky Protocol community, and create synergies with Ethereum's broader DeFi
ecosystem. The stablecoin’s strong foundation, including decentralized
governance and backing by surplus collateral, ensures reliability and security
for all users. This proposal aligns with Moonwell’s mission to deliver simple,
secure, and accessible onchain financial tools. For additional details, please
review the [USDS token documentation](https://sky-protocol.org/docs) and
[USDS asset listing forum post](https://forum.moonwell.fi/t/usds-asset-listing/1485/).

## Token Information

- **Name:** USDS
- **Token Standard:** ERC20
- **Total Supply:** ∞ (uncapped)
- **Circulating Supply (Base):** 100,338,559.43
- **Token Contract:**
  [0x820C137fa70C8691f0e44Dc420a5e53c168921Dc](https://basescan.io/address/0x820C137fa70C8691f0e44Dc420a5e53c168921Dc)
- **Price Feed:**
  [Chainlink USDS/USD](https://basescan.org/address/0x2330aaE3bca5F05169d5f4597964D44522F62930)

## Benefits to the Moonwell Community

1. **Enhanced Stablecoin Liquidity:** Expands Moonwell’s stablecoin offerings,
   fostering new lending and borrowing opportunities.
2. **Increased Protocol Engagement:** Attracts users from the Sky Protocol
   ecosystem, including those leveraging the Sky Savings Rate for decentralized
   rewards.
3. **Decentralization Alignment:** Provides a permissionless, non-custodial
   stablecoin option aligned with DeFi principles.
4. **Reduced Systemic Risk:** Backed by surplus collateral and supporting 1:1
   conversions with DAI, USDS offers a reliable, decentralized stablecoin
   solution.

## Gauntlet's Risk Analysis and Recommendations

### Initial Risk Parameters

| **Parameter**          | **Value**    |
| ---------------------- | ------------ |
| Collateral Factor (CF) | 83%          |
| Supply Cap             | 750,000 USDS |
| Borrow Cap             | 690,000 USDS |
| Protocol Seize Share   | 30%          |
| Reserve Factor         | 10%          |

### Interest Rate Model

| **Parameter**   | **Value** |
| --------------- | --------- |
| Base Rate       | 0%        |
| Multiplier      | 6.7%      |
| Jump Multiplier | 9x        |
| Kink            | 90%       |

#### Interest Rate Curve

| **Utilization** | **Borrow APR** | **Supply APR** |
| --------------- | -------------- | -------------- |
| 0%              | 0%             | 0%             |
| 90% (Kink)      | 6.03%          | 4.88%          |
| 100%            | 96%            | 86.4%          |

The interest rate curve features a kink at 90%, ensuring competitive rates while
incentivizing stable utilization.

## Supporting Data

- **Volatility:** Annualized 30-day log volatility of 11.82% reflects USDS’s
  convergence to its underlying value.
- **Liquidity:** Sufficient on-chain liquidity exists to trade up to 1M USDS
  with ~27% slippage. Initial supply and borrow caps are set conservatively,
  with future adjustments based on market evolution.

## Voting Options

- **Aye:** Approve the proposal to activate a core lending market for USDS on
  Base with Gauntlet's specified initial risk parameters.
- **Nay:** Reject the proposal.
- **Abstain:** Abstain from voting on this proposal. (editado)
