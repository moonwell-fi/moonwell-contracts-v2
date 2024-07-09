# MIP-B17 Onboard AERO as collateral on Base deployment

## Summary

We propose onboarding AERO as collateral on Moonwell Base deployment. Due to the market demand and growth of AERO
liquidity on Base we think it is appropriate to list the asset.

Gauntlet has conducted a market risk analysis for AERO initial asset listing

Address:
[0x940181a94A35A4569E4529A3CDfB74e38FD98631](https://basescan.org/token/0x940181a94a35a4569e4529a3cdfb74e38fd98631)
Oracle Feed: [AERO/USD](https://basescan.org/address/0x4EC5970fC728C5f65ba413992CD5fF6FD70fcfF0)

## Summary

### Risk Parameter Recommendations

| Parameters           | Values                  |
| -------------------- | ----------------------- |
| CF                   | 0% (Expected 70%)       |
| Supply Cap           | 6,000,000 ($10,000,000) |
| Borrow Cap           | 3,000,000 ($5,000,000)  |
| Protocol Seize Share | 3%                      |

### IR Recommendations

| IR Parameters   | Recommended |
| --------------- | ----------- |
| Base            | 0           |
| Kink            | 0.45        |
| Multiplier      | 0.07        |
| Jump Multiplier | 3.15        |
| Reserve Factor  | 0.25        |

### Supporting Data

**Market Overview**

![Screenshot 2024-04-16 at 4.01.39 PM](https://hackmd.io/_uploads/rJzBPPhlA.png)

| Metric                   | Value        |
| ------------------------ | ------------ |
| Market Cap               | $675,508,415 |
| 30D AVG Volume (CEX+DEX) | $44,710,212  |
| Circulating Supply       | 402,444,318  |
| Herfindahl Index         | 0.0284       |

**Volatility & Max DD**

![Screenshot 2024-04-17 at 11.02.17 AM](https://hackmd.io/_uploads/Bkgd5Gu6eC.png)

The maximum and minimum daily log returns for AERO are 65.5% and -26.6% respectively over the past 60 days. We consider
the minimum daily log returns as a suitable benchmark for setting Collateral Factor, giving the max CF at ~74% however,
to be more conservative we recommend a starting CF of 0% to test the market and expect to reach an ideal state with CF
of 70%.

**TVL**

![Screenshot 2024-04-16 at 4.30.57 PM](https://hackmd.io/_uploads/HJ6M0whxR.png)

The TVL of the protocol has grown exponentially to a total of $1.43bn, Aerodrome is the largest DEX on Base. Gauntlet
deems this TVL adequate to classify AERO as an asset that has inherent value/use cases and to be a listable asset on
Moonwell Base market.

**Supply and Borrow Caps**

![Screenshot 2024-04Fila-16 at 10.20.21 AM](https://hackmd.io/_uploads/HyQSDzngA.png)

Borrow and supply caps are the primary parameter recommendations we can make to mitigate protocol risk when listing new
assets. Gauntlet recommends setting the borrow and supply caps strategically with available liquidity on-chain. There is
sufficient liquidity to trade up to $20M worth of AERO tokens with a slippage of 25% signalling a maximum cap setting of
12M AERO tokens. However, we recommend a more conservative supply cap of 6M AERO tokens and 3M AERO tokens for borrow
cap to bootstrap the market. Gauntlet will continue to monitor these caps and increase them with respect to market
demand and liquidity.

**Token Concentration Risks**

As with governance tokens, there have been incidents (Curve) where large sums of tokens were used as collateral to
borrow on lending protocols. Gauntlet suggests that such risks can be averted by applying conservative Caps along with
using the Herfindahl Index to gauge token concentration across wallets.

The Herfindahl Index serves as a measure of fund concentration within addresses on the network, offering insight into
the distribution of funds among participants. In our context, the "market" encompasses the total supply held in
externally owned accounts (EOAs), while the "market share" denotes the relative balance of each address compared to this
total supply. Consequently, the Herfindahl Index condenses this information into a single value, reflecting the extent
of token concentration across network addresses.

Scoring between 0 and 1, the Herfindahl Index provides a clear indication of supply concentration: higher scores signify
significant concentration, whereas lower scores suggest a more balanced distribution of funds among addresses.
Specifically, it aids in pinpointing tokens where a single entity holds a substantial portion of the token supply.

Our findings show that excluding major smart-contracts that are of either AMM or staking pools, the HI of AERO is
**0.0284** suggesting a more evenly distributed ownership across the network.

### IR Parameter Specifications

**AERO IR Curves**

![Screenshot 2024-04-17 at 10.52.22 AM](https://hackmd.io/_uploads/BkrSguTlR.png)

| Utilization | Borrow APR | Supply APR |
| ----------- | ---------- | ---------- |
| 0%          | 0          | 0          |
| 45%         | 3.15%      | 1.06%      |
| 100%        | 176.4%     | 132.3%     |

We recommend an IR curve similar to other assets on the protocols, with a kink at 45% and borrow APR of 3.15% at kink.

### Conclusion

The addition of AERO to Moonwell Base presents a strategic opportunity to enhance the diversity and robustness of
protocol asset offerings. The risk analysis by Gauntlet, alongside the strong market performance and liquidity of AERO,
supports a favorable risk profile. Implementing this recommendation could drive further integration within the Base
ecosystem, benefiting Moonwell community and stakeholders by providing more options for investment and collateral.

### Voting Options

We propose the following voting options for the Moonwell community:

-   For: Approve the addition of AERO as a new collateral asset on Moonwell's Base deployment with the recommended risk
    parameters
-   Against: Reject the addition of AERO as a new collateral asset on Moonwell's Base deployment
-   Abstain
