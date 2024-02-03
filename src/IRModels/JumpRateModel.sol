// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "./InterestRateModel.sol";
import "../SafeMath.sol";

/**
 * @title Moonwell's JumpRateModel Contract
 * @author Compound
 * @author Moonwell
 */
contract JumpRateModel is InterestRateModel {
    using SafeMath for uint;

    event NewInterestParams(
        uint baseRatePerTimestamp,
        uint multiplierPerTimestamp,
        uint jumpMultiplierPerTimestamp,
        uint kink
    );

    /**
     * @notice The approximate number of timestamps per year that is assumed by the interest rate model
     */
    uint public constant timestampsPerYear = 60 * 60 * 24 * 365;

    /**
     * @notice The multiplier of utilization rate that gives the slope of the interest rate
     */
    uint public multiplierPerTimestamp;

    /**
     * @notice The base interest rate which is the y-intercept when utilization rate is 0
     */
    uint public baseRatePerTimestamp;

    /**
     * @notice The multiplierPerTimestamp after hitting a specified utilization point
     */
    uint public jumpMultiplierPerTimestamp;

    /**
     * @notice The utilization point at which the jump multiplier is applied
     */
    uint public kink;

    /// @dev we know that we do not need to use safemath, however safemath is still used for safety
    /// and to not modify existing code.

    /**
     * @notice Construct an interest rate model
     * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
     * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
     * @param jumpMultiplierPerYear The multiplierPerTimestamp after hitting a specified utilization point
     * @param kink_ The utilization point at which the jump multiplier is applied
     */
    constructor(
        uint baseRatePerYear,
        uint multiplierPerYear,
        uint jumpMultiplierPerYear,
        uint kink_
    ) {
        baseRatePerTimestamp = baseRatePerYear
            .mul(1e18)
            .div(timestampsPerYear)
            .div(1e18);
        multiplierPerTimestamp = multiplierPerYear
            .mul(1e18)
            .div(timestampsPerYear)
            .div(1e18);
        jumpMultiplierPerTimestamp = jumpMultiplierPerYear
            .mul(1e18)
            .div(timestampsPerYear)
            .div(1e18);
        kink = kink_;

        emit NewInterestParams(
            baseRatePerTimestamp,
            multiplierPerTimestamp,
            jumpMultiplierPerTimestamp,
            kink
        );
    }

    /**
     * @notice Calculates the utilization rate of the market: `borrows / (cash + borrows - reserves)`
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market (currently unused)
     * @return The utilization rate as a mantissa between [0, 1e18]
     */
    function utilizationRate(
        uint cash,
        uint borrows,
        uint reserves
    ) public pure returns (uint) {
        // Utilization rate is 0 when there are no borrows
        if (borrows == 0) {
            return 0;
        }

        return borrows.mul(1e18).div(cash.add(borrows).sub(reserves));
    }

    /**
     * @notice Calculates the current borrow rate per timestamp, with the error code expected by the market
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @return The borrow rate percentage per timestamp as a mantissa (scaled by 1e18)
     */
    function getBorrowRate(
        uint cash,
        uint borrows,
        uint reserves
    ) public view override returns (uint) {
        uint util = utilizationRate(cash, borrows, reserves);

        if (util <= kink) {
            return
                util.mul(multiplierPerTimestamp).div(1e18).add(
                    baseRatePerTimestamp
                );
        } else {
            uint normalRate = kink.mul(multiplierPerTimestamp).div(1e18).add(
                baseRatePerTimestamp
            );
            uint excessUtil = util.sub(kink);
            return
                excessUtil.mul(jumpMultiplierPerTimestamp).div(1e18).add(
                    normalRate
                );
        }
    }

    /**
     * @notice Calculates the current supply rate per timestamp
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @param reserveFactorMantissa The current reserve factor for the market
     * @return The supply rate percentage per timestamp as a mantissa (scaled by 1e18)
     */
    function getSupplyRate(
        uint cash,
        uint borrows,
        uint reserves,
        uint reserveFactorMantissa
    ) public view override returns (uint) {
        uint oneMinusReserveFactor = uint(1e18).sub(reserveFactorMantissa);
        uint borrowRate = getBorrowRate(cash, borrows, reserves);
        uint rateToPool = borrowRate.mul(oneMinusReserveFactor).div(1e18);
        return
            utilizationRate(cash, borrows, reserves).mul(rateToPool).div(1e18);
    }
}
