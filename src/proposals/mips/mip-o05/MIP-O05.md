# MIP-O05: Add weETH and VELO Markets on Optimism

## Summary

This proposal aims to add weETH (Wrapped eETH) and VELO as new markets on
Moonwell's Optimism deployment. weETH is the non-rebasing equivalent of eETH, a
liquid restaking token from [Ether.fi](https://ether.fi), representing ETH
staked on the Beacon Chain. Additionally, this proposal aims to activate a new
market for VELO, the utility token of [Velodrome](https://velodrome.finance), to
Moonwell's Optimism deployment. VELO was
[previously proposed](https://forum.moonwell.fi/t/activate-moonwell-protocol-on-optimism/1045)
as an initial launch market for Moonwell on Optimism, but was inadvertently not
included in the activation proposals
([MIP-O00](https://moonwell.fi/governance/proposal/moonbeam?id=106) and
[MIP-O01](https://moonwell.fi/governance/proposal/moonbeam?id=107)). MIP-O05
seeks to rectify this issue by activating the VELO market with weETH.

## Proposal Details

We propose adding weETH and VELO as new collateral assets on the Moonwell
Optimism deployment with the following details:

**weETH**

- Asset: weETH (Wrapped eETH)
- Address: [Confirm Address]
- Oracle Feed:
  [weETH/ETH](https://optimistic.etherscan.io/address/0xb4479d436DDa5c1A79bD88D282725615202406E3)
- Composite Oracle Feed: [weETH/ETH](https://optimistic.etherscan.io/address/
  TODO FILL THIS IN )

**VELO**

- Asset: Velodrome v2 (VELO)
- Address:
  [0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db](https://optimistic.etherscan.io/token/0x9560e827af36c94d2ac33a39bce1fe78631088db)
- Oracle Feed:
  [VELO/USD](https://optimistic.etherscan.io/address/0x0f2Ed59657e391746C1a097BDa98F2aBb94b1120)

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
  [Ether.fi documentation](https://etherfi.gitbook.io/etherfi)
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
| Supply Cap           | 5     |
| Borrow Cap           | 0     |
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

- For: Approve the addition of weETH and VELO as new markets on Moonwell's
  Optimism deployment
- Against: Reject the addition of weETH and VELO as new markets on Moonwell's
  Optimism deployment
- Abstain
