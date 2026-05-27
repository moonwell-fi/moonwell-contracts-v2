# MIP-E00: Moonwell Ethereum Launch Parameters

## Summary

This proposal approves the initial launch parameters for Moonwell on Ethereum
Mainnet.

If approved, Moonwell will deploy its lending protocol to Ethereum, creating new
lending and borrowing markets for WETH, USDC, USDT, and cbBTC. The deployment
will also include initial Morpho vaults, Chainlink oracle configuration,
Ethereum market risk parameters, and the governance infrastructure needed for
Moonwell Governance to manage the deployment from its existing governance hub.

This marks an important milestone for Moonwell: the protocol’s expansion to
Ethereum Mainnet, the largest smart contract platform and the deepest DeFi
liquidity environment in the world.

## Background

Moonwell currently operates across multiple networks and has focused on making
onchain lending more accessible, transparent, and useful for users. Expanding to
Ethereum Mainnet is a major step in that mission.

Ethereum remains the center of DeFi liquidity, institutional activity, and
high-value onchain assets. Launching Moonwell on Ethereum gives the protocol an
opportunity to serve a broader user base, support deeper asset markets, and
establish a stronger presence in the ecosystem where decentralized finance first
reached meaningful scale.

This proposal sets the initial parameters for that deployment. These parameters
are intended to support a measured launch with major, highly liquid assets,
conservative market caps, established oracle infrastructure, and governance
controls consistent with Moonwell’s existing security practices.

## Proposal

If approved, this proposal will authorize the deployment of Moonwell Protocol to
Ethereum Mainnet with the following initial markets, vaults, oracle
configuration, governance setup, and risk parameters.

### Initial Markets

| Market | Collateral Factor | Reserve Factor | Supply Cap  | Borrow Cap |
| ------ | ----------------- | -------------- | ----------- | ---------- |
| WETH   | 80%               | 10%            | 50,000      | 35,000     |
| USDC   | 85%               | 10%            | 100,000,000 | 80,000,000 |
| USDT   | 80%               | 10%            | 50,000,000  | 40,000,000 |
| cbBTC  | 75%               | 15%            | 1,000       | 500        |

### Initial MMorpho Vaults

The Ethereum deployment will include the following Morpho vaults:

- WETH Flagship Vault (`mwETH`)
- USDC Flagship Vault (`mwUSDC`)
- USDT Flagship Vault (`mwUSDT`)

These vaults are intended to provide users with simple, curated access to
Moonwell lending markets on Ethereum.

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

### Governance Configuration

The Ethereum deployment will include a `TemporalGovernor` contract that receives
governance actions from Moonbeam through Wormhole.

This allows Moonwell Governance to continue managing protocol changes from its
existing governance hub while extending control to the Ethereum deployment. In
practice, this means Moonwell can expand to Ethereum without fragmenting
governance across separate systems.

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
infrastructure for the initial markets. The use of capped price feeds adds
additional protection for assets such as stablecoins and wrapped assets where
conservative oracle behavior is important.

The proposed governance design also preserves continuity for Moonwell. By using
a TemporalGovernor connected through Wormhole, Moonwell Governance can manage
Ethereum Mainnet from the existing governance hub rather than creating a
separate governance process for Ethereum.

## Voting Options

- **For**: Approve the initial launch parameters and deployment configuration
  for Moonwell on Ethereum Mainnet.
- **Against**: Do not approve the initial launch parameters and deployment
  configuration for Moonwell on Ethereum Mainnet.
- **Abstain**: Participate in the vote without taking a position for or against
  the proposal.
