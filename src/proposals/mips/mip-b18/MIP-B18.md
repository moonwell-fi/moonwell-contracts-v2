# MIP-B18: Gauntlet's Base Recommendations

A proposal to adjust 5 risk parameters:

| Risk Parameter    | Current Value | Recommended Value |
| ----------------- | ------------- | ----------------- |
| cbETH Borrow Cap  | 2,100         | 2,520             |
| wstETH Borrow Cap | 1,250         | 1,750             |
| rETH Borrow Cap   | 250           | 350               |
| USDbC Supply Cap  | 5,000,000     | 1,000,000         |
| USDbC Borrow Cap  | 4,000,000     | 750,000           |
| AERO CF           | 0%            | 65%               |

<sub> \*Cap Recommendations will be implemented via Guardian </sub>

### IR Parameters

A proposal to adjust cbETH, wstETH and rETH's IR curve:

| cbETH IR Parameters | Current  | Recommended |
| ------------------- | -------- | ----------- |
| Base                | 0        | 0           |
| Kink                | **0.45** | **0.35**    |
| Multiplier          | **0.05** | **0.075**   |
| Jump Multiplier     | **3**    | **3.5**     |

| wstETH IR Parameters | Current  | Recommended |
| -------------------- | -------- | ----------- |
| Base                 | 0        | 0           |
| Kink                 | **0.45** | **0.35**    |
| Multiplier           | **0.07** | **0.075**   |
| Jump Multiplier      | **3.15** | **3.5**     |

| rETH IR Parameters | Current  | Recommended |
| ------------------ | -------- | ----------- |
| Base               | 0        | 0           |
| Kink               | **0.45** | **0.35**    |
| Multiplier         | **0.07** | **0.075**   |
| Jump Multiplier    | **3.15** | **3.5**     |

Our recommendation post is located in the forums, please refer to this
[link](https://forum.moonwell.fi/t/gauntlet-s-base-moonbeam-moonriver-recommendations-2024-03-26/841?u=gauntlet). By
approving this proposal, you agree that any services provided by Gauntlet shall be governed by the terms of service
available at gauntlet.network/tos
