# Comptroller

## 1. Introduction

The Comptroller manages the user's account health and facilitates entering and
exiting marketplaces for specific assets.

## 2. Hooks

### MToken Policy Hooks

The Comptroller includes various policy hooks to handle permissions, token
minting and redemption, borrowing and loan repayment, liquidation, and asset
transfers within a given market.

### mintAllowed

This function checks if the account is allowed to mint tokens in the given
market. It considers factors such as minting pause status, market listing, and
whether the mint amount exceeds the market's supply cap. If conditions are met,
the function updates and distributes supplier rewards for the token.

Parameters:

- `mToken`: The market to verify the mint against
- `minter`: The account which would receive the minted tokens
- `mintAmount`: The amount of underlying supplied to the market in exchange for
  tokens

Returns: `0` if the mint is allowed, otherwise a semi-opaque error code (See
`ErrorReporter.sol`)

### redeemAllowed

This function checks if the account is allowed to redeem tokens in the given
market. If redemption is allowed, it updates and distributes supplier rewards
for the token.

Parameters:

- `mToken`: The market to verify the redemption against
- `redeemer`: The account which would redeem the tokens
- `redeemTokens`: The number of mTokens to exchange for the underlying asset in
  the market

Returns: `0` if the redemption is allowed, otherwise a semi-opaque error code
(See `ErrorReporter.sol`)

### redeemVerify

This function validates redeeming and reverts on rejection. It may emit logs.

Parameters:

- `mToken`: The asset being redeemed
- `redeemer`: The address redeeming the tokens
- `redeemAmount`: The amount of the underlying asset being redeemed
- `redeemTokens`: The number of tokens being redeemed

### borrowAllowed

This function checks if the account is allowed to borrow the underlying asset of
the given market. It takes into account factors like borrowing pause status,
market listing, and whether the borrow amount exceeds the market's borrow cap.

Parameters:

- `mToken`: The market to verify the borrow against
- `borrower`: The account which would borrow the asset
- `borrowAmount`: The amount of underlying the account would borrow

Returns: `0` if the borrow is allowed, otherwise a semi-opaque error code (See
`ErrorReporter.sol`)

### repayBorrowAllowed

This function checks if the account is allowed to repay a borrow in the given
market.

Parameters:

- `mToken`: The market to verify the repayment against
- `payer`: The account which would repay the asset
- `borrower`: The account which borrowed the asset
- `repayAmount`: The amount of the underlying asset the account would repay

Returns: `0` if the repayment is allowed, otherwise a semi-opaque error code
(See `ErrorReporter.sol`)

### liquidateBorrowAllowed

This function checks if liquidation is allowed to occur. The borrower must have
a shortfall in order to be liquidated.

Parameters:

- `mTokenBorrowed`: The asset borrowed by the borrower
- `mTokenCollateral`: The asset used as collateral and will be seized
- `liquidator`: The address repaying the borrow and seizing the collateral
- `borrower`: The address of the borrower
- `repayAmount`: The amount of underlying being repaid

Returns: `0` if the liquidation is allowed, otherwise a semi-opaque error code
(See `ErrorReporter.sol`)

### seizeAllowed

This function checks if seizing of assets is allowed to occur.

Parameters:

- `mTokenCollateral`: The asset used as collateral and will be seized
- `mTokenBorrowed`: The asset borrowed by the borrower
- `liquidator`: The address repaying the borrow and seizing the collateral
- `borrower`: The address of the borrower
- `seizeTokens`: The number of collateral tokens to seize

Returns: `0` if the seizure is allowed, otherwise a semi-opaque error code (See
`ErrorReporter.sol`)

### transferAllowed

This function checks if the account should be allowed to transfer MTokens in the
given market.

Parameters:

- `mToken`: The market to verify the transfer against
- `src`: The account which sends the MTokens
- `dst`: The account which receives the MTokens
- `transferTokens`: The number of MTokens to transfer

Returns: `0` if the transfer is allowed, otherwise a semi-opaque error code (See
`ErrorReporter.sol`)

