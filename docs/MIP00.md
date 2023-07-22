# MIP 00

MIP 00 deploys, parameterizes and simulates the execution of a cross chain governance proposal to instantiate the Moonwell Protocool on base.

## Deploy: Deploy Smart Contract System

The `deploy` function in this script is responsible for deploying the Moonwell system contracts.

Here is an overview of the smart contracts being deployed and their function:

1. **TemporalGovernor**: The `TemporalGovernor` contract acts as the governance system for the protocol. The governor has control over certain protocol parameters and decisions. In this script, the `TemporalGovernor` is initialized with `WORMHOLE_CORE` as the core address, `proposalDelay` and `permissionlessUnpauseTime` as time settings, and `trustedSenders` as the trusted entities.

2. **MultiRewardDistributor**: This contract is responsible for distributing multiple types of rewards to borrowers and lenders of the Moonwell Protocol. Users interact with this contract through the `TransparentUpgradeableProxy`.

3. **Unitroller** and **Comptroller**: The `Unitroller` acts as a proxy contract for the `Comptroller`. The `Comptroller` contract is the risk management layer of the protocol and controls parameters such as collateralization ratios and liquidation incentives.

4. **ProxyAdmin**: This contract is a transparent proxy administration contract. It helps manage and upgrade the protocol. This ProxyAdmin will own the Proxy that sits on top of the MultiRewardDistributor. The admin of the proxy is the `TemporalGovernor`.

5. **TransparentUpgradeableProxy**: This contract proxies the `MultiRewardDistributor` contract, allowing it to be upgraded without changing the contract address that users interact with and change business logic after the contract is deployed.

6. **MErc20Delegate**: This contract serves as the logic layer for the mToken, which are the protocol's native interest-bearing tokens.

7. **JumpRateModel**: This contract sets the interest rate model for the protocol. The JumpRateModel is an interest rate model that increases interest rates quickly when utilization is high.

8. **MErc20Delegator**: For each supported asset, a new `MErc20Delegator` contract is deployed. This contract allows users to earn interest on their assets by interacting with the underlying lending market. The `MErc20Delegator` delegatecalls all user calls to the `MErc20Delegate`.

9. **WETHRouter**: This contract facilitates transactions involving WETH, the wrapped version of Ethereum that's compliant with the ERC20 standard. This allows users to mint mTokens with raw ETH without having to wrap into WETH themselves.

10. **ChainlinkOracle**: This contract is responsible for providing reliable and secure price feeds for the protocol. It is initialized with "null_asset".

The function also adds the deployed contract addresses to an `Addresses` contract for easy reference and stores specific configuration settings for the deployed contracts. This includes initial exchange rates for the mTokens and the configuration of the JumpRateModel.

Please note that the specific details can vary depending on the specific implementation and requirements of your project.

## AfterDeploy: Handle Post Deployment Cleanup Actions

The `afterDeploy` function handles post deployment cleanup actions after the initial deployment of smart contracts.

Here's a summary of what it does:

1. It retrieves already deployed smart contract instances by their stored addresses. This includes `ProxyAdmin`, `Unitroller`, `TemporalGovernor` and `ChainlinkOracle` contracts.

2. It transfers ownership of the `ProxyAdmin` to the `TemporalGovernor`. This implies that the `TemporalGovernor` contract has control over the `ProxyAdmin` contract and hence can handle upgrades of the proxied contracts.

3. It sets the price oracle in the `Comptroller` to the `ChainlinkOracle`. This means that the `Comptroller` uses the `ChainlinkOracle` to fetch the price of assets in the protocol.

4. It initializes arrays to hold the `mTokens`, `supplyCaps`, and `borrowCaps` for the different markets in the protocol.

5. It then loops over the `cTokenConfigs`, setting the price feed in the `ChainlinkOracle` for each token, supporting the market in the `Comptroller` (which effectively means adding the market to the protocol), and pausing the minting of `mTokens`.

6. After it's looped over all markets, it sets the supply and borrow caps for each market in the `Comptroller`.

7. It sets the `TemporalGovernor` as the pending admin for the `Unitroller`, indicating an upcoming transfer of admin control.

8. Finally, it sets the `TemporalGovernor` as the admin of the `ChainlinkOracle`, granting control over the oracle settings.

No new contracts are being deployed in this function; it only interacts with the ones already deployed and stored in the `Addresses` contract.

## Build: Cross Chain Gov Proposal Steps

The `build` function in the deployment script contains the final steps to properly configure the deployment and prepare it for operation. It does so by using cross-chain actions which are essentially transaction calls to different contracts and their methods. Here is a detailed breakdown of what happens in the `build` function:

1. **Unitroller Configuration**: It calls the `_acceptAdmin()` method of the `Unitroller` contract, where the temporal governor (a kind of admin for this system) accepts their role.

2. **Set mint unpaused for all of the deployed MTokens**: For each of the MTokens that are part of the deployed market, it sets their minting status to unpaused, which allows for the creation of new tokens in that market. This is done using the `_setMintPaused` method of the `Unitroller` contract.

3. **Token Approvals**: Approves the newly minted tokens to be spent in their respective markets. This is done by calling the `approve` method on each underlying asset token, giving approval to the corresponding MToken contract to spend a certain amount (`initialMintAmount`) of the asset token on behalf of the deployer.

4. **Initialize markets**: Calls the `mint` function on each of the MToken contracts to mint the initial amount of tokens, thus initializing the market and preventing potential exploits.

5. **Set Collateral Factor on CToken**: For each market, it sets the collateral factor, which is an important parameter in calculating the maximum borrowable amount against a certain collateral. This is done by calling the `_setCollateralFactor` method of the `Unitroller` contract.

6. **Set Liquidation Incentive on CToken**: Sets the liquidation incentive, which is the reward given to users who participate in the liquidation of a loan. This is done by calling the `_setLiquidationIncentive` method of the `Unitroller` contract.

7. **Set Close Factor on CToken**: Sets the close factor, which determines what percentage of a borrower's total borrowed value they can repay in a single transaction. This is done by calling the `_setCloseFactor` method of the `Unitroller` contract.

8. **Set Reward Distributor on Comptroller**: Sets the reward distributor on the Comptroller contract. The reward distributor is the contract that will handle the distribution of rewards to the participants of the market.

9. **Set Pause Guardian**: Sets the pause guardian in the `Unitroller` contract. The pause guardian is a role that has the authority to pause certain actions in the system in case of an emergency.

10. **Emission Configuration**: Adds emission configuration for each MToken, specifying the tokens to be emitted as rewards, the rate of emission, and the ending time for emissions. This is done by calling the `_addEmissionConfig` method on the `MRD_PROXY` contract.

In summary, the `build` function is responsible for the final configuration and initialization of the markets, as well as the setting up of necessary roles, and parameters that govern the functioning of the markets. It ensures that everything is ready for operations to begin.

## Run: Cross Chain Proposal

The `run` function in the deploy script takes the actions generated in the build function, pranks as the TemporalGovernor contract and then executes all the actions specified in the build script.

## Validate: Parameters

The `validate` function in the deploy script observes the smart contracts after they have been deployed and the run function has applied all states changes from the governance proposal.
