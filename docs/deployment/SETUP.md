## Live System Contracts

Currently the Moonwell contracts are deployed on the following chains:

- Moonbeam
- Moonbase
- Base Mainnet
- Base Sepolia

All the addresses are stored in the `Addresses.json` file with their respective
chain ids.

## Deploying

This section outlines the steps to deploy the system contracts to a new chain.

### Set Environment Variables

Set `ETH_PRIVATE_KEY = "0x..."` to .env file or export it in the shell. This is
the private key of the account that will deploy the contracts.

### Clean addresses from Addresses.json

When redeploying the contracts to a chain that already has the contracts
deployed, the addresses to the respective chain in the `Addresses.json` file
should be removed. If you don't remove, the deployment script will skip the
deployment of the contracts that already have an address in the
`Addresses.json`.

### Running the Deployment Script

`forge script src/proposals/DeployProposal.s.sol:DeployProposal -vvv --rpc-url baseSepolia --with-gas-price 100000000 --skip-simulation --slow --gas-estimate-multiplier 200 --broadcast --etherscan-api-key baseSepolia --verify`

Substitute out the rpc-url for the chain to deploy on if the destination is not
base Sepolia.

If deploying on mainnet, double check that `mainnetMTokens.json` and
`mainnetRewardStreams.json` in the `proposals/` folder are correctly filled out.
Then, double check that in `Addresses.json`, all the oracles, tokens and
guardians are correctly set. If no reward streams will be created, ensure the
rewards json file is an empty array. Triple check that the addresses for the
system are correct in `Addresses.json`, then deploy to base mainnet:

`forge script src/proposals/DeployProposal.s.sol:DeployProposal -vvv --rpc-url base --with-gas-price 100000000 --skip-simulation --slow --gas-estimate-multiplier 200 --broadcast --etherscan-api-key base --verify`

Once contracts are deployed, add generated addresses into the Addresses.json
file.

### Submitting Governance Proposal

After the contracts are deployed, the next step is to submit a governance
proposal to MultichainGovernor to accept the ownership of the system contracts.

Create the calldata to submit on the proposing chain, for testnet fork base
sepolia:

`forge test --match-test testPrintCalldata -vvv --fork-url baseGoerli`

for mainnet calldata:

`forge test --match-test testPrintCalldata -vvv --fork-url base`

Then, scroll up to get the calldata after section "artemis governor queue
governance calldata", and send the calldata to the governance contract on
moonbase by going to metamask and submitting a transaction to the
ArtemisGovernor contract with the calldata the raw hex copied.

Once the calldata is sent, wait for the proposal to finish the voting period,
then queue and execute it.

If on base sepolia , send .00001 eth to the Temporal Governor contract. If on
mainnet, send .00001 eth to the Temporal Governor contract and all required
amounts for other tokens as well.

After the proposal is executed, get the proposal execute transaction hash, and
pass the transaction hash to the VAA script.

Once the VAA is generated, go through the steps to submit the VAA to the
Temporal Governor on the destination chain.

1. Submit the generated VAA to the Temporal Governor on the destination chain by
   calling queueProposal.
2. Wait for the timelock to expire. Then submit the same VAA bytes to the
   Temporal Governor by calling executeProposal. This should execute the
   proposal.
