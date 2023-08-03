# Table of Contents

The Moonwell system is a Compound based lending market. The system consists of the following contracts.

- [TemporalGovernor](./TEMPORALGOVERNOR.md): A cross chain governance contract that allows proposals passed by the community on moonbeam to be relayed across the chain to the Base network. This contract owns the entire system deployment on base.
- [JumpRateModel](./JUMPRATEMODEL.md): Jump rate model contract that automatically adjusts the interest rate based on the utilization rate.
- [GovProposals](./GOVPROPOSALS.md): Documentation on submitting proposals to the TemporalGovernor contract using the cross chain proposal simulation framework.
- [ChainlinkOracle](./CHAINLINKORACLE.md): A Chainlink oracle contract that allows the system to fetch the price of assets on the Ethereum network. Maps the underlying token symbol to a chainlink feed address for easy lookups of price. Allows admin (temporal governor) to override the price of an asset in case of a price feed failure.
- [ChainlinkCompositeOracle](./CHAINLINKCOMPOSITEORACLE.md): A Chainlink composite oracle contract that combines multiple Chainlink oracles into a single oracle. This allows the system to fetch and combine the price of assets on the base network from multiple sources and receive the product of the results. Two or three asset prices can be combined together, and the result can be used as the price of a new asset. This is useful for calculating the price of a synthetic asset that is a combination of multiple assets. Conforms with the Chainlink AggregatorV3Interface.
- [Unitroller](./UNITROLLER.md): A proxy contract that delegates calls to the Comptroller contract. This contract is used to upgrade the Comptroller contract and hold all state.
- [Comptroller](./COMPTROLLER.md): A logic contract that handles the business logic of the system. Validates user actions such as liquidating, supplying and borrowing assets. Stores important variables such as the liquidation incentive, close factor, and markets users have entered.
- [InterestRateModel](./INTERESTRATEMODEL.md): An abstract interest rate model contract with no functions that defines an interface for all interest rate models. This contract is used by the JumpRateModel contract.
- [MToken](./MTOKEN.md): A contract that represents a token that has been supplied to the system. Users can supply and borrow this token. The contract also allows users to redeem their tokens for the underlying asset.
- [WETHRouter](./WETHROUTER.md): A contract that allows users to wrap their ETH and then mint mWETH atomically. This contract also allows users to unwrap their mWETH and then unwrap their WETH into ETH atomically by first approving the contract to spend their mWETH.
- [MultiRewardDistributor](./MULTIREWARDDISTRIBUTOR.md): Reward distributor contract that allows the system to distribute rewards for supplying and borrowing in multiple reward tokens per MToken. This contract is used by the Comptroller contract. This contract's admin is the Comptroller's admin which is the Temporal Governor.
- [MERC20Delegator](./MERC20DELEGATOR.md): A proxy contract that delegates calls to the MERC20Delegate contract. This contract is used to upgrade the MERC20Delegate contract and hold all state.
- [MERC20Delegate](./MERC20DELEGATE.md): A logic contract that handles the business logic of the MERC20Delegator contract. This contract inherits the MToken contract and provides all the functionality of the MToken contract.
- [Deployment](../SETUP.md): Documentation on how to deploy the Moonwell system on the base or base goerli network.
- [Testing](../run.sh): Shell script file to run all the different tests. Requires setting both `ARB_RPC_URL` and `ETH_RPC_URL` environment variables to work properly.
