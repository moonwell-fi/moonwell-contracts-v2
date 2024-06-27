# MIP-B14: Gauntlet's Base Recommendations

## Simple Summary

### Risk Parameters

A proposal to adjust 12 risk parameters:

| Risk Parameter        | Current Value | Recommended Value |
| --------------------- | ------------- | ----------------- |
| wstETH Reserve Factor | 25%           | 30%               |
| rETH Reserve Factor   | 25%           | 30%               |
| cbETH Reserve Factor  | 25%           | 30%               |
| DAI Reserve Factor    | 15%           | 20%               |
| wETH Supply Cap       | 10,500        | 12,500            |
| wETH Borrow Cap       | 8000          | 10,500            |
| DAI Supply Cap        | 4,500,000     | 2,500,000         |
| DAI Borrow Cap        | 3,800,000     | 2,000,000         |
| rETH Supply Cap       | 600           | 700               |
| wstETH Supply Cap     | 1600          | 1800              |
| wstETH Borrow Cap     | 700           | 800               |
| USDC Borrow Cap       | 10,000,000    | 12,000,000        |

<sub> \*Cap Recommendations will be implemented via Guardian </sub>

### IR Parameters

A proposal to adjust wETH's IR curve:

| wETH IR Parameters | Current   | Recommended |
| ------------------ | --------- | ----------- |
| Base               | **0.01**  | **0**       |
| Kink               | 0.8       | 0.8         |
| Multiplier         | **0.037** | **0.032**   |
| Jump Multiplier    | **4.8**   | **4.2**     |

A proposal to adjust DAI's IR curve:

| DAI IR Parameters | Current  | Recommended |
| ----------------- | -------- | ----------- |
| Base              | 0        | 0           |
| Kink              | **0.8**  | **0.75**    |
| Multiplier        | **0.05** | **0.067**   |
| Jump Multiplier   | **8.6**  | **9.0**     |

Our recommendation post is located in the forums, please refer to this [link](https://forum.moonwell.fi/t/gauntlet-s-base-moonbeam-moonriver-recommendations-2024-02-28/800).
By approving this proposal, you agree that any services provided by Gauntlet shall be governed by the terms of service available at gauntlet.network/tos