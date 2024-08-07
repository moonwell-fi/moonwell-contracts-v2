# MIP-O05: Add weETH Market on Optimism

## Summary

This proposal aims to add weETH (Wrapped eETH) as a new market on Moonwell's
Optimism deployment. weETH is the non-rebasing equivalent of eETH, a liquid
restaking token from [Ether.fi](https://ether.fi), representing ETH staked on
the Beacon Chain.

## Proposal Details

We propose adding weETH as a new collateral asset on the Moonwell Optimism
deployment with the following details:

- Asset: weETH (Wrapped eETH)
- Address:
  [0x5A7fACB970D094B6C7FF1df0eA68D99E6e73CBFF](https://optimistic.etherscan.io/token/0x5A7fACB970D094B6C7FF1df0eA68D99E6e73CBFF)
- Chainlink weETH/ETH Oracle Feed:
  [0xb4479d436DDa5c1A79bD88D282725615202406E3](https://optimistic.etherscan.io/address/0xb4479d436DDa5c1A79bD88D282725615202406E3)
- Chainlink ETH/USD Oracle Feed:
  [0x13e3Ee699D1909E989722E753853AE30b17e08c5](https://optimistic.etherscan.io/address/0x13e3Ee699D1909E989722E753853AE30b17e08c5)
- Chainlink Composite Oracle Feed:
  [0x512CE44e4F69A98bC42A57ceD8257e65e63cD74f](https://optimistic.etherscan.io/address/0x512CE44e4F69A98bC42A57ceD8257e65e63cD74f)
-

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

1. Enhanced liquidity for weETH on Optimism
2. Users can earn Ether.fi points and Eigenlayer points while supplying and
   borrowing against weETH
3. Increased DeFi opportunities for Moonwell users on Optimism

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
| Supply Cap           | 170   |
| Borrow Cap           | 85    |
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

- For: Approve the addition of weETH as a new market on Moonwell's Optimism
  deployment
- Against: Reject the addition of weETH as a new market on Moonwell's Optimism
  deployment
- Abstain
