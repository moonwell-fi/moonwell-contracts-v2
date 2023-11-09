# Overview
The proposal simulation framework is a way to test the governance system. It runs and executes cross chain proposals using a JSON file.

## How to add a new proposal

View the files located in the [proposals](proposals/) folder, these files define how to structure a Moonwell Improvement Proposal in JSON.

Make a new file in the [`proposals/`](proposals/) folder named `MIPBXX.json`. Fill in everything the proposal should do in each step. Keep in mind, new contract deployments should be done in the `deploy` step, but doing this deployment requires creating a new Solidity file by copying the file from [CrossChainJSONProposal.sol](src/proposals/proposalTypes/CrossChainJSONProposal.sol), creating a new MIP folder in the [src/proposals/mips](src/proposals/mips) folder, and adding the copied file to that folder. Then, you'll need to make modifications to the `deploy` section and actually deploy the new contracts. See [mip-b03](src/proposals/mips/mip-b03/mip-b03.sol) for an example of the deploy section.

Integration tests will only run with the new proposal a new file was created in [src/proposals/mips](src/proposals/mips) folder. They will now validate the state change after your proposal passes.

If creating a new solidity file:

```export PROPOSAL_ARTIFACT_PATH=artifacts/foundry/mip-b05.sol/mipb05.json```

If not creating a new solidity file:

```export PROPOSAL_ARTIFACT_PATH=artifacts/foundry/CrossChainJSONProposal.sol/CrossChainJSONProposal.json```

Run the tests with the fork test.

```forge test --match-contract LiveSystemBaseTest --fork-url base -vvv```


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
- **PROPOSAL_ARTIFACT_PATH** - Path to the artifact of the governance proposal you would like to run.
- **DO_AFTER_DEPLOY_MTOKEN_BROADCAST** - Whether or not to do the after deploy mtoken broadcast. Defaults to true. Only used when using the [`mip-market-listing.sol`](./src/proposals/mips/examples/mip-market-listing/mip-market-listing.sol) proposal.
- **PROPOSAL** - path to the JSON proposal file. to run MIPB06, set to `proposals/MIPB06.json`
- **PROPOSAL_DESCRIPTION** - path to the proposal description markdown file. to simulate MIPB06, set to `src/proposals/mips/mip-b06/MIP-B06.md`
Set the environment variables to true or false depending on which steps you want to run.

If deploying or running against base mainnet, the following environment variable needs to be set:

Or by setting it to a private RPC endpoint if the public end point is not working.

To generate calldata for an existing proposal, run the following command, where the proposal is the proposal you want to generate calldata for, and the network is the network you want to generate calldata for.

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

if not deploying contracts, ensure DO_BUILD and DO_RUN are set to true:

```DO_BUILD=true DO_RUN=true forge script src/proposals/proposalTypes/CrossChainJSONProposal.sol:CrossChainJSONProposal -vvvvv --ffi```

to build mip-b02:
```
export DO_BUILD=true
export DO_RUN=true
export PROPOSAL=proposals/MIPB02.json
export PROPOSAL_DESCRIPTION=src/proposals/mips/mip-b02/MIP-B02.md
forge script src/proposals/proposalTypes/CrossChainJSONProposal.sol:CrossChainJSONProposal -vvvvv --ffi --rpc-url base
```


to build mip-b05:
```
export DO_BUILD=true
export DO_RUN=true
export PROPOSAL=proposals/MIPB05.json
export PROPOSAL_DESCRIPTION=src/proposals/mips/mip-b05/MIP-B05.md
forge script src/proposals/proposalTypes/CrossChainJSONProposal.sol:CrossChainJSONProposal -vvvvv --ffi --rpc-url base
```


to build mip-b06:
```
export DO_BUILD=true
export DO_RUN=true
export PROPOSAL=proposals/MIPB06.json
export PROPOSAL_DESCRIPTION=src/proposals/mips/mip-b06/MIP-B06.md
forge script src/proposals/proposalTypes/CrossChainJSONProposal.sol:CrossChainJSONProposal -vvvvv --ffi --rpc-url base
```

if deploying contracts, a path to the new solidity file will need to be provided like so:

```forge script src/proposals/mips/mip-b02/mip-b02.sol:mipb02 --rpc-url base -vvvvv --broadcast --etherscan-api-key base --verify```

##### Debugging

If running the script is failing, the first thing you should do is double check that your environment variables are set correctly. If they aren't, the script will fail. Other areas to investigate are the output log of the failure as that can inform you of what went wrong.

### Warning

Currently this WILL NOT WORK for proposals that are executed against Moonbeam due to how the build process works. This can be fixed in the future.
