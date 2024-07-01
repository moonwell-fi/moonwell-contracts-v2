# MIP-B22: Gauntlet's Base Recommendations

A proposal to adjust 6 risk parameters:

| Risk Parameter   | Current Value | Recommended Value |
| ---------------- | ------------- | ----------------- |
| USDC Supply Cap  | 92,000,000    | 100,000,000       |
| USDC Supply Cap  | 84,000,000    | 92,000,000        |
| cbETH Supply Cap | 7,200         | 8,000             |
| cbETH Borrow Cap | 2,520         | 3,200             |
| AERO Supply Cap  | 16,000,000    | No Change         |
| AERO Borrow Cap  | 10,000,000    | No Change         |

<sub> \*Cap Recommendations will be implemented via Guardian </sub>

## IR Parameters Adjustment Proposal

A proposal to adjust WETH, wstETH, cbETH, rETH, and AERO's IR curve:

### WETH IR Parameters

| IR Parameter    | Current  | Recommended |
| --------------- | -------- | ----------- |
| Base            | 0        | 0           |
| Kink            | 0.8      | 0.8         |
| Multiplier      | **0.02** | **0.01**    |
| Jump Multiplier | 4.2      | 4.2         |

### wstETH IR Parameters

| IR Parameter    | Current   | Recommended |
| --------------- | --------- | ----------- |
| Base            | 0         | 0           |
| Kink            | 0.35      | 0.35        |
| Multiplier      | **0.075** | **0.061**   |
| Jump Multiplier | 3.5       | 3.5         |

### cbETH IR Parameters

| IR Parameter    | Current   | Recommended |
| --------------- | --------- | ----------- |
| Base            | 0         | 0           |
| Kink            | 0.35      | 0.35        |
| Multiplier      | **0.075** | **0.061**   |
| Jump Multiplier | 3.5       | 3.5         |

### rETH IR Parameters

| IR Parameter    | Current   | Recommended |
| --------------- | --------- | ----------- |
| Base            | 0         | 0           |
| Kink            | 0.35      | 0.35        |
| Multiplier      | **0.075** | **0.061**   |
| Jump Multiplier | 3.5       | 3.5         |

### AERO IR Parameters

| IR Parameter    | Current   | Recommended |
| --------------- | --------- | ----------- |
| Base            | 0         | 0           |
| Kink            | 0.45      | 0.45        |
| Multiplier      | **0.145** | **0.18**    |
| Jump Multiplier | 3.15      | 3.96        |

Our recommendation post is located in the forums, please refer to this
[link](https://forum.moonwell.fi/t/gauntlet-s-base-moonbeam-moonriver-recommendations-2024-06-26/1075?u=gauntlet).
By approving this proposal, you agree that any services provided by Gauntlet
shall be governed by the terms of service available at gauntlet.network/tos
