# Moonwell Protocol v2

The Moonwell Protocol is a fork of Compound v2 with features like borrow/supply caps, cross-chain governance, and
multi-token emissions.

The "v2" release of the Moonwell Protocol is a major system upgrade to use solidity 0.8.19, add supply caps, and a
number of improvements for user experience (things like `mintWithPermit` and `claimAllRewards`). Solidity version 0.8.20
was not used because EIP-3855 which adds the PUSH0 opcode was not be live on base at the time this system was deployed.

# Table of Contents

-   [Contributing](./docs/CONTRIBUTING.md)
-   [Engineering Guidelines](./docs/GUIDELINES.md)
-   [Protocol Core](./docs/core/)
    -   [JumpRateModel](./JUMPRATEMODEL.md): Jump rate model contract that automatically adjusts the interest rate based
        on the utilization rate.
    -   [ChainlinkOracle](./CHAINLINKORACLE.md): A Chainlink oracle contract that allows the system to fetch the price
        of assets on the Ethereum network. Maps the underlying token symbol to a chainlink feed address for easy lookups
        of price. Allows admin (temporal governor) to override the price of an asset in case of a price feed failure.
    -   [ChainlinkCompositeOracle](./CHAINLINKCOMPOSITEORACLE.md): A Chainlink composite oracle contract that combines
        multiple Chainlink oracles into a single oracle. This allows the system to fetch and combine the price of assets
        on the base network from multiple sources and receive the product of the results. Two or three asset prices can
        be combined together, and the result can be used as the price of a new asset. This is useful for calculating the
        price of a synthetic asset that is a combination of multiple assets. Conforms with the Chainlink
        AggregatorV3Interface.
    -   [Unitroller](./UNITROLLER.md): A proxy contract that delegates calls to the Comptroller contract. This contract
        is used to upgrade the Comptroller contract and hold all state.
    -   [Comptroller](./COMPTROLLER.md): A logic contract that handles the business logic of the system. Validates user
        actions such as liquidating, supplying and borrowing assets. Stores important variables such as the liquidation
        incentive, close factor, and markets users have entered.
    -   [InterestRateModel](./INTERESTRATEMODEL.md): An abstract interest rate model contract with no functions that
        defines an interface for all interest rate models. This contract is used by the JumpRateModel contract.
    -   [MToken](./MTOKEN.md): A contract that represents a token that has been supplied to the system. Users can supply
        and borrow this token. The contract also allows users to redeem their tokens for the underlying asset.
    -   [WETHRouter](./WETHROUTER.md): A contract that allows users to wrap their ETH and then mint mWETH atomically.
        This contract also allows users to unwrap their mWETH and then unwrap their WETH into ETH atomically by first
        approving the contract to spend their mWETH.
    -   [MultiRewardDistributor](./MULTIREWARDDISTRIBUTOR.md): Reward distributor contract that allows the system to
        distribute rewards for supplying and borrowing in multiple reward tokens per MToken. This contract is used by
        the Comptroller contract. This contract's admin is the Comptroller's admin which is the Temporal Governor.
    -   [MERC20Delegator](./MERC20DELEGATOR.md): A proxy contract that delegates calls to the MERC20Delegate contract.
        This contract is used to upgrade the MERC20Delegate contract and hold all state.
    -   [MERC20Delegate](./MERC20DELEGATE.md): A logic contract that handles the business logic of the MERC20Delegator
        contract. This contract inherits the MToken contract and provides all the functionality of the MToken contract.
-   [Governance](./docs/governance/)
    -   [Contributing](./docs/governance/CONTRIBUTING.md): Documentation on submitting proposals to the TemporalGovernor
        contract using the cross chain proposal simulation framework.
    -   [Listing new markets](./docs/governance/MARKET_ADD.md): Documentation on listing new markets on the Moonwell
        Protocol.
    -   [Temporal Governor](./docs/governance/contracts/TEMPORALGOVERNOR.md): A cross chain governance contract that
        allows proposals passed by the community on moonbeam to be relayed across the chain to the Base network. This
        contract owns the entire system deployment on base.
    -   [Multichain Governor](./docs/governance/contracts/MULTICHAINGOVERNOR.md): Multichain Governor is live on
        Moonbeam and is the source of truth for all governance actions in Moonwell.
    -   [Vote Collection](./docs/governance/VOTECOLLECTION.md): Documentation on how votes are collected on external
        chains and relayed to Moonbeam.
-   [Deployment](./docs/deployment/): Steps to deploy the Moonwell Protocol to a new chain.

# Tests

The protocol has several layers of testing: unit testing, integration testing, invariants, fuzzing, mutation and formal
verification.

## Unit tests

The unit tests coverage must be kept as close to 100% as possible.

-   use `forge test -vvv --match-contract UnitTest` to run the unit tests

## Integration tests

-   use `forge test --match-contract IntegrationTest --fork-url ethereum` to run the integration tests
-   use `forge test --match-contract ArbitrumTest --fork-url arbitrum` to run the ChainlinkCompositeOracle tests
-   use `forge test --match-contract BaseTest --fork-url base` to run the Base ChainlinkCompositeOracle tests
-   use `forge test --match-contract LiveSystemTest --fork-url baseSepolia` to run the base sepolia live system tests
-   use `forge test --match-contract MultichainProposalTest` to run the Multichain Governor integration tests

## Invariants

-   use `forge test --match-contract Invariant` to run the invariants tests

## Formal Verification

Moonwell uses Certora to formally verify key protocol invariants. The Certora formal specifications are located in the
`certora` directory. To run the Certora tests, first you need to export the `CERTORAKEY` environment variable with the
Certora API key.

-   use `certoraRun certora/confs/ConfigurablePauseGuardian.conf` to run the ConfigurablePauseGuardian tests.
-   use `certoraRun certora/confs/ERC20.conf` to run the ERC20 tests.
-   use `certoraRun certora/confs/MultichainGovernor.conf` to run the MultichainGovernor tests.
-   use `certoraRun certora/confs/MultichainVoteCollection.conf` to run the MultichainVoteCollection tests.

## Mutation Testing

Use certora gambit to generate mutations for `MultichainVoteCollection` and `MultichainGovernor` and then run each
mutation against unit, integration tests and formal specification using `run-vote-collection-mutation.sh` and
`run-governor-mutation.sh` script respectively. Each scripts generates a `MutationTestOuput/Result_<Contract>.md` file
which stores following details for each mutations:

-   mutant diff with original contract
-   unit/integration test results with number and list of failing tests if any
-   [ ] result of certora formal verification against mutant with details such as number of failed rules, their list and
        certora prover cli job url (Certora formal verification runs only in MultichainVoteCollection script)

Finally at the end it logs total number of failed mutations.

The following steps needs to be followed for mutation testing:

1. Run certora gambit to generate mutations:

-   MultichainVoteCollection

```
gambit mutate --json certora/mutation/MultichainVoteCollectionConfig.json
```

-   MultichainGovernor

```
gambit mutate --json certora/mutation/MultichainGovernorConfig.json
```

2. Run script that runs tests against mutants and outputs results into a readme file:

-   MultichainVoteCollection

```
sh bin/run-vote-collection-mutation.sh
```

-   MultichainVoteCollection

```
sh bin/run-governor-mutation.sh
```

Note: Remember the script replaces original contract code with mutated code and thus both script cannot be run in
parallel as the tests might fail because of mutated code of the other contract. But you can easily run scripts in
parallel with just cloning the same repository and running single script in a single repository. Also remember to
checkout any changes before running the mutations as they might affect the mutation output.

## Running All Tests

Run [run.sh](./run.sh) to execute all the different tests
