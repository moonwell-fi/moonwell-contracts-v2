# MIP-B03 Onboard DAI as collateral
## Summary
We propose onboarding DAI as a collateral asset on Moonwell’s Base deployment. Due to the market demand and rapid increase in DAI liquidity on Base we think it appropriate to list the asset as collateral.

## Recommendation
We propose launching DAI as collateral with the following parameters:
|Asset|CF|Supply cap|Borrow cap|IRM|Oracle|Protocol seize share|
| --- | --- | --- | --- | --- | --- | --- |
|[DAI](https://basescan.org/token/0x50c5725949a6f0c72e6c4a641f24049a917db0cb)|0.8|6M|5M|Stable|[Chainlink DAI / USD](https://basescan.org/address/0x591e79239a7d679378eC8c847e5038150364C78F)|30%|

We propose to set DAI’s interest rate curve parameters to the stable IRM configuration. 

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

## Analysis
KPIs for Dai on Base, with USDbC as comparison (as of August 15 2023)

|Asset|Circulating supply (Base)|Circulating supply (all chains)|Bridge|-5% liquidity depth (to ETH)|
| --- | --- | --- | --- | --- |
|DAI|15M|4B|Base (Native)|$384k| |USDbC|52M|26B|Base (Native)|$1.33M|

Given the significant difference in on-chain liquidity of DAI vs USDbC, we recommend scaling the supply and borrow caps for DAI to around ⅛ of those of USDbC.

|Market|Supply cap|Borrow cap|
| --- | --- | --- |
|DAI|6M|5M|
|USDbC|40M|32M|

## Deployment
We strongly recommend collateral factors to be set at 0 during deployment to mitigate the risk of someone exploiting a known Compound v2 issue (see [Hundred Finance exploit](https://www.comp.xyz/t/hundred-finance-exploit-and-compound-v2/4266)). Steps for safe deployment as proposed by Hexagate are the following:

* Initialize markets using 0 as collateral factor (no borrowing possible).
* Burn a small amount of collateral token supply for each market.
* Set collateral factors for each market as specified
## References
#### DAI → USDbC Liquidity profile ![image|690x349](https://i.imgur.io/e6TCd9G_d.webp?maxwidth=640&shape=thumb&fidelity=medium) ![image|690x342](https://i.imgur.io/ATJiNz3_d.webp?maxwidth=640&shape=thumb&fidelity=medium) 
#### USDbC → DAI Liquidity profile ![image|690x358](https://i.imgur.io/5Y0u7HC_d.webp?maxwidth=640&shape=thumb&fidelity=medium) ![image|690x351](https://i.imgur.io/z4VpxiC_d.webp?maxwidth=640&shape=thumb&fidelity=medium) 
#### DAI → WETH Liquidity profile ![image|690x349](https://i.imgur.io/rYUZDNw_d.webp?maxwidth=640&shape=thumb&fidelity=medium) ![image|690x349](https://i.imgur.io/9pjr0cy_d.webp?maxwidth=640&shape=thumb&fidelity=medium) 
#### WETH → DAI Liquidity profile ![image|690x361](https://i.imgur.io/WR9Xd6v_d.webp?maxwidth=640&shape=thumb&fidelity=medium) ![image|690x353](https://i.imgur.io/sjvI1dB_d.webp?maxwidth=640&shape=thumb&fidelity=medium)
