# MIP-B07: Add Support for USDC Reward Streams

## Simple Summary

We are proposing to add support for native USDC reward streams on Moonwell's
deployment on Base.

## Details

Currently, Moonwell's deployment on Base strictly supports WELL reward streams.
This proposed update will bring Moonwell's Base deployment in line with the
deployments on Moonbeam and Moonriver, both of which support multiple reward
streams (WELL/GLMR and MFAM/MOVR).

In the case of native USDC being granted to the Moonwell community to be
utilized as liquidity incentives, these new reward streams would allow for
suppliers and borrowers on all Base markets to receive USDC denominated rewards.

### Reward stream will be initialized with following configuration:

| Market | Supply emissions per sec (USDC) | Borrow emissions per sec (USDC) |
| ------ | ------------------------------- | ------------------------------- |
| USDC   | 0                               | 1                               |
| USDbC  | 0                               | 1                               |
| DAI    | 0                               | 1                               |
| ETH    | 0                               | 1                               |
| cbETH  | 0                               | 1                               |

**Note:** that in order to avoid smart contract issues, borrow-side reward
speeds must be greater than 0.

Additionally, upon the passage of the present proposal, Warden Finance will be
granted permissions to set allocations for this new rewards stream as part of
the
[emissions manager role](https://forum.moonwell.fi/t/warden-finance-moonwell-base-rewards-optimization/577).
