# JumpRateModel

## Description

The JumpRateModel is a smart contract developed by Moonwell based on Compound's
InterestRateModel. It implements methods to calculate supply and borrow interest
rates per timestamp.

The contract uses SafeMath library for mathematical operations, providing
underflow and overflow safety.

## Contract Details

### Constants

- `timestampsPerYear`: The number of timestamps per year (60*60*24\*365).
- `isInterestRateModel`: A constant boolean value set to `true`, serving as an
  indicator that this contract implements an InterestRateModel.

### State Variables

- `multiplierPerTimestamp`: The utilization rate multiplier that gives the slope
  of the interest rate.
- `baseRatePerTimestamp`: The base interest rate which is the y-intercept when
  utilization rate is 0.
- `jumpMultiplierPerTimestamp`: The `multiplierPerTimestamp` after hitting a
  specified utilization point.
- `kink`: The utilization point at which the `jumpMultiplierPerTimestamp` is
  applied.

### Events

- `NewInterestParams`: Emitted when a new JumpRateModel is constructed. It
  provides details about the base rate, multiplier, jump multiplier, and kink.

### Methods

- `constructor(uint baseRatePerYear, uint multiplierPerYear, uint jumpMultiplierPerYear, uint kink_)`:
  Initializes a new JumpRateModel with given parameters.

- `utilizationRate(uint cash, uint borrows, uint reserves)`: Calculates the
  utilization rate of the market (`borrows / (cash + borrows - reserves)`).
  Returns the utilization rate as a mantissa between [0, 1e18].

- `getBorrowRate(uint cash, uint borrows, uint reserves)`: Calculates the
  current borrow rate per timestamp based on market utilization rate.

- `getSupplyRate(uint cash, uint borrows, uint reserves, uint reserveFactorMantissa)`:
  Calculates the current supply rate per timestamp.

## Remarks

1. The contract utilizes SafeMath for mathematical operations even though it is
   not necessary with Solidity version 0.8.17. This is for safety and to
   preserve the existing code structure.

2. The `utilizationRate` method returns 0 when there are no borrows.

3. In the `getBorrowRate` method, if the utilization rate is below or equal to
   `kink`, the borrow rate is calculated using `multiplierPerTimestamp`. When
   the utilization rate exceeds `kink`, the `jumpMultiplierPerTimestamp` is
   applied.

4. The `getSupplyRate` method calculates the supply rate based on the borrow
   rate and the reserve factor of the market.
