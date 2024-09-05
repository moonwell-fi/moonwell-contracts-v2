# MIP-B28: Add cbBTC Market on Base

## Proposal Details

I propose the addition of a [cbBTC](https://x.com/coinbase/status/1823501582006411614) (Coinbase wrapped BTC) market to Moonwell's Base deployment. This proposal aims to initiate the process of listing cbBTC, allowing the Moonwell community and risk managers like Gauntlet to prepare for its imminent launch. By positioning Moonwell as an early adopter of this significant asset, we align ourselves with Base's vision of becoming a major hub for Bitcoin DeFi and further catalyzing the growth of the world's largest onchain economy.

**Note from Gauntlet:** We propose onboarding cbBTC as collateral on Moonwell Base deployment conditional to significant liquidity being added on DEXes. Due to the market demand and future growth of cbBTC liquidity on Base we think it appropriate to list the asset.

- Asset: cbBTC
- Address:
  [0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf](https://basescan.org/address/0xcbb7c0000ab88b473b1f5afd9ef808440eed33bf)
- Oracle Feed:
  [BTC/USD](https://basescan.org/address/0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F)

### cbBTC

* cbBTC is an upcoming wrapped Bitcoin derivative expected to launch on the Base network very soon.
* It aims to become the dominant Bitcoin variant on Base, replacing WBTC as the trusted solution for Bitcoin DeFi following the announcement of WBTC custodian [BitGo’s new ownership structure](https://protos.com/justin-sun-has-99-problems-and-wbtc-is-two-of-them/).
* Jesse Pollak, creator of Base, has emphasized his desire [to build a massive Bitcoin economy](https://x.com/jessepollak/status/1823515062658830681) on the network.

### Benefits to the Moonwell Community

1. Early Adoption Advantage: Position Moonwell as a leader in supporting Coinbase's onchain initiatives and work to build substantial liquidity for cbBTC early in the asset’s life cycle.
2. Market Diversification: Expand Moonwell's offerings, introducing the first Bitcoin-based lending market on Moonwell’s Base deployment.
3. Increased TVL and Revenue Potential: Leverage the popularity of Bitcoin collateralization, as evidenced by WBTC's performance on Moonbeam, which is the largest Moonwell market by TVL on the network.
4. Strategic Alignment: Support Base's vision of becoming a hub for Bitcoin DeFi and further building out of the onchain economy.

### Gauntlet Risk Parameter Recommendations

Gauntlet, Moonwell's lead risk manager, has provided the following initial risk parameter recommendations for the cbBTC market. 

Please note that Gauntlet serves as Cap Guardian for Moonwell. This means that as DEX liquidity for cbBTC grows, Gauntlet will be able to dynamically adjust the supply and borrow caps without requiring additional onchain governance proposals.

#### Risk Parameter Recommendations

| Parameter            | Value                                             |
| -------------------- | -----                                             |
| Collateral Factor    | 81%                                               |
| Supply Cap           | 0.001 (Will increase as DEX liquidity increases)  |
| Borrow Cap           | 0.0005 (Will increase as DEX liquidity increases) |
| Protocol Seize Share | 30%                                               |

#### Interest Rate Model Recommendations

| IR Parameter    | Recommended Value |
| --------------- | ----------------- |
| Base            | 0.02              |
| Kink            | 0.6               |
| Multiplier      | 0.065             |
| Jump Multiplier | 3.0               |
| Reserve Factor  | 0.1               |

## Conclusion

While we eagerly await cbBTC's launch on Base, initiating this proposal now is critical to cementing Moonwell's position as a leader in the rapidly evolving onchain economy. This proactive approach not only demonstrates our commitment to innovation but also ensures we are fully prepared to integrate cbBTC swiftly and safely once it goes live.

The addition of cbBTC to Moonwell represents more than just another new market—it's a strategic move that aligns our community with Base and our protocol with the future of Bitcoin DeFi. By being among the first to support cbBTC, we have the opportunity to help shape the landscape of onchain finance and further establish Moonwell as a cornerstone of the Base ecosystem.

## Voting Options

- For: Approve the addition of cbBTC as a new market on Moonwell's Base
  deployment
- Against: Reject the addition of cbBTC as a new market on Moonwell's Base
  deployment
- Abstain
