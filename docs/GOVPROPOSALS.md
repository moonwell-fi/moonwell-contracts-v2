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

To generate calldata for an existing proposal that is already pushed onto the proposals array at the 0th index in `TestProposals.sol`, run the following command:

```forge test -vvv --match-test testQueueAndPublishMessage --fork-url network_name|network_url```

