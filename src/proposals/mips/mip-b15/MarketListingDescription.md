# MIP-B03 Onboard WBTC to Moonwell

## Summary
We propose onboarding WBTC as an asset on Moonwell’s Base deployment. Due to the market demand and future growth of WBTC liquidity on Base we think it appropriate to list the asset.

## Recommendation
We propose launching WBTC as collateral with the following parameters:
|Asset|CF|Supply cap|Borrow cap|IRM|Oracle|Protocol seize share|
| --- | --- | --- | --- | --- | --- | --- |
|[WBTC](https://basescan.org/token/0x1ceA84203673764244E05693e42E6Ace62bE9BA5)|0|0.0001|0.00000001|Stable|[Chainlink WBTC / USD](https://basescan.org/address/0xCCADC697c55bbB68dc5bCdf8d3CBe83CdD4E071E)|30%|

We propose to set WBTC’s interest rate curve parameters to the stable IRM configuration. 

|Stable IRM Parameter|Value|
| --- | --- |
|Base rate|0|
|Multiplier|0.05|
|Kink|0.8|
|Jump multiplier|2.5|
|Reserve factor|0.15|

|Utilization|Borrow rate|
| --- | --- |
|Base utilization (0%)|0%|
|Kink utilization (80%)|4%|
|Max utilization (100%)|56%|


## Deployment
We strongly recommend collateral factors to be set at 0 during deployment to mitigate the risk of someone exploiting a known Compound v2 issue (see [Hundred Finance exploit](https://www.comp.xyz/t/hundred-finance-exploit-and-compound-v2/4266)). Steps for safe deployment as proposed by Hexagate are the following:

* Initialize markets using 0 as collateral factor (no borrowing possible).
* Burn a small amount of collateral token supply for each market.
* Set collateral factors for each market as specified

