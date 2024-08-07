# MIP-O01: Gauntlet's Optimism Recommendations

General recommendations for Optimism market:

#### Caps

| Risk Parameter    | Previous Recommended Value | New Recommended Value |
| ----------------- | -------------------------- | --------------------- |
| WETH Supply Cap   | 4,000                      | 3200                  |
| WETH Borrow Cap   | 3,400                      | 2700                  |
| USDC Supply Cap   | 18,200,000                 | No Change             |
| USDC Borrow Cap   | 17,000,000                 | No Change             |
| USDT Supply Cap   | 22,600,000                 | No Change             |
| USDT Borrow Cap   | 18,400,000                 | No Change             |
| DAI Supply Cap    | 2,400,000                  | No Change             |
| DAI Borrow Cap    | 2,000,000                  | No Change             |
| WBTC Supply Cap   | 70                         | 66                    |
| WBTC Borrow Cap   | 45                         | 40                    |
| wstETH Supply Cap | 1,850                      | 1500                  |
| wstETH Borrow Cap | 850                        | 750                   |
| rETH Supply Cap   | 800                        | 750                   |
| rETH Borrow Cap   | 380                        | 350                   |
| cbETH Supply Cap  | 30                         | 30                    |
| cbETH Borrow Cap  | 0                          | 0                     |
| OP Supply Cap     | 2,000,000                  | 1,400,000             |
| OP Borrow Cap     | 1,000,000                  | 650,000               |
| VELO Supply Cap   | 19,500,000                 | 9,000,000             |
| VELO Borrow Cap   | 9,000,000                  | 4,500,000             |

#### LTs and RFs

| Risk Parameter           | Recommended Value |
| ------------------------ | ----------------- |
| WETH Collateral Factor   | 81%               |
| WETH Reserve Factor      | 10%               |
| USDC Collateral Factor   | 83%               |
| USDC Reserve Factor      | 5%                |
| USDT Collateral Factor   | 83%               |
| USDT Reserve Factor      | 5%                |
| DAI Collateral Factor    | 83%               |
| DAI Reserve Factor       | 5%                |
| WBTC Collateral Factor   | 81%               |
| WBTC Reserve Factor      | 10%               |
| wstETH Collateral Factor | 78%               |
| wstETH Reserve Factor    | 10%               |
| rETH Collateral Factor   | 78%               |
| rETH Reserve Factor      | 10%               |
| cbETH Collateral Factor  | 78%               |
| cbETH Reserve Factor     | 10%               |
| OP Collateral Factor     | 65%               |
| OP Reserve Factor        | 25%               |
| VELO Collateral Factor   | 65%               |
| VELO Reserve Factor      | 25%               |

#### IRs

| IR Parameters   | USDC  | DAI   | USDT  | WETH  | WBTC  |
| --------------- | ----- | ----- | ----- | ----- | ----- |
| Base            | 0     | 0     | 0     | 0.02  | 0.02  |
| Kink            | 0.8   | 0.8   | 0.8   | 0.8   | 0.6   |
| Multiplier      | 0.075 | 0.075 | 0.075 | 0.055 | 0.065 |
| Jump Multiplier | 2.5   | 2.5   | 2.5   | 5     | 3     |

| IR Parameters   | cbETH | wsETH | rETH  | OP   | VELO |
| --------------- | ----- | ----- | ----- | ---- | ---- |
| Base            | 0.02  | 0.02  | 0.02  | 0.02 | 0.02 |
| Kink            | 0.45  | 0.45  | 0.45  | 0.45 | 0.45 |
| Multiplier      | 0.065 | 0.065 | 0.065 | 0.1  | 0.1  |
| Jump Multiplier | 3     | 3     | 3     | 3.15 | 3.15 |

#### Protocol Seize share

| Asset                | USDC | USDT | DAI | WETH | WBTC | cbETH | wstETH | rETH | VELO | OP  |
| -------------------- | ---- | ---- | --- | ---- | ---- | ----- | ------ | ---- | ---- | --- |
| Protocol Seize Share | 30%  | 30%  | 30% | 30%  | 30%  | 30%   | 30%    | 30%  | 30%  | 30% |

Our recommendation post is located in the forums, please refer to this
[link](https://forum.moonwell.fi/t/gauntlet-base-optimism-moonbeam-moonriver-monthly-recommendations-2024-08-01/1151).
By approving this proposal, you agree that any services provided by Gauntlet
shall be governed by the terms of service available at gauntlet.network/tos
