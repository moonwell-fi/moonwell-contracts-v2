# Proposal: Onboard wstETH as collateral on Base deployment

## Summary

We propose onboarding wstETH as collateral on Moonwell Base deployment conditional to the token being available on Base
and significant liquidity being onboarded subsequently on DEXes.

## Specifications

We propose using the same collateral factor and interest rate model as cbETH. We will provide further recommendations in
regards to supply and borrow caps once liquidity is available on Base chain.

### Market parameters

| Symbol                                                                               | Price oracle                         | CF   | Borrow Cap | Supply Cap |
| ------------------------------------------------------------------------------------ | ------------------------------------ | ---- | ---------- | ---------- |
| [wstETH](https://basescan.org/token/0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452#code) | Chainlink (wstETH / ETH + ETH / USD) | 0.75 | 0.05       | 0.1        |

### Interest rate model

| Parameter | Base rate | Multiplier | Kink | Jump Multiplier | Reserve factor |
| --------- | --------- | ---------- | ---- | --------------- | -------------- |
| Value     | 0.00      | 0.07       | 0.45 | 3.15            | 0.25           |

| Key utilization rate | Base (0%) | Kink (45%) | Max (100%) |
| -------------------- | --------- | ---------- | ---------- |
| Supply rate          | 0%        | 1.06%      | 132.30%    |
| Borrow rate          | 0%        | 3.15%      | 176.40%    |

![|624x387](https://i.imgur.com/95AcDHc.png"Chart") As part of our role of managing
[Base liquidity incentives](https://forum.moonwell.fi/t/warden-finance-base-liquidity-incentives/608), we will also
allocate supply-side rewards once wstETH market is deployed to help bootstrap initial liquidity. We will provide further
details regarding rewards once more liquidity is available for wstETH on Base.

## Analysis

### LST Market Overview

Lido is by far the most dominant LST solution available. It is the most liquid option available on-chain.

| Protocol                         | stETH<br/>Lido                                  | rETH<br/>Rocket Pool                     | Binance staked ETH             | frxETH<br/>Frax             | cbETH<br/>Coinbase              |
| -------------------------------- | ----------------------------------------------- | ---------------------------------------- | ------------------------------ | --------------------------- | ------------------------------- |
| TVL                              | 8.86m ($15.95b)                                 | 997k ($1.8b)                             | 767k ($1.38b)                  | 284k ($513m)                | 192k ($364m)                    |
| Market share                     | 77.3%                                           | 8.69%                                    | 6.67%                          | 2.48%                       | 1.67%                           |
| Operators                        | Centralized<br/>36 entities approved by Lido    | Decentralized<br/>2204 deposit addresses | Centralized<br/>Ran by Binance | Centralized<br/>Ran by Frax | Centralized<br/>Ran by Coinbase |
| LSD Over-collateralization       | Slashing insurance fund<br/>6.2k stETH ($11.2M) | Yes<br/>Staked RPL                       | No                             | Slashing insurance fund     | No                              |
| Fee                              | 10%                                             | 5-20%                                    | 10%                            | 10%                         | 25%                             |
| Correlation penalty risk profile | High                                            | Low                                      | High                           | Medium                      | High                            |
| Quadratic leaking risk profile   | High                                            | Low                                      | High                           | Medium                      | High                            |

### Past Performance

| Protocol                    | stETH<br/>Lido              | rETH<br/>Rocket Pool      | Binance staked ETH         | frxETH<br/>Frax           | cbETH<br/>Coinbase        |
| --------------------------- | --------------------------- | ------------------------- | -------------------------- | ------------------------- | ------------------------- |
| Launch date                 | Dec 18 2020<br/>(1049d ago) | Nov 9 2021<br/>(723d ago) | Apr 27 2023<br/>(189d ago) | Oct 7 2022<br/>(391d ago) | May 3 2021<br/>(913d ago) |
| Slashing Events             | 31<br/>(2.99 / 100 days)    | 8<br/>(1.11 / 100 days)   | 0                          | 0                         | 0                         |
| Consensus Rewards Earned    | 394k ETH                    | 25k ETH                   | 119k ETH                   | 4.4k ETH                  | 221k ETH                  |
| Total Penalties Accrued     | -1.3k ETH                   | -300 ETH                  | 502 ETH                    | -7 ETH                    | -858 ETH                  |
| Percent Loss from Penalties | 0.37%                       | 1.20%                     | 0.42%                      | 0.16%                     | 0.39%                     |

Source: [Rated.network](https://www.rated.network/?network=mainnet&view=pool&timeWindow=1d&page=1&poolType=all) | Date:
3/11/2023

### LST-specific Risk

Validators are rewarded for contributing to the chain's security, and penalized for failing to contribute.
https://eth2book.info/capella/part2/incentives/penalties/

#### Correlation penalty risk

Correlation penalty is incurred when a validator is [slashed](https://eth2book.info/capella/part2/incentives/slashing/).
The penalty amount is determined based on the amount of validators that also get slashed at the same moment.

Lido is subject to incurring increased correlation penalty due to the relatively large number of validators managed by
individual operators.

#### Quadratic leaking risk profile

Quadratic leak is a penalty that is imposed upon validators for being offline and missing a slot. The more often a
validator is offline, the steeper the penalty rate is.

Quadratic leak is also a risk factor for stETH due to the lack of diversity in operators.

#### Insurance fund

In July 2021, the Lido DAO voted to take on self-insurance by allocating a proportion of funds - in the form of protocol
fees - for insurance purposes.

The insurance fund could be used, as an example, to compensate stakers in the case of slashings (or other risk scenarios
outlined
[here](https://research.lido.fi/t/redirecting-incoming-revenue-stream-from-insurance-fund-to-dao-treasury/2528/21?u=kadmil)).

### Volatility Risk

Volatility can be described as a measure of the amplitude of price changes for an asset over time. Overcollateralized
lending protocols like Moonwell are subject to volatility risks. As collateral and debt asset prices change, the
collateralization of accounts changes.

In order to assess robustness of the suggested parameters, we’ll assume a worst case scenario where wstETH asset price
drops down as much as the worst 1-hour price drawdown observed for ETH during the last year.

Max drawdown over the last year for ETH is 9.01%.

![|624x224](https://i.imgur.com/PSWWo3O.png)![|624x357](https://i.imgur.com/2OEUMus.png)

### Liquidity Risk

wstETH is not yet launched on Base. We will provide more information once data is available.

### Oracle Risk

Oracle risk is the probability of the oracle price feed not accurately tracking the actual market price.

Given the lack of historical data for the proposed oracle price feed on Base (Chainlink wstETH/ETH + ETH/USD), we’ll
assume that skew between oracle and spot price should be similar to wstETH on Optimism given an equivalent oracle setup.

During the last 90d, for a similar oracle price feed on Optimism, 99.7% of observed oracle price skew data points are
within [-0.689%, 0.817%].

As a conservative measure, we’ll assume 1% skew in a worst case scenario for wstETH on Base.

![|624x448](https://i.imgur.com/sCHnJJL.png)

## Robustness Test

In order to validate the robustness of the liquidation incentive, collateral factor and caps our methodology relies on
backtesting the profitability of simulated liquidations given historical market conditions. More information about our
methodology is available on [Warden’s documentation](https://docs.warden.finance/docs/).

![|624x383](https://i.imgur.com/HH5cWJV.png)

Assuming the following historical market conditions:

| Liquidation cost         | % of seized collateral              |
| ------------------------ | ----------------------------------- |
| Max drawdown 60min       | 9.05%                               |
| Slippage                 | TBD depending on liquidity and caps |
| Protocol reserve fee     | 3%                                  |
| Oracle / spot price skew | 1%                                  |
| Gas fees                 | 0%                                  |

The buffers necessary for the liquidation to execute profitably can then be determined:

-   Collateral factor needs to provide sufficient buffer to cover for
    -   9.05% drawdown
    -   10% liquidation incentive.
-   Liquidation incentive need to provide sufficient buffer to cover for
    -   3% reserve fee
    -   1% oracle / spot price skew
    -   TBD slippage

Given above assumptions and liquidation incentive for Moonwell Base deployment set to 10%:

-   Collateral factor must be less than 0.81
-   Liquidation incentive offers tolerance for up to 6% slippage cost in a worst case scenario.
-   Borrow and supply caps must be set low enough to prevent users from holding collateral or debt positions that
    increase the risk for the protocol of accumulating bad debt (>6% slippage when liquidated).

The suggested collateral factor (0.75) and current liquidation incentive (10%) pass the above robustness test. We will
follow up with borrow and supply caps once we have sufficient data to provide recommendations.

### Interest Rate Model

The suggested interest rate model aims to

-   Facilitate borrowing wstETH considering additional borrowing cost due to staking yield (~3.8%)
-   Attract more suppliers when liquidity risk is high. Higher borrow rates above the kink incentivize borrowers to
    repay their loans and can attract new lenders in order to maximize liquidity at all times.

## References

-   Warden Finance - wstETH on Optimism dashboard: https://warden.finance/tokens/wstETH?chain=optimism
-   Warden Finance - wstETH on Optimism - Backtesting Simulation:
    https://warden.finance/liquidation-backtesting/1187eeab-5d90-47fb-8c2f-046ed34bd3e5
-   DefiLlama - LSD Dashboard: https://defillama.com/lsd
-   Rated network: https://www.rated.network/
