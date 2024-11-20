# Overview

The proposal simulation framework is a way to test the governance system. It
runs and executes cross chain proposals, and then tests the system to ensure it
is still operating normally.

## How to add a new proposal

[IProposal.sol](../../proposals/proposalTypes/IProposal.sol) defines the
interface for a Moonwell Improvement Proposal.

When creating new proposals, please follow the naming conventions and guidelines
outlined below

### Naming Convention

1.  **Folder Name:** Use the format `mip-yXX`, where `y` is the first letter of
    the chain name and `XX` is the proposal number, incremented by 1 from the
    last proposal. For proposals that touch multiple chains, use the letter `x`.
    For example, if the last multichain proposal is `mip-x09`, the next should
    be `mip-x10`.
2.  **Markdown File Name:** Inside the folder, create a file named `MIP-YXX.md`.
3.  **Contract Name:** If the proposal includes a smart contract, name it
    `contract mipyxx` inside the corresponding Solidity file.
4.  **Folders and Solidity Files:** Use lowercase letters.
5.  **Markdown Files:** Use uppercase letters, e.g., `MIP-BXX.md`.

### Guidelines for Pull Requests and Branches

All pull requests must adhere to the style guidelines detailed in
[GUIDELINES.md](../GUIDELINES.md).

### Proposal Structure

- Ensure that each step of the proposal is thoroughly documented within the
  Solidity file.
- Inherit from
  [HybridProposal](../../proposals/proposalTypes/HybridProposal.sol) and include
  all necessary details.

## How to test a proposal

### Set the `PRIMARY_FORK_ID` environment variable

For example, to test a proposal on the base network, set the `PRIMARY_FORK_ID`
to `1`. Find the corresponding fork ID in the `chains/mainnetchains.json` file.

```bash
    export PRIMARY_FORK_ID=1
```

### Run Integration Tests

`forge test --match-contract LiveSystem -vvv`

Integration tests inherit from `PostProposalCheck`, which will run the latest
proposals from both base and moonbeam if they have not already been proposed on
mainnet. Combining the proposal execution with the integration tests provides a
clear idea of how the system will behave after proposal execution.

## Nonce

Please note: the nonce field set in
[CrossChainProposal.sol](./../proposals/proposalTypes/CrossChainProposal.sol) is
completely extraneous as this field is not used in the Temporal Governor when it
processes cross chain messages. There is no need to set this field in any cross
chain proposal.

## Generating Calldata for an Existing Proposal

### Environment Variables

First, set the environment variables for which actions you want to be run during
this proposal. The following environment variables are available:

- **DO_DEPLOY** - Whether or not to deploy the system. Defaults to true.
- **DO_AFTER_DEPLOY** - Whether or not to run the after deploy script. Defaults
  to true.
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
  [`mip-market-listing.sol`](./proposals/mips/examples/mip-market-listing/mip-market-listing.sol)
  proposal.

### Sample Environment Variables For Deploying and Building Calldata for a Market Listing Proposal

```
export DO_DEPLOY=true
export DO_AFTER_DEPLOY=true
export DO_BUILD=true
export DO_RUN=false
export DO_TEARDOWN=false
export DO_VALIDATE=false
```

For a proposal where a new market is being listed:

```
export OVERRIDE_SUPPLY_CAP=false
export OVERRIDE_BORROW_CAP=false
```

For a market listing proposal where the contracts have already been deployed:

```
export DO_DEPLOY=false
export DO_AFTER_DEPLOY=true
export DO_BUILD=true
export DO_RUN=true
export DO_TEARDOWN=true
export DO_VALIDATE=true

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
export DO_BUILD=true
export DO_RUN=true
export DO_TEARDOWN=true
export DO_VALIDATE=false
export DO_PRINT=true
```

`forge script proposals/mips/mip-b02/mip-b02.sol:mipb02 --rpc-url base -vvvvv`

add the following flags to deploy and verify against the base network:

`forge script proposals/mips/mip-b02/mip-b02.sol:mipb02 --rpc-url base -vvvvv --broadcast --etherscan-api-key base --verify --slow`

### Debugging

If running the script is failing, the first thing you should do is double check
that your environment variables are set correctly. If they aren't, the script
will fail. Other areas to investigate are the output log of the failure as that
can inform you of what went wrong.
