# MIP-O04: Add VELO Market on Optimism

## Summary

This proposal aims to activate a new market for VELO, the utility token of
[Velodrome](https://velodrome.finance), to Moonwell's Optimism deployment. VELO
was
[previously proposed](https://forum.moonwell.fi/t/activate-moonwell-protocol-on-optimism/1045)
as an initial launch market for Moonwell on Optimism, but was inadvertently not
included in the activation proposals
([MIP-O00](https://moonwell.fi/governance/proposal/moonbeam?id=106) and
[MIP-O01](https://moonwell.fi/governance/proposal/moonbeam?id=107)). MIP-MO03
seeks to rectify this issue by activating a new VELO market through a bespoke
Moonwell Improvement Proposal.

## Market Details

We propose adding VELO as a new collateral asset on Moonwell's Optimism
deployment:

- Asset: Velodrome v2 (VELO)
- Address:
  [0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db](https://optimistic.etherscan.io/token/0x9560e827af36c94d2ac33a39bce1fe78631088db)
- Oracle Feed:
  [VELO/USD](https://optimistic.etherscan.io/address/0x0f2Ed59657e391746C1a097BDa98F2aBb94b1120)

This addition aligns with the original intent of including VELO in the initial
set of markets for Moonwell's Optimism deployment.

### Market Parameters

Gauntlet, Moonwell's lead risk manager, has provided updated risk parameters for
the VELO market in their risk parameter
[recommendation proposal](https://forum.moonwell.fi/t/gauntlet-base-optimism-moonbeam-moonriver-monthly-recommendations-2024-08-01/1151/2?),
ensuring that the VELO market is integrated with appropriate risk
considerations.

| Parameter         | Value     |
| ----------------- | --------- |
| Collateral Factor | 65%       |
| Reserve Factor    | 25%       |
| Seize Share       | 3%        |
| Supply Cap        | 9,000,000 |
| Borrow Cap        | 4,500,000 |

| IR Parameters   | VELO |
| --------------- | ---- |
| Base            | 0.02 |
| Kink            | 0.45 |
| Multiplier      | 0.1  |
| Jump Multiplier | 3.15 |

## Voting Options

We propose the following voting options for the Moonwell community:

- For: Approve the activation of a VELO market on Moonwell's Optimism deployment
- Against: Reject the activation of a VELO market on Moonwell's Optimism
  deployment
- Abstain
