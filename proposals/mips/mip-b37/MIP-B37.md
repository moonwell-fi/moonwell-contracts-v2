# MIP-B37: Add WELL Market to Moonwell on Base

## Summary

This proposal seeks to onboard WELL, Moonwell's governance token, as a new
collateral asset on Moonwell's Base deployment. WELL serves as a foundational
component of the Moonwell ecosystem, playing a critical role in enabling
decentralized governance, incentivizing liquidity providers across Core Markets
and Morpho Vaults, and rewarding Safety Module stakers who help to backstop the
protocol against potential shortfall events. By activating a market for WELL on
Base we can strengthen token liquidity, create new lending and borrowing
opportunities, and foster further engagement with the Moonwell ecosystem.

## For additional details, please review the [WELL token documentation](https://docs.moonwell.fi/moonwell/moonwell-overview/tokens) and [WELL asset listing forum post](https://forum.moonwell.fi/t/well-asset-listing/1442).

## Token Information

**Name:** WELL **Token Standard:** [xERC20](https://www.xerc20.com/) **Total
Supply:** 5,000,000,000 **Circulating Supply:** 3,142,645,838 **Token
Contract:**
[0xA88594D404727625A9437C3f886C7643872296AE](https://basescan.org/token/0xa88594d404727625a9437c3f886c7643872296ae)
**Price Feed:**
[Chainlink WELL/USD](https://basescan.org/address/0xc15d9944daefe2db03e53bef8dda25a56832c5fe)

---

## Gauntlet's Risk Analysis and Recommendations

### Initial Risk Parameters

| Parameter              | Value               |
| ---------------------- | ------------------- |
| Collateral Factor (CF) | 65%                 |
| Supply Cap             | 75,000,000 (~$4.7M) |
| Borrow Cap             | 37,500,000 (~$2.3M) |
| Protocol Seize Share   | 3%                  |
| Reserve Factor         | 0.25                |

### Interest Rate Model

| Parameter       | Base Value |
| --------------- | ---------- |
| Base Rate       | 0          |
| Kink            | 0.45       |
| Multiplier      | 0.22       |
| Jump Multiplier | 3          |

### Supporting Data

Gauntlet conducted a detailed risk analysis to define these recommendations
based on WELL's volatility and market liquidity:

- **Volatility & Max Drawdown:** The maximum and minimum daily log returns for
  WELL are 21% and -22.93% respectively over the past 180 days. Given the
  volatility exhibited by WELL we recommend that Collateral Factor to align with
  that of AERO. We therefore recommend a CF of 65%

- **Supply and Borrow Caps:** Borrow and supply caps are the primary parameter
  recommendations we can make to mitigate protocol risk when listing new assets.
  Gauntlet recommends setting the borrow and supply caps strategically with
  available liquidity on-chain. On Base, there is sufficient liquidity to trade
  upto 75M worth of WELL tokens with a slippage of 25% signalling a maximum cap
  setting of WELL tokens at this level. We recommend setting the borrow cap at
  37.5M accordingly to adjust for kink level and provide sufficient buffer to
  prevent any governance exploits given the quorum requirements.

- **Interest Rate Curve:** | Utilization | Borrow APR | Supply APR | |
  ----------- | ---------- | ---------- | | 0% | 0% | 0% | | 45% | 9.9% | 3.3% |
  | 100% | 174.4% | 131.3% |

The interest rate curve features a kink at 45%, ensuring competitive rates while
incentivizing balanced utilization.

---

## Voting Options

- **Aye:** Approve the proposal to activate a core lending market for WELL on
  Base with Gauntlet's specified initial risk parameters.
- **Nay:** Reject the proposal.
- **Abstain:** Abstain from voting on this proposal.
