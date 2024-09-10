# MIP-B29: Add EURC Market on Base

## Proposal Details

I propose the activation of an EURC (Circle's Euro-Backed Stablecoin) market to
Moonwell's Base deployment, positioning Moonwell as an early adopter of this
significant asset. This strategic move would align Moonwell with Base's vision
of becoming a major hub for onchain finance and expand the protocol's stablecoin
offerings to include both US dollar and euro-backed assets.

Note from Gauntlet: We propose onboarding EURC on Moonwell's Base deployment due
to its status as a fully-backed, euro-pegged stablecoin issued by Circle, in
compliance with MiCA. We believe this will contribute to a more diverse
stablecoin market and offer new opportunities for liquidity growth.

**Asset:** EURC  
**Address:**
[0x60a3E35Cc302bFA44Cb288Bc5a4F316Fdb1adb42](https://basescan.org/address/0x60a3e35cc302bfa44cb288bc5a4f316fdb1adb42)
**Oracle Feed:**
[EUR/USD](https://basescan.org/address/0xdae398520e2b67cd3f27aef9cf14d93d927f8250)

## EURC Overview

EURC is Circle's Euro-backed stablecoin, one of the first mainstream euro-pegged
stablecoins to be released. Alongside USDC, EURC is part of Circle's effort to
provide reliable and compliant stablecoin solutions across multiple ecosystems,
including Ethereum, Avalanche, Solana, and Stellar. It is redeemable 1:1 for
euros and can be used for cross-border payments, making it an attractive option
for global financial operations.

## Benefits to the Moonwell Community

- **Early Adoption Advantage:** By supporting EURC early in its life cycle,
  Moonwell positions itself as a leader in offering euro-denominated onchain
  lending and borrowing.
- **Market Diversification:** Expands the range of stablecoins offered on
  Moonwell, allowing users to access euro-denominated liquidity.
- **Increased TVL and Revenue Potential:** The addition of EURC opens up
  opportunities for liquidity growth and borrowing demand, which can drive
  increased protocol revenues.
- **Strategic Alignment:** Supports Base's vision of becoming a hub for onchain
  finance and enhances Moonwell's integration with Circle's growing suite of
  stablecoins.

## Gauntlet Risk Parameter Recommendations

Gauntlet, Moonwell's lead risk manager, has provided the following initial risk
parameter recommendations for the EURC market.

Please note that Gauntlet serves as Cap Guardian for Moonwell, which allows for
the dynamic adjustment of the supply and borrow caps as market demand increases,
without requiring additional onchain governance proposals.

### Risk Parameter Recommendations

| **Parameter**          | **Value** |
| ---------------------- | --------- |
| Collateral Factor (CF) | 83%       |
| Supply Cap             | 4.2M EURC |
| Borrow Cap             | 3.9M EURC |
| Protocol Seize Share   | 30%       |
| Reserve Factor         | 10%       |

### Interest Rate Model Recommendations

| **IR Parameter** | **Recommended Value** |
| ---------------- | --------------------- |
| Base Rate        | 0                     |
| Kink             | 0.9                   |
| Multiplier       | 0.056                 |
| Jump Multiplier  | 9                     |

### Supporting Data

- Primary liquidity source: [Aerodrome](https://aerodrome.finance), with over
  $8M TVL in EURC-USDC pools
- Recommended supply cap: 44.2M EURC (40% of circulating supply)
- Recommended borrow cap: 3.9M EURC
- EURC Interest Rate Curves: Aligned with those of USDC

## Conclusion

Adding EURC to Moonwell on Base represents a strategic step forward in
diversifying our stablecoin markets and solidifying our position in the evolving
onchain financial landscape. By introducing euro-denominated lending and
borrowing, we not only expand our protocol offerings but also open doors to a
broader user base, potentially driving significant growth in both TVL and
protocol revenue.

This move aligns perfectly with Base's vision of globally accessible onchain
finance, positioning Moonwell as an early leader in euro-denominated DeFi. Our
early adoption of EURC demonstrates Moonwell's commitment to innovation and our
readiness to support the next wave of stablecoin developments in the Base
ecosystem. By approving this proposal, we take a decisive step towards enhancing
Moonwell's global appeal, diversifying our liquidity sources, and strengthening
our alignment with both Circle and Base.

This addition not only benefits our existing community but also paves the way
for Moonwell's continued growth and relevance in the rapidly growing onchain
economy.

## Voting Options

- **Aye:** Approve the addition of EURC as a new market on Moonwell's Base
  deployment
- **Nay:**Reject the addition of EURC as a new market on Moonwell's Base
  deployment
- **Abstain:** Choose to abstain from voting on this proposal
