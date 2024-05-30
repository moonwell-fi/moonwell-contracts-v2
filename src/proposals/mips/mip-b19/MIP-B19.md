# MIP-B19: Gauntlet's Base Recommendations

A proposal to adjust 5 risk parameters:

| Risk Parameter    | Current Value | Recommended Value |
| ----------------- | ------------- | ----------------- |
| WETH Supply Cap   | 50,000        | 60,000            |
| wstETH Supply Cap | 5,000         | 6,300             |
| wstETH Borrow Cap | 1,750         | 2,400             |
| USDbC Supply Cap  | 1,000,000     | 250,000           |
| USDbC Borrow Cap  | 750,000       | 200,000           |

<sub> \*Cap Recommendations will be implemented via Guardian </sub>

### IR Parameters

A proposal to adjust WETH, USDC and AERO's IR curve:

| WETH IR Parameters | Current   | Recommended |
| ------------------ | --------- | ----------- |
| Base               | 0         | 0           |
| Kink               | 0.8       | 0.8         |
| Multiplier         | **0.032** | **0.02**    |
| Jump Multiplier    | 4.2       | 4.2         |

| USDC IR Parameters | Current   | Recommended |
| ------------------ | --------- | ----------- |
| Base               | 0         | 0           |
| Kink               | 0.9       | 0.9         |
| Multiplier         | **0.067** | **0.05**    |
| Jump Multiplier    | 9         | 9           |

| AERO IR Parameters | Current  | Recommended |
| ------------------ | -------- | ----------- |
| Base               | 0        | 0           |
| Kink               | 0.45     | 0.45        |
| Multiplier         | **0.07** | **0.145**   |
| Jump Multiplier    | 3.15     | 3.15        |

Our recommendation post is located in the forums, please refer to this
[link](https://forum.moonwell.fi/t/gauntlet-s-base-moonbeam-moonriver-recommendations-2024-05-29/957?u=gauntlet).
By approving this proposal, you agree that any services provided by Gauntlet
shall be governed by the terms of service available at gauntlet.network/tos
