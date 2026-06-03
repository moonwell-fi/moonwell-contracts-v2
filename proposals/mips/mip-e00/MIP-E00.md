# MIP-E00: Moonwell Ethereum Launch Parameters

## Summary

This proposal approves the initial launch parameters for Moonwell on Ethereum
Mainnet.

If approved, Moonwell will deploy its lending protocol to Ethereum, creating new
lending and borrowing markets for WETH, USDC, USDT, and cbBTC. The deployment
will also include Chainlink oracle configuration, Ethereum market risk
parameters, and the governance infrastructure needed for Moonwell Governance to
manage the deployment from its existing governance hub.

This marks an important milestone for Moonwell: the protocol’s expansion to
Ethereum Mainnet, the largest smart contract platform and the deepest DeFi
liquidity environment in the world.

## Background

Moonwell currently operates across multiple networks and has focused on making
onchain lending more accessible, transparent, and useful for users. Expanding to
Ethereum Mainnet is a major step in that mission. Ethereum remains the center of
DeFi liquidity, institutional activity, and high-value onchain assets. Launching
Moonwell on Ethereum gives the protocol an opportunity to serve a broader user
base, support deeper asset markets, and establish a stronger presence in the
ecosystem where decentralized finance first reached meaningful scale.

This proposal sets the initial parameters for that deployment. These parameters
are intended to support a measured launch with major, highly liquid assets,
conservative market caps, established oracle infrastructure, and governance
controls consistent with Moonwell’s existing security practices.

## Proposal

If approved, this proposal will authorize the deployment of Moonwell Protocol to
Ethereum Mainnet with the following initial markets, vaults, oracle
configuration, governance setup, and risk parameters.

### Initial Ethereum Markets

The proposed initial Ethereum Mainnet markets are:

- WETH
- cbBTC
- USDT
- USDC

### Global Risk Parameters

| Parameter             | Value |
| --------------------- | ----- |
| Liquidation Incentive | 10%   |
| Liquidator Share      | 7%    |
| Protocol Seize Share  | 3%    |
| Close Factor          | 50%   |

### WETH Risk Parameters

| Parameter         | Recommended Value |
| ----------------- | ----------------- |
| Collateral Factor | 80%               |
| Reserve Factor    | 15%               |
| Supply Cap        | 30,000 WETH       |
| Borrow Cap        | 20,000 WETH       |

#### WETH Interest Rate Parameters

| Parameter       | Recommended Value |
| --------------- | ----------------- |
| Base Rate       | 0                 |
| Multiplier      | 0.025             |
| Jump Multiplier | 9                 |
| Kink            | 0.9               |

#### WETH Projected APYs

With a 15% reserve factor:

| Utilization | Borrow APY | Supply APY |
| ----------- | ---------- | ---------- |
| 0%          | 0%         | 0%         |
| 90% / Kink  | 2.25%      | 1.72%      |
| 100%        | 92.25%     | 78.41%     |

#### WETH Oracle

| Oracle  | Address                                      | Type         |
| ------- | -------------------------------------------- | ------------ |
| ETH/USD | `0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419` | Market price |

### cbBTC Risk Parameters

| Parameter         | Recommended Value |
| ----------------- | ----------------- |
| Collateral Factor | 80%               |
| Reserve Factor    | 15%               |
| Supply Cap        | 1,000 cbBTC       |
| Borrow Cap        | 600 cbBTC         |

#### cbBTC Interest Rate Parameters

| Parameter       | Recommended Value |
| --------------- | ----------------- |
| Base Rate       | 0                 |
| Multiplier      | 0.068             |
| Jump Multiplier | 2                 |
| Kink            | 0.6               |

#### cbBTC Projected APYs

With a 15% reserve factor:

| Utilization | Borrow APY | Supply APY |
| ----------- | ---------- | ---------- |
| 0%          | 0%         | 0%         |
| 60% / Kink  | 4.08%      | 2.08%      |
| 100%        | 84.08%     | 71.47%     |

#### cbBTC Oracle

| Oracle    | Address                                      | Type         |
| --------- | -------------------------------------------- | ------------ |
| cbBTC/USD | `0x2665701293fCbEB223D11A08D826563EDcCE423A` | Market price |

