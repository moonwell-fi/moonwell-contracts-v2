# WETHRouter

## Overview

The `WETHRouter` contract is designed to facilitate a straightforward
interaction with the Moonwell protocol for end users that hold ETH in their
wallet. It wraps raw Ethereum (ETH) into Wrapped Ethereum (WETH) before
depositing into Moonwell, allowing for a single transaction to both add and
remove ETH liquidity.

This contract interacts with several other contracts:

- **SafeERC20**: a library provided by OpenZeppelin that provides safe versions
  of the ERC20 operations that throw on failure.
- **IERC20**: the standard interface for Ethereum tokens.
- **WETH9**: the standard implementation of WETH, wrapped Ether.
- **MErc20**: a custom ERC20 contract used in the Moonwell protocol.

## Contract Architecture

### State Variables

- `weth`: This public, immutable state variable holds the address of the WETH9
  contract.
- `mToken`: This public, immutable state variable holds the address of the
  MErc20 contract.

### Constructor

- The constructor is called when the contract is deployed. It takes two
  parameters - the addresses of the WETH9 and MErc20 contracts. It sets these
  addresses to the state variables and approves the mToken contract to spend the
  maximum amount of WETH.

### Functions

#### mint()

- This function is used to deposit raw ETH into the Moonwell protocol.
- It takes a `recipient` parameter - the address to receive the mToken.
- It's marked as `payable` so it can receive Ether.
- First, the function deposits all sent ETH into the WETH contract.
- Then it mints mTokens of equivalent value, minus some rounding error in the
  Compound math.
- If the MToken minting operation fails, it throws an error with the message
  "WETHRouter: mint failed".
- After minting, it transfers the mToken balance of the WETHRouter to the
  recipient using the `safeTransfer` method from the SafeERC20 library to check
  the ERC20 transfer happened successfully.

#### redeem()

- This function is used to redeem an mToken for raw ETH.
- It takes two parameters: `mTokenRedeemAmount` and `recipient`. The first one
  represents the amount of mToken to redeem, and the second one is the address
  to receive the ETH.
- First, it transfers the specified amount of mToken from the sender to the
  WETHRouter using the `safeTransferFrom` method from the SafeERC20 library to
  check that the transfer from the sender to this contract succeeded.
- Then it redeems the mToken for WETH. If the redeem operation fails, it throws
  an error with the message "WETHRouter: redeem failed".
- After redeeming, it withdraws the WETH to ETH and attempts to transfer the
  total balance of the contract to the recipient.
- If the ETH transfer fails, it throws an error with the message "WETHRouter:
  ETH transfer failed".

#### receive()

- This function is used to receive Ether. It's marked as `external payable` but
  doesn't perform any operations.

## Edge Cases & Considerations

- If the minting or redeeming of mTokens fails for any reason, the function will
  throw an error and revert the transaction. This is expected behavior as
  Compound `mint` and `redeem` functions can both fail silently, leaving tokens
  stuck in the contract if the call didn't fail.
- If the transfer of ETH in the `redeem` function fails, for example due to the
  call stack being too deep or the recipient contract throwing an error, the
  function will throw an error and revert the transaction.
- The contract's balance of WETH is always fully approved for the mToken
  contract to spend. If the mToken contract is compromised, all WETH held by the
  contract could be stolen. However, both of these conditions being true is
  unlikely given the WETHRouter is non custodial, meaning it should never hold
  user funds once the transaction ends.
