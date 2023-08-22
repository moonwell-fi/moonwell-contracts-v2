# Overview
The proposal simulation framework is a way to test the governance system. It runs and executes cross chain proposals, and then tests the system to ensure it is still operating normally.

## How to add a new proposal

View the `IProposal` file, it defines the interface for a Moonwell Improvement Proposal.

Make a new file, MIPXX in the same folder as MIP00. Fill in everything the proposal should do in each step. Be sure to use the CrossChainProposal and not any other proposal type for proposals happening on Base.

See example code in mip01 where the executor is TEMPORAL_GOVERNOR. While simulating a cross chain gov proposal, TEMPORAL_GOVERNOR must be the executor. In validate, it should validate all state changes that occurred during the gov proposal checking that all parameters are properly set.

Then in TestProposals file, copy the same pattern used for MIP00, but remove MIP00 and replace it with MIPXX and push any other proposals that need to be run sequentially.

Then import the TestProposals file into a new file, and create tests to ensure the system operates normally after the governance proposal. These tests should follow the same pattern as found in `LiveSystemTest` and `SystemUpgradeUnitTest`

Run the tests with the fork test.

```forge test --match-contract your_contract_name --fork-url base```

Example proposal MIP01 can be found, which creates reward streams for the system on base.


### Generating Calldata for an Existing Proposal

#### Environment Variables
First, set the environment variables for which actions you want to be run during this proposal. The following environment variables are available:
- **DO_DEPLOY** - Whether or not to deploy the system. Defaults to true.
- **DO_AFTER_DEPLOY** - Whether or not to run the after deploy script. Defaults to true.
- **DO_AFTER_DEPLOY_SETUP** - Whether or not to run the after deploy setup script. Defaults to true.
- **DO_BUILD** - Whether or not to build the calldata for the proposal. Defaults to true.
- **DO_RUN** - Whether or not to simulate the execution of the proposal. Defaults to true.
- **DO_TEARDOWN** - Whether or not to run the teardown script. Defaults to true.
- **DO_VALIDATE** - Whether or not to run validation checks after all previous steps have been run. Defaults to true.

Set the environment variables to true or false depending on which steps you want to run.

To generate calldata for an existing proposal, run the following command, where the proposal is the proposal you want to generate calldata for, and the network is the network you want to generate calldata for.

```forge script test/proposals/mips/mip-b02/mip-b02.sol:mipb02 --rpc-url base -vvvvv```

add the following flags to deploy and verify against the base network:

```forge script test/proposals/mips/mip-b02/mip-b02.sol:mipb02 --rpc-url base -vvvvv --broadcast --etherscan-api-key base --verify```

### MIP00

In order to configure the system before go live on Base, we need to run a proposal to set the initial parameters. This proposal is MIP00. It is a cross chain proposal that sets the initial parameters for the system. It is run on Base, and then the system is deployed to the other networks. The proposal is then run on the other networks to set the parameters for those networks.

Currently, there are mock values in the `mainnetMTokens.json` file that are used to set the initial parameters. These values are not final, and will be updated by Guantlet before go live.

Additionally, the Pause Guardian, Borrow Supply Guardian, and other parameters like the chainlink oracles, and underlying tokens must be set in the `Addresses.sol` before the proposal is run.