### USDT Risk Parameters

| Parameter         | Recommended Value |
| ----------------- | ----------------- |
| Collateral Factor | 85%               |
| Reserve Factor    | 10%               |
| Supply Cap        | 200,000,000 USDT  |
| Borrow Cap        | 180,000,000 USDT  |

#### USDT Interest Rate Parameters

| Parameter       | Recommended Value |
| --------------- | ----------------- |
| Base Rate       | 0                 |
| Multiplier      | 0.67              |
| Jump Multiplier | 9                 |
| Kink            | 0.9               |

#### USDT Projected APYs

With a 10% reserve factor:

| Utilization | Borrow APY | Supply APY |
| ----------- | ---------- | ---------- |
| 0%          | 0%         | 0%         |
| 90% / Kink  | 6.03%      | 4.88%      |
| 100%        | 96.03%     | 86.43%     |

#### USDT Oracle

| Oracle   | Address                                      | Type         |
| -------- | -------------------------------------------- | ------------ |
| USDT/USD | `0x3E7d1eAB13ad0104d2750B8863b489D65364e32D` | Market price |

### USDC Risk Parameters

| Parameter         | Recommended Value |
| ----------------- | ----------------- |
| Collateral Factor | 85%               |
| Reserve Factor    | 10%               |
| Supply Cap        | 200,000,000 USDC  |
| Borrow Cap        | 180,000,000 USDC  |

#### USDC Interest Rate Parameters

| Parameter       | Recommended Value |
| --------------- | ----------------- |
| Base Rate       | 0                 |
| Multiplier      | 0.67              |
| Jump Multiplier | 9                 |
| Kink            | 0.9               |

#### USDC Projected APYs

With a 10% reserve factor:

| Utilization | Borrow APY | Supply APY |
| ----------- | ---------- | ---------- |
| 0%          | 0%         | 0%         |
| 90% / Kink  | 6.03%      | 4.88%      |
| 100%        | 96.03%     | 86.43%     |

#### USDC Oracle

| Oracle   | Address                                      | Type         |
| -------- | -------------------------------------------- | ------------ |
| USDC/USD | `0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6` | Market price |

### Oracle Configuration

The Ethereum deployment will use Chainlink price feeds for the initial supported
markets:

| Market | Oracle Feed         |
| ------ | ------------------- |
| WETH   | Chainlink ETH/USD   |
| USDC   | Chainlink USDC/USD  |
| USDT   | Chainlink USDT/USD  |
| cbBTC  | Chainlink cbBTC/USD |

### Risk Parameters

The deployment will use the following initial protocol-level risk parameters:

| Parameter             | Value |
| --------------------- | ----- |
| Liquidation Incentive | 10%   |
| Close Factor          | 50%   |
| Protocol Seize Share  | 3%    |

## Rationale

Ethereum Mainnet is the most important liquidity venue in decentralized finance.
Deploying Moonwell to Ethereum gives the protocol access to a larger market of
users, assets, integrations, and institutional attention.

The initial market selection focuses on widely used assets with deep liquidity
and established demand:

- WETH is the core asset of Ethereum DeFi.
- USDC and USDT are the two largest stablecoins used across lending markets.
- cbBTC gives Moonwell an initial BTC-backed market on Ethereum.

The proposed collateral factors, reserve factors, supply caps, and borrow caps
are designed to support meaningful early usage while keeping the launch
controlled. Caps can be revisited by governance over time as the Ethereum
deployment matures, liquidity deepens, and market behavior becomes easier to
evaluate.

The use of Chainlink price feeds provides familiar and battle-tested oracle
infrastructure for the initial markets. Additionally, these markets will have
their own OEV Wrappers deployed as well.

## Voting Options

- **For**: Approve the initial launch parameters and deployment configuration
  for Moonwell on Ethereum Mainnet.
- **Against**: Do not approve the initial launch parameters and deployment
  configuration for Moonwell on Ethereum Mainnet.
- **Abstain**: Participate in the vote without taking a position for or against
  the proposal.
