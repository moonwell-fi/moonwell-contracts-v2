# MIP-B15 Onboard WBTC to Moonwell

## Summary
We propose onboarding wBTC as collateral on Moonwell Base deployment conditional to the token being available on Base and significant liquidity being onboarded subsequently on DEXes. Due to the market demand and future growth of WBTC liquidity on Base we think it appropriate to list the asset.

### Risk Parameter Recommendations

| Parameters           | Values |
|----------------------|--------|
| CF                   | 0   |
| Supply Cap           | 0.00010001    |
| Borrow Cap           | 0.00001    |
| Protocol Seize Share | 0.3    |


### IR Recommendations

| IR Parameters    | Recommended |
|------------------|-------------|
| Base             | 0           |
| Kink             | 0.45        |
| Multiplier       | 0.04        |
| Jump Multiplier  | 3.00        |
| Reserve Factor   | 0.25        |

### Supporting Data 

#### IR Parameter Specifications 

**wBTC IR Curves**

![Screenshot 2024-02-12 at 2.46.20 PM](https://hackmd.io/_uploads/HyKiQW_j6.png)

| Utilization | Borrow APR | Supply APR| 
| ------------| ---------- | ----------|
|      0%       |     0       |      0     |
|      45%       |     1.8%       |     0.6%      |
|      100%       |      166.8%      |     125.1%      |

#### Risk Parameter Specifications

**Token Liquidity and Market Stats**

| Metrics              | wBTC    |
|----------------------|-----------|
| Market Cap                  | $10.53B   |
| 24h Trading Volume       | $505M     |
| 2% Depth (DEX+CEX)   | $40.7M     |

### Supply and Borrow Caps

Borrow and supply caps are the primary parameter recommendations we can make to mitigate protocol risk when listing new assets. Gauntlet recommends setting the borrow and supply caps strategically until wBTC is added to the BASE bridge and on-chain circulating supply begins to ramp up.

|Asset|	Cap Recommendation|
| ----| ---- |
| Supply Cap           | 0.00010001    |
| Borrow Cap           | 0.00001    |

Utilizing the Supply and Borrow Cap Guardian, Moonwell gains the ability to swiftly adjust the caps to capture the wBTC market. This contrasts with the previous method of setting the CF to 0 and subsequently making adjustments after the listing, which would have be delayed via the governance process.

Gauntlet recommends the supply and borrow cap at 0.00010001 and 0.00001 BTC respectively, facilitating the governance proposal’s ability to mint a minimal amount as a preventive measure against a Hundred Finance attack.

