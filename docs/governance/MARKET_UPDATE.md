# Overview

This document explains how to update parameters to Moonwell markets, leveraging
existing tooling in a way that allows integration and governance testing both
pre and post-deploy.

## Setup

All MIPS should be placed in the `proposals/mips/` folder. The proposal
[naming convention](./CONTRIBUTING.md#naming-convention) should be respected.
The market update proposal must include the following three files:

### 1. JSON File

If you have already deployed the IRM contracts, you should first add them to the
chain addresses file located in the `/utils/` folder. For example, if the
proposal includes an IRM update on Base network and you have deployed the
contract externally, add the contract with a descriptive name like
`JUMP_RATE_IRM_MOONWELL_USDC_MIP_B32` to [/utils/8453.json](/utils/8453.json).

If you haven't deployed the contracts yet and prefer to use the script for
deployment, please follow the instructions in the
[Running Locally](#running-locally) section below.

Once you've handled the contracts deployment and addresses addition, create a
new file named `yxx.json` in the newly created `mip-yxx` folder, where `yxx`
represents your MIP number.

```JSON
{
    "8453": {
        "markets": [
            {
                "collateralFactor": -1,
                "irm": "",
                "market": "MOONWELL_USDBC",
                "reserveFactor": 0.75e18
            },
            {
                "collateralFactor": -1,
                "irm": "JUMP_RATE_IRM_MOONWELL_USDC_MIP_B32",
                "market": "MOONWELL_USDC",
                "reserveFactor": -1
            },
            {
                "collateralFactor": -1,
                "irm": "JUMP_RATE_IRM_MOONWELL_cbBTC_MIP_B32",
                "market": "MOONWELL_cbBTC",
                "reserveFactor": -1
            }
        ],
        "irModels": [
            {
                "baseRatePerTimestamp": 0,
                "jumpMultiplierPerTimestamp": 9e18,
                "kink": 0.9e18,
                "multiplierPerTimestamp": 0.05e18,
                "name": "JUMP_RATE_IRM_MOONWELL_USDC_MIP_B32"
            },

                "baseRatePerTimestamp": 0,
                "jumpMultiplierPerTimestamp": 3e18,
                "kink": 0.6e18,
                "multiplierPerTimestamp": 0.067e18,
                "name": "JUMP_RATE_IRM_MOONWELL_cbBTC_MIP_B32"
            }
        ]
    }
}
```

For numbers, use `-1` if you don't want to include them in the calldata. For
strings, use an empty string.

The tooling supports multi-chain proposals. The field should be the chain
number. For example, if you want to create a proposal that affects both Base and
Optimism, it should look like this:

```JSON
{
    "8453": {
        "markets": [...],
        "irModels": [...]
    },
    "10": {
        "markets": [...],
        "irModels": [...]
    }
}
```

### 2. Proposal Description

Once the proposal description has been created, copy and paste it into a file
named `MIP-YXX.md` in the new `mip-yxx` folder.

### 3. Shell Script

Once both the markdown and json files have been created, add a new file `yxx.sh`
to the same folder. On this file you should export the following environment
variables:

```
export JSON_PATH="./src/proposals/mips/mip-yxx/yxx.json"
export DESCRIPTION_PATH="./src/proposals/mips/mip-yxx/MIP-YXX.md"
export PRIMARY_FORK_ID=1

echo "JSON_PATH=$JSON_PATH"
echo "DESCRIPTION_PATH=$DESCRIPTION_PATH"
echo "PRIMARY_FORK_ID=$PRIMARY_FORK_ID"

```

- Uses 0 for the `PRIMARY_FORK_ID` env if it's a Moonbeam-only or multi-chain
  proposal.
- Uses 1 for Base-only proposals.
- Uses 2 for Optimism-only proposals.

**Note:** If any errors show up relating to not being able to read in a file,
double-check the environment variables and make sure the paths are correct.

## Running Locally

```bash
source src/proposals/mips/mip-yxx/yxx.sh && forge script src/proposals/templates/MarketUpdate.sol`
```

If you want to use the script to deploy the IRM contracts run this instead:

```bash
source src/proposals/mips/mip-yxx/yxx.sh && forge script
src/proposals/templates/MarketUpdate.sol` --broadcast --ledger/account
```

After running, copy the new IRM contracts and add to the corresponding chain
json file inside [/utils/](/utils/)

## Creating the Pull Request

Before opening a PR, you should add a new object to the
[/src/proposals/mips/mips.json](/src/proposals/mips/mips.json) file. For
example:

```JSON
    {
        "envpath": "src/proposals/mips/mip-yxx/yxx.json",
        "governor": "MultichainGovernor",
        "id": 0,
        "path": "src/proposals/templates/MarketUpdate.sol",
        "proposalType": "HybridProposal"
    },
```

When adding the new entry:

1. The `governor`, `path`, and `proposalType` fields should always remain the
   same as shown in the example.
2. Set the `id` to 0 while the proposal is not yet on-chain.
3. Once the proposal is on-chain, update the `id` with the proposal id from the
   transaction `ProposalCreated` event emisison.

Important notes:

- The PR will only be merged after the `id` has been properly set.
- Adding this new entry to `mips.json` is mandatory as it ensures:
  1. Integration tests run against the new proposal.
  2. CI will print the calldata in the PR comments.

Please follow the [Pull Requests Guideline](/docs/GUIDELINES.md#pull-requests)
when submitting your PR.
