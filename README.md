# Moonwell Protocol v2

The Moonwell Protocol is a fork of Compound v2 with features like borrow/supply
caps, cross-chain governance, and multi-token emissions.

The "v2" release of the Moonwell Protocol is a major system upgrade to use
solidity 0.8.17, add supply caps, and a number of improvements for user
experience (things like `mintWithPermit` and `claimAllRewards`). Solidity
version 0.8.20 was not used because EIP-3855 which adds the PUSH0 opcode will
not be live on base where this system will be deployed.

# Running + Development

Development will work with the latest version of foundry installed.

Basic development workflow:

- use `forge build` to build the smart contracts
- use `forge test -vvv --match-contract UnitTest` to run the unit tests
- use `forge test --match-contract IntegrationTest --fork-url ethereum` to run
  the integration tests
- use `forge test --match-contract ArbitrumTest --fork-url arbitrum` to run the
  ChainlinkCompositeOracle tests
- use `forge test --match-contract LiveSystemTest --fork-url baseSepolia` to run
  the base sepolia live system tests
- use
  `forge script src/proposals/DeployProposal.s.sol:DeployProposal -vvvv --rpc-url moonbeam/base`
  to do a dry run of the deployment script
