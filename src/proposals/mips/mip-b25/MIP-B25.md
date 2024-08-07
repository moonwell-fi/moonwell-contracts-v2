# MIP-B25: Add weETH Market on Base

## Summary

This proposal aims to add weETH (Wrapped eETH) as a new market on Moonwell's
Base deployment. weETH is the non-rebasing equivalent of eETH, a liquid
restaking token from [Ether.fi](https://ether.fi), representing ETH staked on
the Beacon Chain.

## Proposal Details

We propose adding weETH as a new collateral asset on the Moonwell Base
deployment with the following details:

- Asset: weETH (Wrapped eETH)
- Address:
  [0x04c0599ae5a44757c0af6f9ec3b93da8976c150a](https://basescan.org/address/0x04c0599ae5a44757c0af6f9ec3b93da8976c150a#code)
- Oracle Feed:
  [weETH/ETH](https://basescan.org/address/0xFC1415403EbB0c693f9a7844b92aD2Ff24775C65)
- Composite Oracle Feed:
  [weETH/ETH/USD](https://basescan.org/address/0xe44b816FE6bc5047C22b9fA5e4D4c5c9747476b3)

### About weETH and Ether.fi

Ether.fi is a decentralized, non-custodial liquid staking protocol built on
Ethereum. weETH is the wrapped, non-rebasing version of eETH, which represents
ETH staked on the Beacon Chain and accrues daily staking rewards.

Key points:

- Users can deposit ETH to mint eETH, which can be wrapped into weETH
- ETH staked through Ether.fi accrues normal Ethereum staking rewards and is
  natively restaked with EigenLayer
- The eETH contract has been live since June 2023, with weETH launching in
  November 2023
- Approximately 1,814,766.66 ETH is held within the contract

### Benefits to the Moonwell Community

1. Enhanced liquidity for weETH on Base
2. Users can earn Ether.fi points and Eigenlayer points while supplying and
   borrowing against weETH
3. Increased DeFi opportunities for Moonwell users on Base

### Security and Smart Contract Information

- Multiple audits performed (details available in
  [Ether.fi documentation](https://etherfi.gitbook.io/etherfi))
- Active bug bounty program
- DAO Governance with 3-day timelock before onchain upgrades/updates can be
  executed

### Gauntlet Risk Parameter Recommendations

Gauntlet, Moonwell's lead risk manager, has provided the following risk
parameters for the weETH market:

#### Risk Parameters

| Parameter            | Value |
| -------------------- | ----- |
| Collateral Factor    | 74%   |
| Supply Cap           | 1950  |
| Borrow Cap           | 780   |
| Protocol Seize Share | 30%   |

#### Interest Rate Parameters

| IR Parameter    | Recommended Value |
| --------------- | ----------------- |
| Base            | 0                 |
| Kink            | 0.35              |
| Multiplier      | 0.15              |
| Jump Multiplier | 4.5               |
| Reserve Factor  | 0.15              |

## Voting Options

- For: Approve the addition of weETH as a new market on Moonwell's Base
  deployment
- Against: Reject the addition of weETH as a new market on Moonwell's Base
  deployment
- Abstain
