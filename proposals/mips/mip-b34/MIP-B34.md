# MIP-B34: Gauntlet's Base Recommendations

A proposal to adjust 9 risk parameters:

| Risk Parameter          | Current Value | Recommended Value |
| ----------------------- | ------------- | ----------------- |
| USDbC Collateral Factor | 78%           | 76%               |
| USDbC Supply Cap        | 150,000       | 110,000           |
| USDbC Borrow Cap        | 150,000       | 100,000           |
| USDbC Reserve Factor    | 75%           | 90%               |
| DAI Collateral Factor   | 82%           | 80%               |
| DAI Supply Cap          | 750,000       | 400,000           |
| DAI Borrow Cap          | 500,000       | 300,000           |
| DAI Reserve Factor      | 20%           | 40%               |
| WETH Reserve Factor     | 15%           | 5%                |

<sub> \*Cap Recommendations will be implemented via Guardian </sub>

### IR Parameters

A proposal to adjust IR parameters for DAI, WETH and USDbC

| DAI IR Parameters | Current   | Recommended |
| ----------------- | --------- | ----------- |
| Base              | 0         | 0           |
| Kink              | **0.75**  | **0.6**     |
| Multiplier        | **0.067** | **0.04**    |
| Jump Multiplier   | **9**     | **4**       |

| WETH IR Parameters | Current | Recommended |
| ------------------ | ------- | ----------- |
| Base               | 0       | 0           |
| Kink               | **0.8** | **0.9**     |
| Multiplier         | 0.01    | 0.01        |
| Jump Multiplier    | **4.2** | **8**       |

| USDbC IR Parameters | Current   | Recommended |
| ------------------- | --------- | ----------- |
| Base                | 0         | 0           |
| Kink                | **0.75**  | **0.6**     |
| Multiplier          | **0.067** | **0.04**    |
| Jump Multiplier     | **9**     | **4**       |

Our recommendation post is located in the forums, please refer to this
[link](https://forum.moonwell.fi/t/gauntlet-base-optimism-moonbeam-moonriver-monthly-recommendations-2024-10-23/1302).
By approving this proposal, you agree that any services provided by Gauntlet
shall be governed by the terms of service available at gauntlet.network/tos
