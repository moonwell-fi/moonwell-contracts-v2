# System Setup

set your env vars:

`ETH_PRIVATE_KEY, DO_DEPLOY, and DO_AFTERDEPLOY to true`

if deploying on base goerli, go to Addresses.sol and delete everything after this line
```        /// ---------- base goerli deployment ----------```
and before this line`
```                /// -----------------------------------------------```

then to deploy the entire system on base goerli:

```forge script test/proposals/DeployProposal.s.sol:DeployProposal -vvv --rpc-url baseGoerli --with-gas-price 100000000 --skip-simulation --slow --gas-estimate-multiplier 200 --broadcast --etherscan-api-key baseGoerli --verify```

optionally, you can deploy with verification on BaseScan Goerli:

```forge script test/proposals/DeployProposal.s.sol:DeployProposal -vvv --etherscan-api-key baseGoerli --verify --rpc-url baseGoerli --broadcast```


Substitute out the rpc-url for the chain to deploy on if the destination is not base goerli.

If deploying on mainnet, double check that `mainnetMTokens.json` and `mainnetRewardStreams.json` in the `test/proposals/` folder are correctly filled out. Then, double check that in `Addresses.sol`, all the oracles, tokens and guardians are correctly set. If no reward streams will be created, ensure the rewards json file is an empty array. Triple check that the addresses for the system are correct in `Addresses.sol`, then deploy to base mainnet:

```forge script test/proposals/DeployProposal.s.sol:DeployProposal -vvv --rpc-url base --with-gas-price 100000000 --skip-simulation --slow --gas-estimate-multiplier 200 --broadcast --etherscan-api-key base --verify```

Once contracts are deployed, add generated _addAddress function calls into the Addresses.sol constructor.

Create the calldata to submit on the proposing chain, for testnet fork base goerli:

```forge test --match-test testPrintCalldata -vvv --fork-url baseGoerli```

for mainnet calldata:

```forge test --match-test testPrintCalldata -vvv --fork-url base```

Then, scroll up to get the calldata after section "artemis governor queue governance calldata", and send the calldata to the governance contract on moonbase by going to metamask and submitting a transaction to the ArtemisGovernor contract with the calldata the raw hex copied.

Once the calldata is sent, wait for the proposal to finish the voting period, then queue and execute it.

If on base goerli, send .00001 eth to the Temporal Governor contract. If on mainnet, send .00001 eth to the Temporal Governor contract and all required amounts for other tokens as well.

After the proposal is executed, get the proposal execute transaction hash, and pass the transaction hash to the VAA script.

Once the VAA is generated, go through the steps to submit the VAA to the Temporal Governor on the destination chain.

1. Submit the generated VAA to the Temporal Governor on the destination chain by calling queueProposal.
2. Wait for the timelock to expire. Then submit the same VAA bytes to the Temporal Governor by calling executeProposal. This should execute the proposal.
