# MIP-B42: Add MORPHO Market to Moonwell on Base

## Summary

This proposal seeks to list **MORPHO**, the governance token of the Morpho
Protocol, as a new collateral asset in Moonwell's Core Lending Markets on Base.
MORPHO is used for onchain governance of the Morpho Protocol, allowing holders
and Morpho delegates to vote on key protocol upgrades and initiatives.

[Morpho](https://docs.morpho.org/overview/) is a permissionless,
capital-efficient lending protocol that supports isolated market creation and
vault strategies, with Moonwell operating and providing frontend support for
several vaults and isolated markets within the Morpho ecosystem. The MORPHO
token is now transferable and live on Base, with liquidity growing across both
DEXs and CEXs.

Gauntlet has reviewed the asset and recommends onboarding MORPHO with
conservative parameters to account for its current liquidity profile. This
listing will also allow the Moonwell community to deepen alignment with a key
protocol partner while expanding support for blue chip Base-native assets.

---

## Token Information

- **Name:** MORPHO
- **Token Standard:** ERC20 (Wrapped)
- **Token Contract (Base):** `0xBAa5CC21fd487B8Fcc2F632f3F4E8D37262a0842`
- **Total Supply:** 1,000,000,000
- **Circulating Supply on Base:** 224,000,000
- **Chainlink Price Feed (Base):** `0xe95e258bb6615d47515Fc849f8542dA651f12bF6`
- **Launched on Base:** November 2024
- **Transferability Enabled:** November 21, 2024
- **Wrapper Contract (Ethereum):** `0x9D03bb2092270648d7480049d0E58d2FcF0E5123`

---

## Token Background

MORPHO is the governance token of the Morpho Protocol. It is used to vote on
protocol upgrades and decisions via an onchain delegation system. Initially
launched as a non-transferable token to support a more decentralized and
equitable distribution model, transferability was enabled in November 2024
following a governance vote.

To support governance features and future cross-chain compatibility, MORPHO
exists in a wrapped form. The original "legacy" token remains 1:1 convertible
via a wrapper contract. All MORPHO on Base is already in its wrapped,
transferable form.

---

## Integration with Moonwell

Moonwell and Morpho are deeply integrated. The Moonwell DAO currently owns and
operates [several Morpho Vaults](https://moonwell.fi/vaults) across Base and OP
Mainnet, including:

- Moonwell Flagship ETH, USDC, and EURC vaults on Base
- Moonwell Frontier cbBTC vault on Base
- A new Moonwell Flagship USDC Vault on OP Mainnet

These vaults are curated by **B.Protocol** and **Block Analitica**, with full
frontend support inside the Moonwell app.

---

## Administrative Notes

This proposal also includes a minor change to support guardian role
functionality for OP Mainnet deployment.

---

## Gauntlet Risk Parameter Recommendations

### Initial Risk Parameters

| Parameter              | Value            |
| ---------------------- | ---------------- |
| Collateral Factor (CF) | 65%              |
| Supply Cap             | 1,000,000 MORPHO |
| Borrow Cap             | 500,000 MORPHO   |
| Reserve Factor         | 30%              |
| Protocol Seize Share   | 30%              |

### Interest Rate Model

| Parameter       | Value |
| --------------- | ----- |
| Base Rate       | 0%    |
| Multiplier      | 23%   |
| Jump Multiplier | 5x    |
| Kink            | 45%   |

#### Utilization vs Interest Rate Curve

| Utilization | Borrow APR | Supply APR |
| ----------- | ---------- | ---------- |
| 0%          | 0%         | 0%         |
| 45% (Kink)  | 10.35%     | 3.26%      |
| 100%        | 285.35%    | 199.74%    |

---

## Supporting Data

### Liquidity

| Platform             | Pair               | TVL    | 24h Volume |
| -------------------- | ------------------ | ------ | ---------- |
| Aerodrome Slipstream | MORPHO/WETH (0.3%) | $1.83M | $270K      |
| Uniswap V3 (Base)    | MORPHO/WETH (0.3%) | $291K  | $101K      |
| Uniswap V3 (Base)    | MORPHO/USDC (1%)   | $103K  | $2.4K      |

- **Total DEX TVL (Base):** ~$2.2M
- Liquidity is concentrated in WETH pairs
- A ~$1.5M sell would currently result in ~25–30% slippage
- **30-day Annualized Volatility:** 183%

---

## Voting Options

- **Aye:** Approve the proposal to activate a MORPHO market on Moonwell (Base)
  using Gauntlet's recommended initial risk parameters
- **Nay:** Reject the proposal
- **Abstain:** Abstain from voting
