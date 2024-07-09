# MIP-M25: Gauntlet's Moonbeam Recommendations

A proposal to adjust 7 total risk parameters:

| Parameter                  | Current Value | Recommended Value |
| -------------------------- | ------------- | ----------------- |
| xcUSDC Collateral Factor   | 10%           | 15%               |
| WGLMR Collateral Factor    | 58%           | 57%               |
| WGLMR Borrow Cap           | 22,500,000    | 10,000,000        |
| WBTC.wh Borrow Cap         | 50            | 5                 |
| WETH.wh WBTC.wh Borrow Cap | 500           | 100               |
| xcUSDT Reserve Factor      | 20%           | 25%               |
| xcUSDC Reserve Factor      | 20%           | 25%               |

A proposal to make a IR curve adjustments for USDC.wh:

| USDC.wh IR Parameters | Current    | Recommended |
| --------------------- | ---------- | ----------- |
| BASE                  | 0          | 0           |
| Kink                  | 0.8        | 0.8         |
| Multiplier            | **0.0845** | **0.0875**  |
| Jump Multiplier       | **7.2**    | **7.4**     |

A proposal to make an IR curve adjustments for xcUSDC:

| xcUSDC IR Parameters | Current    | Recommended |
| -------------------- | ---------- | ----------- |
| BASE                 | 0          | 0           |
| Kink                 | 0.8        | 0.8         |
| Multiplier           | **0.0814** | **0.0875**  |
| Jump Multiplier      | **7.0**    | **7.4**     |

A proposal to make a IR curve adjustments for xcUSDT:

| xcUSDT IR Parameters | Current    | Recommended |
| -------------------- | ---------- | ----------- |
| BASE                 | 0          | 0           |
| Kink                 | 0.8        | 0.8         |
| Multiplier           | **0.0814** | **0.0875**  |
| Jump Multiplier      | **7.0**    | **7.4**     |

A proposal to make an IR curve adjustments for FRAX:

| FRAX IR Parameters | Current  | Recommended |
| ------------------ | -------- | ----------- |
| BASE               | 0        | 0           |
| Kink               | 0.8      | 0.8         |
| Multiplier         | **0.01** | **0.0563**  |
| Jump Multiplier    | **0.01** | **4**       |

Our recommendation post is located in the forums, please refer to this
[link](https://forum.moonwell.fi/t/gauntlet-s-base-moonbeam-moonriver-recommendations-2024-03-26/841?u=gauntlet). By
approving this proposal, you agree that any services provided by Gauntlet shall be governed by the terms of service
available at gauntlet.network/tos
