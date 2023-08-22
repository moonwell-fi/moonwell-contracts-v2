# MIP-B03 Onboard DAI as collateral
## Summary

We propose onboarding DAI as a collateral asset on Moonwell’s Base deployment. Due to the market demand and rapid increase in DAI liquidity on Base we think it appropriate to list the asset as collateral. Additionally, we propose updating USDbC’s interest rate curve to keep it in line with DAI.

## Recommendations

We propose launching DAI as collateral with the following parameters:

|Asset|CF|Supply cap|Borrow cap|IRM|Oracle|Protocol seize share|
| --- | --- | --- | --- | --- | --- | --- |
|[DAI](https://basescan.org/token/0x50c5725949a6f0c72e6c4a641f24049a917db0cb)|0.8|5M|4M|Stable (updated)|[Chainlink DAI / USD](https://basescan.org/address/0x591e79239a7d679378eC8c847e5038150364C78F)|30%|

We propose to set DAI’s interest rate curve parameters and update USDbC’s interest rate curve parameters as follow:

|Stable IRM Parameter|Value (current)|Value (proposed)|
| --- | --- | --- |
|Base rate|0|0|
|Multiplier|0.05|0.05|
|Kink|0.8|0.8|
|Jump multiplier|2.5|4.775|
|Reserve factor|0.15|0.15|

The proposed stablecoin interest rate curve increases the maximum interest rate in cases of high utilization to mitigate liquidity concerns.

![image|512x317](upload://1maSI7Qq6M2fzraCNS0A0ZqP0dJ.png)
|Utilization|Borrow rate (current)|Borrow rate (proposed)|
| --- | --- | --- |
|Base utilization (0%)|0%|0%|
|Kink utilization (80%)|4%|4%|
|Max utilization (100%)|56%|100%|

## Analysis

KPIs for Dai on Base, with USDbC as comparison (as of August 15 2023)

|Asset|Circulating supply (Base)|Circulating supply (all chains)|Bridge|-5% liquidity depth (to ETH)|
| --- | --- | --- | --- | --- |
|DAI|15M|4B|Base (Native)|$384k|
|USDbC|52M|26B|Base (Native)|$1.33M|

Given the significant difference in on-chain liquidity of DAI vs USDbC, we recommend scaling the supply and borrow caps for DAI to ⅛ of those of USDbC.

|Market|Supply cap|Borrow cap|
| --- | --- | --- |
|DAI|5M|4M|
|USDbC|40M|32M|

## Deployment

We strongly recommend collateral factors to be set at 0 during deployment to mitigate the risk of someone exploiting a known Compound v2 issue (see [Hundred Finance exploit](https://www.comp.xyz/t/hundred-finance-exploit-and-compound-v2/4266)).

Steps for safe deployment as proposed by Hexagate are the following:

* Initialize markets using 0 as collateral factor (no borrowing possible).
* Burn a small amount of collateral token supply for each market.
* Set collateral factors for each market as specified

## References

#### DAI → USDbC Liquidity profile
![image|690x349](upload://SsLA7HIMQapJ4G7kFbduXdvi5q.png)
![image|690x342](upload://4Tb3smfhyrUHe1MyFBLbolRfhvf.png)

#### USDbC  → DAI Liquidity profile 
![image|690x358](upload://jhlWXfSAmItIayjOZUx1QHICvVA.png)
![image|690x351](upload://x6pqHAPmjiTxXgQlRZNJU2pJ3Ga.png)

#### DAI → WETH Liquidity profile
![image|690x349](upload://vW9kzTdJvQFXtLXDQUU5xDvrZ2g.png)
![image|690x349](upload://wTEYGrWRA9Mupn9nMDrTAmcPPkJ.png)

#### WETH → DAI Liquidity profile
![image|690x361](upload://x1MBKMPXmvi10P7xEW5A2jz7gUl.png)
![image|690x353](upload://wk93EJ4brzWl9Va5bmWaENQnxdI.png)