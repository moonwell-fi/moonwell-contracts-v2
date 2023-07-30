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

Once contracts are deployed, add generated _addAddress function calls into the Addresses.sol constructor.

Create the calldata to submit on the proposing chain, for testnet fork base goerli:

```forge test --match-test testPrintCalldata -vvv --fork-url baseGoerli```

Then, scroll up to get the calldata after section "artemis governor queue governance calldata", and send the calldata to the governance contract on moonbase by going to metamask and submitting a transaction to the ArtemisGovernor contract with the calldata the raw hex copied.

for mainnet calldata:

```forge test --match-test testPrintCalldata -vvv --fork-url base```

Once the calldata is sent, wait for the proposal to finish the voting period, then queue and execute it.

After the proposal is executed, get the proposal execute transaction hash, and pass the transaction hash to the VAA script.

Once the VAA is generated, go through the steps to submit the VAA to the Temporal Governor on the destination chain.

1. Submit the generated VAA to the Temporal Governor on the destination chain by calling queueProposal.
2. Wait for the timelock to expire. Then submit the same VAA bytes to the Temporal Governor by calling executeProposal. This should execute the proposal.
