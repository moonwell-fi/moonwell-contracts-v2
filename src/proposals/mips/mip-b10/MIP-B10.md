# MIP-B10 - Onboard rETH as collateral on Base deployment

## Summary

Warden proposes onboarding rETH as collateral on Moonwell Base deployment.

## Specifications

|Asset|Price oracle|CF|Supply Cap|Borrow Cap|
| --- | --- | --- | --- | --- |
|[rETH](https://basescan.org/token/0xb6fe221fe9eef5aba221c348ba20a1bf5e73624c) (Base native bridge)|Chainlink (rETH / ETH + ETH / USD)|0.76|100|50|

|Interest rate model|Base rate|Multiplier|Kink|Jump Multiplier|Reserve factor|Close Factor|
| --- | --- | --- | --- | --- | --- | --- |
|LST|0.00|0.07|0.45|3.15|0.25|0.5|

|Key utilization rate|Base (0%)|Kink (45%)|Max (100%)|
| --- | --- | --- | --- |
|Supply rate|0%|1.06%|132.30%|
|Borrow rate|0%|3.15%|176.40%|

As part of our role of managing [Base liquidity incentives](https://forum.moonwell.fi/t/warden-finance-base-liquidity-incentives/608), we will also allocate supply-side rewards once rETH market is deployed to help bootstrap initial liquidity. We will provide further details regarding rewards once market is closer to be deployed. 

<img src="https://i.imgur.com/1CTYiYo.png" width="600px" />


## Analysis

### LST Market Overview

Rocket pool is a decentralized and trustless ETH staking solution. Specific information about the protocol is available on [Rocket Pool’s documentation](https://docs.rocketpool.net/overview/faq.html#what-does-rocket-pool-do).

Rocket Pool is currently the most adopted and liquid decentralized LST available on the market, which makes it a good candidate to use as collateral asset on lending protocols.


<table>
  <tr>
   <td>Protocol
   </td>
   <td><strong>rETH</strong>
<strong>Rocket Pool</strong>
   </td>
   <td>stETH
Lido
   </td>
   <td>Binance staked ETH
   </td>
   <td>frxETH
Frax
   </td>
   <td>cbETH
Coinbase
   </td>
  </tr>
  <tr>
   <td>TVL
   </td>
   <td><strong>997k ($1.8b)</strong>
   </td>
   <td>8.86m ($15.95b)
   </td>
   <td>767k ($1.38b)
   </td>
   <td>284k ($513m)
   </td>
   <td>192k ($364m)
   </td>
  </tr>
  <tr>
   <td>Market share
   </td>
   <td><strong>8.69%</strong>
   </td>
   <td>77.3% 
   </td>
   <td>6.67%
   </td>
   <td>2.48%
   </td>
   <td>1.67% 
   </td>
  </tr>
  <tr>
   <td>Operators
   </td>
   <td><strong>Decentralized</strong>
<strong>2204 deposit addresses</strong>
   </td>
   <td>Centralized
36 entities approved by Lido
   </td>
   <td>Centralized
Ran by Binance
   </td>
   <td>Centralized
Ran by Frax
   </td>
   <td>Centralized
Ran by Coinbase
   </td>
  </tr>
  <tr>
   <td>LSD Over-collateralization
   </td>
   <td><strong>Yes</strong>
<strong>Staked RPL</strong>
   </td>
   <td>Slashing insurance fund
6.2k stETH ($11.2M)
   </td>
   <td>No
   </td>
   <td>Slashing insurance fund
   </td>
   <td>No
   </td>
  </tr>
  <tr>
   <td>Fee
   </td>
   <td><strong>5-20%</strong>
   </td>
   <td>10%
   </td>
   <td>10%
   </td>
   <td>10%
   </td>
   <td>25%
   </td>
  </tr>
  <tr>
   <td>Correlation penalty risk profile
   </td>
   <td><strong>Low</strong>
   </td>
   <td>High
   </td>
   <td>High
   </td>
   <td>Medium
   </td>
   <td>High
   </td>
  </tr>
  <tr>
   <td>Quadratic leaking risk profile
   </td>
   <td><strong>Low</strong>
   </td>
   <td>High
   </td>
   <td>High
   </td>
   <td>Medium
   </td>
   <td>High
   </td>
  </tr>
</table>

### Past Performance

<table>
  <tr>
   <td>Protocol
   </td>
   <td><strong>rETH</strong>
<strong>Rocket Pool</strong>
   </td>
   <td>stETH
Lido
   </td>
   <td>Binance staked ETH
   </td>
   <td>frxETH
Frax
   </td>
   <td>cbETH
Coinbase
   </td>
  </tr>
  <tr>
   <td>Launch date
   </td>
   <td>Nov 9 2021
(723d ago)
   </td>
   <td>Dec 18 2020
(1049d ago)
   </td>
   <td>Apr 27 2023
(189d ago)
   </td>
   <td>Oct 7 2022
(391d ago)
   </td>
   <td>May 3 2021
(913d ago)
   </td>
  </tr>
  <tr>
   <td>Slashing Events
   </td>
   <td>8
(1.11 / 100 days)
   </td>
   <td>31
(2.99 / 100 days)
   </td>
   <td>0
   </td>
   <td>0
   </td>
   <td>0
   </td>
  </tr>
  <tr>
   <td>Consensus Rewards Earned
   </td>
   <td>25k ETH
   </td>
   <td>394k ETH
   </td>
   <td>119k ETH
   </td>
   <td>4.4k ETH
   </td>
   <td>221k ETH
   </td>
  </tr>
  <tr>
   <td>Total Penalties Accrued
   </td>
   <td>-300 ETH
   </td>
   <td>-1.3k ETH
   </td>
   <td>502 ETH
   </td>
   <td>-7 ETH
   </td>
   <td>-858 ETH
   </td>
  </tr>
  <tr>
   <td>Percent Loss from Penalties
   </td>
   <td>1.20%
   </td>
   <td>0.37%
   </td>
   <td>0.42%
   </td>
   <td>0.16%
   </td>
   <td>0.39%
   </td>
  </tr>
</table>


### LST-specific Risk

<details>
<summary>
About LST-specific risk
</summary>

<hr>

#### Staking incentives and penalties

Validators are rewarded for contributing to the chain's security, and penalized for failing to contribute. More implementation details about incentives/penalties is available over there: https://eth2book.info/capella/part2/incentives/penalties/

The reward, penalty and slashing design of the consensus mechanism encourages individual validators to behave correctly. However, from these design choices emerges a system that strongly incentivizes equal distribution of validators across multiple clients, and should strongly disincentivize single-client dominance.

#### Slashing
Slashing is a more severe action that results in the forceful removal of a validator from the network and an associated loss of their staked ether. There are three ways a validator can be slashed, all of which amount to the dishonest proposal or attestation of blocks:

* By proposing and signing two different blocks for the same slot
* By attesting to a block that "surrounds" another one (effectively changing history)
* By "double voting" by attesting to two candidates for the same block

Correlation penalty is incurred when a validator is [slashed](https://eth2book.info/capella/part2/incentives/slashing/). The penalty amount is determined based on the amount of validators that also get slashed at the same moment. Correlation penalty aims to promote decentralization of validators.

#### Inactivity leak

If the consensus layer has gone more than four epochs without finalizing, an emergency protocol called the "inactivity leak" is activated.

Quadratic leak is a penalty that is imposed upon validators for being offline and missing a slot. The more longer a validator is offline, the steeper the penalty rate is.

#### Insurance

In order to protect stakers funds, protocols may set up some form of insurance to compensate stakers in case of slashings or offline penalties.
<hr>
</details>

#### Correlation penalty risk

Since Rocket Pool ETH relies on a diverse network of independent nodes, it is very unlikely that a significant part of the network gets slashed at the same moment.

#### Quadratic leaking risk profile

Again here, Rocket Pool ETH is less prone to quadratic leaking penalties since node operators are well distributed and highly diversified.

#### Insurance fund

When creating a minipool validator in the protocol, a minimum of 10% of the ETH's value provided by rETH stakers must also be staked in RPL as a security promise to the protocol.

The insurance promise acts as collateral, where if the node operator is penalized heavily or slashed and finishes staking with less than the 24 (or 16) ETH provided by rETH stakers, their collateral is sold for ETH via auction to help compensate the protocol for the missing ETH.

[Source: Rocket Pool docs](https://docs.rocketpool.net/overview/faq.html#:~:text=RPL%20%E2%80%94%20Rocket%20Pool%20Protocol%20Token&text=The%20insurance%20promise%20acts%20as,protocol%20for%20the%20missing%20ETH.)

### Volatility Risk

<details>
<summary>About volatility risk</summary>

<hr>
In order to maintain solvency, the protocol must ensure that debts are always overcollateralized by assets of a higher value. If debts were not overcollateralized, borrowers would be economically incentivized to default on their debt. Defaulting would lead to the creation of bad debts in the system.

In order to mitigate asset volatility risk, the protocol enforces liquidations to ensure that debts are always overcollateralized.

Time to undercollateralization measures the time required during a worst drawdown event for a highly leveraged position to accumulate bad debt . The lower the value, the less time is available for liquidators to clear risky positions.

Our methodology specifies a minimum time to undercollateralization of 60 minutes for assets with healthy liquidity levels to ensure sufficient time is available to profitably liquidate risky positions of large size (i.e 20% of supply cap). Goal of this buffer is to reduce the risk of bad debt accumulating.

<hr>
</details>

The proposed collateral factor of 0.76 for rETH provides a undercollateralization time buffer of 9,865 minutes (6d 20hrs 24min), which is in line with other LST markets on Moonwell Base.

Given very low and unstable liquidity levels for rETH on Base at the moment,  the proposed collateral factor aims to leave sufficient time for liquidators to profitably liquidate risky positions of large size (i.e $100k rETH collateral position) in a scenario where DEX liquidity is drastically deteriorated.

<table>
  <tr>
   <td>Time to under collateralization analysis
   </td>
   <td><strong>rETH</strong>
   </td>
   <td>cbETH
   </td>
   <td>wstETH
   </td>
  </tr>
  <tr>
   <td>Overcollateralization
<p>
(1 - Collateral Factor)
   </td>
   <td><strong>24%</strong>
   </td>
   <td>24%
   </td>
   <td>25%
   </td>
  </tr>
  <tr>
   <td>Liquidation incentive
   </td>
   <td><strong>10%</strong>
   </td>
   <td>10%
   </td>
   <td>10%
   </td>
  </tr>
  <tr>
   <td>Price drawdown tolerance
   </td>
   <td><strong>14%</strong>
   </td>
   <td>14%
   </td>
   <td>15%
   </td>
  </tr>
  <tr>
   <td>Time to undercollateralization
   </td>
   <td><strong>9,865 min</strong>
   </td>
   <td>10,206 min
   </td>
   <td>10,712 min
   </td>

  </tr>
</table>

<img src="https://i.imgur.com/81tSUAY.png" width="800px" />
<img src="https://i.imgur.com/LRz5Pz2.png" width="600px" />

### Liquidity Risk
<details>
<summary>About liquidity risk</summary>

<hr>

If an account collateral ratio breaches the minimum collateral ratio enforced by the protocol, it will become eligible for liquidation. In order for liquidators to be able to liquidate assets at a reasonable price, there must be sufficient on-chain liquidity for liquidators to liquidate accounts profitably.

Slippage tolerance measures the maximum budget allowed for slippage cost when liquidating a risky position during worst downturn events.

<hr>

</details>

rETH circulating supply on Base is very low, with 197 rETH ($433k) currently in circulation. DEX liquidity is also currently not incentivized and concentrated in a single pool on Balancer, so it is very hard to predict how stable the liquidity will be in the short term.

Given these uncertainties, we recommend starting with a supply cap that is substantially less than circulating supply to avoid outsized positions from joining the market right now while liquidity is sparse.

|Symbol|Circulating supply (Base)|Slippage tolerance|4% depth|Proposed supply cap|Proposed borrow cap|
| --- | --- | --- | --- | --- |--- |
|rETH|197 ($433k)|4% of seized collateral|$150k|100 ($222k)|50 ($111k)|

<img src="https://i.imgur.com/1g9BNif.png" width="600px" />
<img src="https://i.imgur.com/jSuVVAM.png" width="600px" />
<img src="https://i.imgur.com/9EcSG1A.png" width="600px" />
<img src="https://i.imgur.com/dqlYfx9.png" width="800px" />
<img src="https://i.imgur.com/yxzGwC4.png" width="800px" />
<img src="https://i.imgur.com/2uQRfwF.png" width="800px" />
<img src="https://i.imgur.com/n6ywM3g.png" width="800px" />

### Oracle Risk

Oracle risk is the probability of the oracle price feed not accurately tracking the actual market price.

Given the lack of historical data for rETH on Base, we’ll assume that skew between oracle and spot price should have a similar behavior than wstETH on Optimism given an equivalent oracle setup (Chainlink wstETH/ETH + ETH/USD).

During the last 90d, for a similar oracle price feed on Optimism, 99.7% of observed oracle price skew data points are within [-0.689%, 0.817%].

As a conservative measure, we’ll assume 1% skew in a worst case scenario for rETH on Base.

<img src="https://i.imgur.com/ntZjC67.png" width="800px" />

## Interest Rate Model

The suggested interest rate model aims to

* Facilitate borrowing rETH considering additional borrowing cost due to staking yield (~3.12%)
* Attract more suppliers when liquidity risk is high. Higher borrow rates above the kink incentivize borrowers to repay their loans and can attract new lenders in order to maximize liquidity at all times.