## 3. Account Liquidity Calculations

The Comptroller uses a struct named `AccountLiquidityLocalVars` to calculate
account liquidity without exceeding stack-depth limits. This struct contains
various parameters related to collateral, borrowed amount, exchange rates, and
oracle prices.

The Comptroller provides functions to determine the current account liquidity
with respect to collateral requirements, hypothetical account liquidity, and
calculate the number of tokens to seize in a liquidation.

## 4. Admin Actions

The following functions can only be performed by the admin of the Comptroller:

1. `_supportMarket(MToken mToken)`: Enables the admin to list a new market.

2. `_setMarketBorrowCaps(MToken[] calldata mTokens, uint[] calldata newBorrowCaps)`:
   Allows the admin or borrowCapGuardian to set the borrow caps for an array of
   mToken markets.

3. `_setBorrowCapGuardian(address newBorrowCapGuardian)`: Allows the admin to
   change the borrowCapGuardian.

4. `_setMarketSupplyCaps(MToken[] calldata mTokens, uint[] calldata newSupplyCaps)`:
   Allows the admin or supplyCapGuardian to set the supply caps for an array of
   mToken markets.

5. `_setSupplyCapGuardian(address newSupplyCapGuardian)`: Allows the admin to
   change the supplyCapGuardian.

6. `_setPauseGuardian(address newPauseGuardian)`: Allows the admin to change the
   pauseGuardian.

7. `_setRewardDistributor(MultiRewardDistributor newRewardDistributor)`: Allows
   the admin to change the rewardDistributor.

8. `_setMintPaused(MToken mToken, bool state)`,
   `_setBorrowPaused(MToken mToken, bool state)`,
   `_setTransferPaused(bool state)`, `_setSeizePaused(bool state)`: Allow the
   pauseGuardian or admin to pause or unpause minting, borrowing, transferring,
   and seizing actions for listed markets.

9. `_become(Unitroller unitroller)`: Allows the unitroller admin to change the
   controller of the unitroller.

10. `_rescueFunds(address _tokenAddress, uint _amount)`: Allows the admin to
    transfer ERC-20 tokens from the comptroller contract to the admin.

## 4. Rewards Distribution

This piece of smart contract code manages the distribution of the WELL token as
rewards to both suppliers and borrowers in a specific market by calling the
MultiRewardDistributor contract.

## Functions

1. `updateAndDistributeSupplierRewardsForToken(address mToken, address supplier)`:
   Distributes WELL rewards to a supplier in a particular market.

2. `updateAndDistributeBorrowerRewardsForToken(address mToken, address borrower)`:
   Distributes WELL rewards to a borrower in a particular market.

3. `claimReward()`: Claims all accrued WELL rewards for the function caller in
   all markets.

4. `claimReward(address holder)`: Claims all accrued WELL rewards for a specific
   holder in all markets.

5. `claimReward(address holder, MToken[] memory mTokens)`: Claims all accrued
   WELL rewards for a specific holder in specified markets.

6. `claimReward(address[] memory holders, MToken[] memory mTokens, bool borrowers, bool suppliers)`:
   Claims all rewards for a specified group of users, tokens, and market sides.

7. `getAllMarkets()`: Returns the list of all MToken markets listed in the
   Comptroller.

## Noteworthy Points for Auditors

1. Function Access: Most functions are either internal or public, allowing
   access from within the contract or by external users/contracts. ACL rules are
   in place to only allow the contract admin ability to change key variables.

2. Dependency: The contract relies heavily on the `MultiRewardDistributor`
   contract, so vulnerabilities in the `MultiRewardDistributor` could impact
   this contract.

3. Updation of Indices: The contract ensures that relevant market indices are
   updated before distributing rewards, which may require careful implementation
   in the `MultiRewardDistributor` as an error could stop normal operation of
   the Comptroller.

4. Checks: The `claimReward` function checks if supplied markets are listed to
   prevent incorrect distribution.
