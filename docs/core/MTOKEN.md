# MToken Contract

### Description

The MToken contract is an abstract contract that defines the core
functionalities for a tokenized lending market. It provides a standard interface
for ERC-20 compatible tokens with additional functionalities to support
borrowing, lending, and interest accrual. This contract is intended to be
inherited by specific token implementations.

### Dependencies

The MToken contract depends on the following interfaces and libraries:

- ComptrollerInterface.sol: Interface for the Comptroller contract that controls
  market operations.
- MTokenInterfaces.sol: Interface for the MToken contract.
- ErrorReporter.sol: Error reporting library for handling errors.
- Exponential.sol: Library for handling fixed-point arithmetic.
- EIP20Interface.sol: Interface for ERC-20 tokens.
- IRModels/InterestRateModel.sol: Interface for the interest rate model.

### User Functions

1. **transfer**: Transfers a specified amount of tokens to a target address.
2. **transferFrom**: Transfers tokens from a source address to a target address
   on behalf of an approved spender.
3. **approve**: Approves a spender to spend a specific amount of tokens on
   behalf of the owner.
4. **allowance**: Returns the amount of tokens the spender is allowed to spend
   on behalf of the owner.
5. **balanceOf**: Returns the balance of tokens for a specific account.
6. **balanceOfUnderlying**: Returns the balance of underlying assets (tokens)
   for a specific account.
7. **getAccountSnapshot**: Returns various account metrics, including token
   balance, borrow balance, and exchange rate.
8. **borrowRatePerTimestamp**: Returns the current borrow interest rate per
   block timestamp.
9. **supplyRatePerTimestamp**: Returns the current supply interest rate per
   block timestamp.
10. **totalBorrowsCurrent**: Returns the total amount of outstanding borrows
    after accruing interest.
11. **borrowBalanceCurrent**: Returns the current borrow balance of a specific
    account after accruing interest.
12. **borrowBalanceStored**: Returns the stored borrow balance of a specific
    account without accruing interest.
13. **exchangeRateCurrent**: Returns the current exchange rate between the token
    and underlying assets after accruing interest.
14. **exchangeRateStored**: Returns the stored exchange rate between the token
    and underlying assets without accruing interest.
15. **accrueInterest**: Accrues interest for the market, updating total borrows,
    total reserves, and borrow index.

### Admin Functions

1. **initialize**: Initializes the market with initial parameters. This function
   can only be called by the contract's admin.
2. **\_setPendingAdmin**: External function to set the pending admin of the
   contract.
3. **\_acceptAdmin**: External function to accept the admin role after being
   nominated as the pending admin.
4. **\_setComptroller**: External function to set the Comptroller contract
   address.
5. **\_setReserveFactor**: External function to set the reserve factor for the
   market.
6. **\_reduceReserves**: External function to reduce reserves by a specified
   amount.
7. **\_setInterestRateModel**: External function to set the interest rate model
   for the market.
8. **\_setProtocolSeizeShare**: External function to set the share of seized
   funds distributed to the protocol.
