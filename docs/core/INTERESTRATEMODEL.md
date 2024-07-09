# InterestRateModel

## Description

InterestRateModel is an abstract contract. It serves as an interface that provides the structure for calculating borrow
and supply interest rates per timestamp in the market.

The contract is intended to be inherited and the methods to be overridden and implemented by the child contracts.

## Contract Details

### Constants

-   `isInterestRateModel`: A constant boolean value set to `true`, indicating that this contract is an InterestRateModel
    contract.

### Methods

-   `getBorrowRate(uint cash, uint borrows, uint reserves)`: This abstract method is expected to be overridden by
    inheriting contracts. The purpose is to calculate the current borrow interest rate per timestamp given the market's
    total amount of cash, outstanding borrows, and reserves. The calculated borrow rate per timestamp is expected to be
    a percentage and scaled by 1e18.

-   `getSupplyRate(uint cash, uint borrows, uint reserves, uint reserveFactorMantissa)`: Another abstract method meant
    to be overridden. It calculates the current supply interest rate per timestamp using the market's total cash,
    outstanding borrows, total reserves, and the current reserve factor.

## Remarks

1. This contract is abstract and doesn't contain any implementation. It is designed to be inherited and its methods to
   be implemented by the child contracts.

2. Both `getBorrowRate` and `getSupplyRate` are view functions, meaning they don't modify the state and can be called
   without sending a transaction.

3. The return values of `getBorrowRate` and `getSupplyRate` are scaled by 1e18 for precision in Solidity.

4. While SafeMath is not explicitly used in this contract, it may be used in the implementations of these functions in
   the child contracts to prevent underflows and overflows.

5. The boolean constant `isInterestRateModel` serves as an indicator for contract inspection. It is not crucial for the
   functionality but can be helpful for validation and contract interaction checks.
