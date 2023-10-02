# Overview

This document explains how to add new markets to Moonwell from end to end, leveraging existing tooling in a way that allows integration and governance testing both pre and post-deploy.

## 1. Setup

### Directory Structure

All MIPS should be placed in the `proposals/mips/mip-bxx` folder, where bxx is the next available MIP number. If the next available MIP number is 4, then the folder should be named `mip-b04`. You should copy all of the existing files from the `proposals/mips/examples/mip-market-listing` folder into the new `mip-bxx` folder as a starting point. The only 3 files that are required are `MIP-Bxx.md`, `MTokens.json`, and `RewardStreams.json`. The `MIP-Bxx.md` file is the proposal description, the `MTokens.json` file is the configuration for the MTokens being added, and the `RewardStreams.json` file is the configuration for the reward streams being added.

Please also copy the [`mip-market-listing.sol`](./proposals/mips/examples/mip-market-listing/mip-market-listing.sol) file into the new `mip-bxx` folder and rename it to `mip-bxx.sol`. This file is the Solidity script that will deploy the new markets and generate the calldata for the governance proposal. Even though you won't be executing it from this path, it's good to keep it as a reference to the version of code used to deploy the market.

### MTokens
Go to `mainnetMTokensExample.json` to see what an example mToken JSON configuration looks like. Copy the file [`MTokens.json`](./proposals/mips/examples/mip-market-listing/MTokens.json) in the `proposals/mips/examples/mip-market-listing` folder to a new `mip-bxx` folder, replacing all of the values with the correct values for those markets. Initial mint amount, collateral factor, should be set to the correct values and replaced with the actual values the market should have once deployed.
```
        "initialMintAmount": 1e12,
        "collateralFactor": 0.75e18,
        "reserveFactor": 0.25e18,
        "seizeShare": 0.03e18,
        "supplyCap": 10500e18,
        "borrowCap": 6300e18,
        "priceFeedName": "ETH_ORACLE",
        "tokenAddressName": "WETH",
        "name": "Moonwell WETH",
        "symbol": "mWETH",
        "addressesString": "MOONWELL_WETH",
        "jrm": {
            "baseRatePerYear": 0.02e18,
            "multiplierPerYear": 0.15e18,
            "jumpMultiplierPerYear": 3e18,
            "kink": 0.6e18
        }
```
- `initialMintAmount` amount of tokens to mint during gov proposal, if token has 18 decimals, should be `1e12`, if token has 6 decimals, should be `1e6`. If token has greater than 18 decimals, decimals should be token decimals - 6 decimals. Temporal Governor must be funded with the initialMintAmount of said tokens before the proposal is executed in order for the proposal to succeed.
- `collateralFactor` the percentage of value of supplied assets that is counted towards an account's collateral value, scaled up by `1e18`. Must be less than `1e18` to ensure system solvency.
- `reserveFactor` percentage of interest accrued that goes to the Moonwell DAO reserves, scaled up by `1e18`.
- `seizeShare` percentage of seized collateral that goes to protocol reserves when a liquidation occurs, scaled up by `1e18`.
- `supplyCap` cap of amount of assets that can be supplied for a given market.
- `borrowCap` cap of amount of assets that can be borrowed for a given market.
- `priceFeedName` name of the chainlink aggregator address in `Addresses.sol`. **Note user must add the address to Addresses.sol on the proper network pre-deployment in order for the price feed to be set correctly**
- `tokenAddressName` name of the underlying token address name for the new market, set in `Addresses.sol`. **Note user must add the underlying token address to Addresses.sol on the proper network pre-deployment in order for the MToken's underlying address to be set correctly**
- `name` name of the Moonwell MToken. Prefixed with `Moonwell`.
- `symbol` symbol of the Moonwell MToken. Prefixed with `m`.
- `addressesString` name of the address string set in `Addresses.sol`.
- `jrm` parameters for the configuration of a JumpRateModel for each MToken.
- `baseRatePerYear` cost to borrow per year as a percentage, scaled by `1e18`.
- `multiplierPerYear` multiplier on the base rate, which creates the curve of the rate before kink is hit, as a percentage, scaled by `1e18`.
- `jumpMultiplierPerYear` rate multiplier as a percentage, scaled by `1e18` after kink is hit.
- `kink` the point on the utilization curve after which the interest rate spikes using `jumpMultiplierPerYear` as a percentage, scaled by `1e18`

If there are no MTokens being added, the file is still needed, but it should contain an empty array.

### RewardStreams
Go to `mainnetRewardStreams.json` to see what an example reward JSON configuration looks like. Copy the file [`RewardStreams.json`](./proposals/mips/examples/mip-market-listing/RewardStreams.json) in the `proposals/mips/examples/mip-market-listing` folder into the new `mip-bxx` folder, replacing all of the values with the correct values for those markets.

If there are no reward streams, the file is still needed, but it should contain an empty array.

## 2. Proposal Description

