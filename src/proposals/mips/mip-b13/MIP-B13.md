# MIP-B13: Add Support for Optimism Reward Streams

## Simple Summary
We are proposing to add support for native Optimism token reward streams on Moonwell's deployment on Base.

## Details
Currently, Moonwell's deployment on Base strictly supports WELL and USDC reward streams. This proposed update will add the Optimism token as an eligible reward stream to further incentivize market utilization.

Optimism tokens were granted to the Moonwell community from RetroPGF Round 3, these tokens will be utilized as liquidity incentives, these new reward streams would allow for suppliers and borrowers on all Base markets to receive Optimism denominated rewards.

### Reward stream will be initialized with following configuration:

| Market    | Supply emissions per sec (OP) | Borrow emissions per sec (OP) |
|-----------|--------------------------------|---------------------------------|
| DAI       | 0                              | 1                               |
| USDC      | 0                              | 1                               |
| USDbC     | 0                              | 1                               |
| ETH       | 0                              | 1                               |
| rETH      | 0                              | 1                               |
| cbETH     | 0                              | 1                               |
| wstETH    | 0                              | 1                               |

**Note:** that in order to avoid smart contract issues, borrow-side reward speeds must be greater than 0.

Additionally, upon the passage of the present proposal, Warden Finance will be granted permissions to set allocations for this new rewards stream as part of the [emissions manager role](https://forum.moonwell.fi/t/warden-finance-moonwell-base-rewards-optimization/577).
