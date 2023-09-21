# MIP-B04 - Onboard native USDC as collateral

## Summary

Following up on the [launch of native Base USDC on September 5th](https://www.circle.com/blog/usdc-now-available-natively-on-base), we propose onboarding USDC as a collateral asset on Moonwell’s Base deployment.

Due to the market demand and rapid increase in USDC liquidity on Base, we think it appropriate to list the asset as collateral.

## Recommendations

We propose launching USDC as collateral with the following parameters:

|Asset|CF|Supply cap|Borrow cap|IRM|Oracle|Protocol seize share|
| --- | --- | --- | --- | --- | --- | --- |
|[USDC](https://basescan.org/token/0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)|0.8|10M|5M|[Stable](https://basescan.org/address/0x1603178b26c3bc2cd321e9a64644ab62643d138b)|[Chainlink USDC / USD](https://basescan.org/address/0x7e860098F58bBFC8648a4311b374B1D669a2bc6B)|30%|

![|557x345](https://i.imgur.com/lD7PfNI.png)

|Utilization|Borrow rate|Supply rate|
| --- | --- | --- |
|Base utilization (0%)|0%|0%|
|Kink utilization (80%)|4%|2.4%|
|Max utilization (100%)|56%|40.5%|

## Analysis

KPIs for native USDC on Base, with DAI and USDbC as comparison (as of Sept 6 2023).

|Asset|Total supply (Base)|Circulating supply (Base)|Circulating supply (all chains)|Bridge|-5% liquidity depth (to ETH)|
| --- | --- | --- | --- | --- | --- |
|USDC|152M|50M|26B|-|$1.2M|
|USDbC|121M|121M|26B|Base|$1.35M|
|DAI|24M|23.7M|3.9B|Base|$1M|

DEX liquidity for USDC is currently highly concentrated in [Curve 4pool](https://curve.fi/#/base/pools/factory-v2-1/swap). The pool currently holds over 90% of USDC DEX liquidity on Base. Furthermore, [top 10 LPs on Curve 4pool hold ~60% of the liquidity](https://basescan.org/token/tokenholderchart/0x79edc58c471acf2244b8f93d6f425fd06a439407).

![|624x508, 80%](https://i.imgur.com/Zfppx6V.png)


![image|690x464, 80%](https://i.imgur.com/k5YuRly.png)

Given these observations, we propose initializing the USDC market with conservative supply and borrow caps as a preventive measure. Caps may be adjusted shortly after launching the market once more pools are bootstrapped with substantial liquidity. Note that the [Cap Guardian role](https://forum.moonwell.fi/t/gauntlets-initial-recommendations-for-moonwell-on-base/536#enable-gauntlet-as-supply-borrow-cap-guardian-6) allows adjusting the caps without being subject to standard 3-day voting period + timelock.

Here are the proposed caps for USDC, along with current caps for other stable markets as a matter of comparison.

|Market|Supply cap|Borrow cap|
| --- | --- | --- |
|USDC (proposed)|10M|5M|
|USDbC|40M|32M|
|DAI|10M|5M|

## Deployment

We also strongly recommend collateral factors to be set at 0 during deployment to mitigate the risk of someone exploiting a known Compound v2 issue (see [Hundred Finance exploit](https://www.comp.xyz/t/hundred-finance-exploit-and-compound-v2/4266)).

Steps for safe deployment as proposed by Hexagate are the following:

* Initialize markets using 0 as collateral factor (no borrowing possible).
* Burn a small amount of collateral token supply for each market.
* Set collateral factors for each market as specified