Once the proposal description has been created, copy and paste it into a file named `MIP-Bxx.md` in the new `mip-bxx` folder.

## 3. Environment Variables
Once both the `MIP-Bxx.md`, `MTokens.json`, and `RewardStreams.json` files have the necessary contents, environment variables must be set for the script to read in their path. Export the following environment variables pointing to the correct paths:

```
export LISTING_PATH="./proposals/mips/mip-bxx/MIP-Bxx.md"
export MTOKENS_PATH="./proposals/mips/mip-bxx/MTokens.json"
export EMISSION_PATH="./proposals/mips/mip-bxx/RewardStreams.json"
```

Set the `BASE_RPC_URL` environment variable to the RPC URL of base. This can be done using the public RPC endpoint.

```
BASE_RPC_URL="https://mainnet.base.org"
```

Or by setting to a private RPC endpoint if the public end point is not working.

To get local tests running a chainfork with the new proposal type, set the `PROPOSAL_ARTIFACT_PATH` to the path of the proposal artifact. For example, if the proposal artifact is located at `artifacts/foundry/mip-b05.sol/mipb05.json`, the environment variable should be set to:

```export PROPOSAL_ARTIFACT_PATH=artifacts/foundry/mip-b05.sol/mipb05.json```

Once this has been set, then integration tests can be created which ensure the proposal is working as expected.

If deploying and generating calldata for the first time, environment variable `DO_AFTER_DEPLOY_MTOKEN_BROADCAST` should be set to true. After doing deploy and setting the addresses in `Addresses.sol`, this variable should be set to false. This variable is used to determine whether or not to broadcast the after deploy transactions that configure the MToken, which are not needed after the tokens are deployed.

If any errors show up relating to not being able to read in a file, double check the environment variables and make sure the paths are correct.

## 4. Deployment
To deploy these new markets, run [`mip-market-listing.sol`](./proposals/mips/examples/mip-market-listing/mip-market-listing.sol) using command:

```
forge script proposals/mips/examples/mip-market-listing/mip-market-listing.sol:mip0x \
    -vvvv \
    --rpc-url base \
    --broadcast
```

Once the contracts are deployed, copy and paste the `_addAddress()` commands the deployment script outputted into the `Addresses.sol` file under the proper network section. Now, save these changes and proceed to the next step.

## 5. Governance Proposal
Now that the contracts are deployed, it's time to generate the calldata. If the contracts have not been deployed and added to Addresses.sol yet, generate this calldata by running:
```
forge test --match-test testPrintNewMarketCalldataDeployMToken -vvv --fork-url base
```

otherwise, generate the calldata by running:
```
forge test --match-test testPrintNewMarketCalldataAlreadyDeployedMToken -vvv --fork-url base
```

Then, scroll up to get the calldata to propose these changes to the DAO. After section "artemis governor queue governance calldata", copy and paste the calldata and send the calldata to the governance contract on moonbase by going to metamask and submitting a transaction to the ArtemisGovernor contract with the calldata the raw hex copied.

Once the calldata is sent, wait for the proposal to finish the voting period, then queue and execute it.

## 6. Testing

To test the changes introduced by creating these market(s) and ensure the system solvency, modify the [PostProposalCheck](./test/integration/PostProposalCheck.sol) to add the newMarketDeploy mip to the array of mips tested. This can be done by uncommenting the line that adds it to the `mips` address array, and lengthening the array to support 2 active proposals, or if only doing this as a single proposal, write to mips array at index 0 and comment out the other line adds the incorrect MIP.

After PostProposalCheck is modified, the view the [HundredFinanceExploit](./test/unit/HundredFinanceExploit.t.sol) example file, and replicate the structure where the PostProposalCheck contract is imported and inherited, then write the necessary tests for these newly added markets, ensuring supplying, borrowing, repaying all work.

## 7. Safety Checks

This framework is designed to ensure that the system is safe and that the parameters look to be correct. In the market-listing solidity file, there are checks that the parameters are within sane values. There are checks around the supply and borrow cap, and if these values are set to 0, no checks will run, however, if these values are non zero, the checks will ensure that the supply and borrow cap are not set to values that are too high. If the value of a supply or borrow cap exceed 120m tokens adjusted for decimals, then a warning will fire when running the script and the script will not continue. If these values are correct, you can override the warnings by setting: 

```
export OVERRIDE_SUPPLY_CAP=true
export OVERRIDE_BORROW_CAP=true
```

If you set these variables to true, make sure to set them back to false after running the proposal to ensure no errors are missed in the future.

If the borrow cap is not equal to 0, and there is no supply cap, this is invalid for a governance proposal and the creation of the proposal will revert with an appropriate message.

If the supply cap is set, but the borrow cap is greater than or equal to the supply cap, this is invalid for a governance proposal and the creation of the proposal will revert with an appropriate message.

If the collateral factor of a market is set to greater than 95%, then the creation of the proposal will revert with an appropriate message as it is assumed that no collateral will ever have a collateral factor higher than 95%.
