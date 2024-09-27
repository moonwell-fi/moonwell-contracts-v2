# MIP-B31: Add Support for EURC Rewards

## Simple Summary

We propose adding support for EURC reward streams on Moonwell's Base deployment,
enabling [EURC Core market](https://moonwell.fi/markets/supply/base/eurc)
suppliers and borrowers to receive EURC rewards.

## Details

Currently, Moonwell's deployment on Base supports both WELL and USDC reward
streams across its Core markets. Moonwell utilizes a
[MultiRewardDistributor contract](https://basescan.org/address/0xe9005b078701e2A0948D2EaC43010D35870Ad9d2)
which allows for additional reward streams to be added through governance,
enabling support for new reward tokens. With this proposal, like with
[MIP-B07](https://moonwell.fi/governance/proposal/moonbeam?id=55) which added
support for USDC reward streams, we aim to introduce EURC reward streams to the
protocol.

EURC reward streams will provide both suppliers and borrowers in the EURC core
market with EURC-denominated rewards. The initial configuration will allocate
emissions as follows:

| Market | EURC (Supply)       | EURC (Borrow)       |
| ------ | ------------------- | ------------------- |
| EURC   | 0.004538 per second | 0.003025 per second |

In total, **25,000 EURC will be distributed over 38 days and 6 hours (38.25
days)**, split between supply and borrow incentives. The emissions per second
are designed to distribute rewards consistently throughout this period.

**Start Time**: `September 23, 2024, 21:30:00 UTC`  
**End Time**: `November 1, 2024, 03:30:00 UTC`

## Voting Options

- **Yay**: I support adding EURC reward streams to Moonwell's Base deployment.
- **Nay**: I oppose adding EURC reward streams to Moonwell's Base deployment.
- **Abstain**: I decline to vote either for or against this proposal.
