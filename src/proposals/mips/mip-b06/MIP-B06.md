# MIP-B06 Gauntlet's BASE Recommendations

# Simple Summary

### Risk Parameters

A proposal to adjust 2 risk parameters:

| Risk Parameter         | Current Value | Recommended Value |
| ---------------------- | ------------- | ----------------- |
| USDC Collateral Factor | 80%           | 82%               |
| WETH Collateral Factor | 78%           | 80%               |

### IR Parameters

A proposal to adjust IR parameters across 5 assets:

Gauntlet recommends reducing the Multiplier to 0.037 in order to lower the APY at the kink point to 3.96%. This
adjustment is proposed to enhance the capital efficiency of the WETH liquidity pool. | WETH IR Parameters | Current |
Recommended | | --------------- | ------- | ----------- | | BASE | 0.01 | 0.01 | | Kink | 0.8 | 0.8 | | Multiplier |
0.04 | 0.037 | | Jump Multiplier | 4.8 | 4.8 |

Per @Warden's recommendation
[here](https://forum.moonwell.fi/t/moonwell-base-recommendations-2023-09-11/617/3?u=gauntlet), Gauntlet supports the
Jump Multiplier increase to 8.6 for all stablecoins and cbETH IR parameter changes.

| DAI/USDC/USDbC IR Parameters | Current | Recommended |
| ---------------------------- | ------- | ----------- |
| BASE                         | 0       | 0           |
| Kink                         | 0.8     | 0.8         |
| Multiplier                   | 0.045   | 0.045       |
| Jump Multiplier              | 2.5     | 8.6         |

| cbETH IR Parameters | Current | Recommended |
| ------------------- | ------- | ----------- |
| Base                | 0.01    | 0           |
| Kink                | 0.45    | 0.45        |
| Multiplier          | 0.2     | 0.07        |
| Jump Multiplier     | 3       | 3.15        |

Here is the forum [post](https://forum.moonwell.fi/t/gauntlets-base-recommendations-2023-10-05/645) with further
analysis and supporting data for our recommendations.

By approving this proposal, you agree that any services provided by Gauntlet shall be governed by the terms of service
available at gauntlet.network/tos.
