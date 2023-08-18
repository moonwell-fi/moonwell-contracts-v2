# Overview

This document explains how to add new markets to Moonwell from end to end, leveraging existing tooling in a way that allows integration and governance testing both pre and post-deploy.

## 1. Setup

Go to `mainnetMTokensExample.json` to see what an example mToken JSON configuration looks like. Then, copy and paste that structure into `mainnetMTokens.json`, replacing all of the values with the correct values for those markets. Initial mint amount, collateral factor, should be set to the correct values and replaced with the actual values the market should have once deployed.
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

## 3. Versioning

Modify the [`mip-market-listing.sol`](./test/proposals/mips/examples/mip-market-listing.sol) `name` variable to the correct proposal number.

**WARNING** Do not modify the [`mip-market-listing.sol`](./test/proposals/mips/examples/mip-market-listing.sol) other than the name variable. Do not change the file name or the contract name as this will break other files.

## 4. Proposal Description

Once the proposal description has been created, copy and paste it into [`ProposalDescription.md`](./test/proposals/proposalTypes/ProposalDescription.md), deleting all previous data from this file.

## 5. Deployment
To deploy these new markets, run `DeployMarketCreationProposal.s.sol` using command:

```
forge script test/proposals/DeployMarketCreationProposal.s.sol:DeployMarketCreationProposal \
    -vvvv \
    --rpc-url base \
    --broadcast
```

Once the contracts are deployed, copy and paste the `_addAddress()` commands the deployment script outputted into the `Addresses.sol` file under the proper network section. Now, save these changes and proceed to the next step.

## 6. Governance Proposal
Now that the contracts are deployed, it's time to generate the calldata. Generate this calldata by running:
```
forge test --match-test testPrintCalldata -vvv --fork-url base
```

Then, scroll up to get the calldata to propose these changes to the DAO. After section "artemis governor queue governance calldata", copy and paste the calldata and send the calldata to the governance contract on moonbase by going to metamask and submitting a transaction to the ArtemisGovernor contract with the calldata the raw hex copied.

Once the calldata is sent, wait for the proposal to finish the voting period, then queue and execute it.

## 7. Testing

To test the changes introduced by creating these market(s) and ensure the system solvency, modify the [PostProposalCheck](./test/integration/PostProposalCheck.sol) to add the newMarketDeploy mip to the array of mips tested. This can be done by uncommenting the line that adds it to the `mips` address array, and lengthening the array to support 2 active proposals, or if only doing this as a single proposal, write to mips array at index 0 and comment out the other line adds the incorrect MIP.

After PostProposalCheck is modified, the view the [HundredFinanceExploit](./test/unit/HundredFinanceExploit.t.sol) example file, and replicate the structure where the PostProposalCheck contract is imported and inherited, then write the necessary tests for these newly added markets, ensuring supplying, borrowing, repaying all work.
