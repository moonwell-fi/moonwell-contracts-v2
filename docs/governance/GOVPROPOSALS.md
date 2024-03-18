# Overview

The proposal simulation framework is a way to test the governance system. It
runs and executes cross chain proposals, and then tests the system to ensure it
is still operating normally.

## How to add a new proposal

View the `IProposal` file, it defines the interface for a Moonwell Improvement
Proposal.

Make a new folder under the `proposals/mips/` directory named `mip-bXX`, create
file `mip-bxx.sol` in the same folder that was just created. Fill in everything
the proposal should do in each step. Be sure to use the CrossChainProposal and
not any other proposal type for proposals happening on Base.

Import the TestProposals file into a new file, and create tests to ensure the
system operates normally after the governance proposal. These tests should
follow the same pattern as found in `LiveSystemTest` and `SystemUpgradeUnitTest`

Now set the environment variable to your new proposal, and run the integration
tests. They will now validate the state change after your proposal passes.

`export PROPOSAL_ARTIFACT_PATH=artifacts/foundry/mip-b05.sol/mipb05.json`

Run the tests with the fork test.

`forge test --match-contract LiveSystemBaseTest --fork-url base -vvv`

Example proposal MIPB-01, can be found, which creates reward streams for the
system on base.

## Nonce

Please note: the nonce field set in
[CrossChainProposal.sol](./../proposals/proposalTypes/CrossChainProposal.sol) is
completely extraneous as this field is not used in the Temporal Governor when it
processes cross chain messages. There is no need to set this field in any cross
chain proposal.

### Generating Calldata for an Existing Proposal

#### Environment Variables

First, set the environment variables for which actions you want to be run during
this proposal. The following environment variables are available:

- **DO_DEPLOY** - Whether or not to deploy the system. Defaults to true.
- **DO_AFTER_DEPLOY** - Whether or not to run the after deploy script. Defaults
  to true.
- **DO_AFTER_DEPLOY_SETUP** - Whether or not to run the after deploy setup
  script. Defaults to true.
- **DO_BUILD** - Whether or not to build the calldata for the proposal. Defaults
  to true.
- **DO_RUN** - Whether or not to simulate the execution of the proposal.
  Defaults to true.
- **DO_TEARDOWN** - Whether or not to run the teardown script. Defaults to true.
- **DO_VALIDATE** - Whether or not to run validation checks after all previous
  steps have been run. Defaults to true.
- **PROPOSAL_ARTIFACT_PATH** - Path to the artifact of the governance proposal
  you would like to run.
- **DO_AFTER_DEPLOY_MTOKEN_BROADCAST** - Whether or not to do the after deploy
  mtoken broadcast. Defaults to true. Only used when using the
  [`mip-market-listing.sol`](./src/proposals/mips/examples/mip-market-listing/mip-market-listing.sol)
  proposal.

#### Sample Environment Variables For Deploying and Building Calldata for a Market Listing Proposal

```
export DO_DEPLOY=true
export DO_AFTER_DEPLOY=true
export DO_AFTER_DEPLOY_SETUP=true
export DO_BUILD=true
export DO_RUN=false
export DO_TEARDOWN=false
export DO_VALIDATE=false
```

For a proposal where a new market is being listed:

```
export DO_AFTER_DEPLOY_MTOKEN_BROADCAST=true
export OVERRIDE_SUPPLY_CAP=false
export OVERRIDE_BORROW_CAP=false
```

For a market listing proposal where the contracts have already been deployed:

```
export DO_DEPLOY=false
export DO_AFTER_DEPLOY=true
export DO_AFTER_DEPLOY_SETUP=true
export DO_BUILD=true
export DO_RUN=true
export DO_TEARDOWN=true
export DO_VALIDATE=true
export DO_AFTER_DEPLOY_MTOKEN_BROADCAST=false

```

Set the environment variables to true or false depending on which steps you want
to run.

If deploying or running against base mainnet, the following environment variable
needs to be set:

- **BASE_RPC_URL** environment variable to the RPC URL of base. This can be done
  using the public RPC endpoint.

```
BASE_RPC_URL="https://mainnet.base.org"
```

Or by setting it to a private RPC endpoint if the public end point is not
working.

To generate calldata for an existing proposal, run the following command, where
the proposal is the proposal you want to generate calldata for, and the network
is the network you want to generate calldata for.

env setup to build and run without any other steps:

```bash
export DO_DEPLOY=false
export DO_AFTER_DEPLOY=false
export DO_AFTER_DEPLOY_SETUP=false
export DO_BUILD=true
export DO_RUN=true
export DO_TEARDOWN=true
export DO_VALIDATE=false
export DO_PRINT=true
```

`forge script src/proposals/mips/mip-b02/mip-b02.sol:mipb02 --rpc-url base -vvvvv`

add the following flags to deploy and verify against the base network:

`forge script src/proposals/mips/mip-b02/mip-b02.sol:mipb02 --rpc-url base -vvvvv --broadcast --etherscan-api-key base --verify --slow`

##### Debugging

If running the script is failing, the first thing you should do is double check
that your environment variables are set correctly. If they aren't, the script
will fail. Other areas to investigate are the output log of the failure as that
can inform you of what went wrong.
