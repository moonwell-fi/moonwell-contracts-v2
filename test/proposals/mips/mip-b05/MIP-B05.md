# MIP-B05 Base Risk Recommendations

# Simple Summary

### Risk Parameters
A proposal to adjust 5 risk parameters:

| Risk Parameter          | Current Value | Recommended Value |
| ----------------------- | ------------- | ----------------- |
| ETH Collateral Factor   | 75%           | 78%               |
| cbETH Collateral Factor | 73%           | 75%               |
| DAI Collateral Factors  | 80%           | 82%               |


### IR Parameters

A proposal to adjust 3 IR parameters for 4 assets:

| DAI/USDC/USDbC IR Parameters   | Current | Recommended |
| --------------- | ------- | ----------- |
| BASE            | 0       | 0           |
| Kink            | 0.8     | 0.8         |
| Multiplier      | 0.05    | 0.045       |
| Jump Multiplier | 2.5     | 2.5         |


Gauntlet recommends to increase the kink to 80% and Jump Multiplier to 4.8 for the WETH IR curve to improve capital efficency of WETH: 
| WETH IR Parameters   | Current | Recommended |
| --------------- | ------- | ----------- |
| BASE            | 0.01       | 0.01           |
| Kink            | 0.75     | 0.8         |
| Multiplier      | 0.04    | 0.04       |
| Jump Multiplier | 3.8     | 4.8         |


Here is the forum [post](https://forum.moonwell.fi/t/moonwell-base-recommendations-2023-09-11/617) with further analysis and supporting data for our recommendations.

*By approving this proposal, you agree that any services provided by Gauntlet shall be governed by the terms of service available at gauntlet.network/tos.*
