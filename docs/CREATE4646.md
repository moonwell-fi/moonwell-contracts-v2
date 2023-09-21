# 4626 Market Creation

In order to create a market, you must first have a market creator account. This account will be funded with an initial mint amount to establish the share price of the market.

## Deployment Steps

1. Set REWARDS_RECEIVER to the address you want to receive rewards in Addresses.sol on the network you're deploying on.
2. Fund the deployer with the following token amounts:
- 1 USDBC
- 0.000001 weth
- 0.000001 cbeth
- 0.000001 dai

3. Set REWARDS_RECEIVER to the address you want to receive rewards in Addresses.sol
4. Run the following command to deploy and initialize the markets:
```
forge script proposals/Deploy4626Vaults.s.sol:Deploy4626Vaults \
    -vvvv \
    --rpc-url base \
    --broadcast --etherscan-api-key base --verify
```