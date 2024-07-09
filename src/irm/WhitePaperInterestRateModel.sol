// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "../SafeMath.sol";
import "./InterestRateModel.sol";

/**
 * @title Moonwell's WhitePaperInterestRateModel Contract
 * @author Moonwell
 * @notice The parameterized model described in section 2.4 of the original Moonwell Protocol whitepaper
 */
contract WhitePaperInterestRateModel is InterestRateModel {
    using SafeMath for uint256;

    event NewInterestParams(
        uint256 baseRatePerTimestamp, uint256 multiplierPerTimestamp
    );

    /**
     * @notice The approximate number of timestamps per year that is assumed by the interest rate model
     */
    uint256 public constant timestampsPerYear = 31536000;

    /**
     * @notice The multiplier of utilization rate that gives the slope of the interest rate
     */
    uint256 public multiplierPerTimestamp;

    /**
     * @notice The base interest rate which is the y-intercept when utilization rate is 0
     */
    uint256 public baseRatePerTimestamp;

    /**
     * @notice Construct an interest rate model
     * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
     * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
     */
    constructor(uint256 baseRatePerYear, uint256 multiplierPerYear) {
        baseRatePerTimestamp =
            baseRatePerYear.mul(1e18).div(timestampsPerYear).div(1e18);
        multiplierPerTimestamp =
            multiplierPerYear.mul(1e18).div(timestampsPerYear).div(1e18);

        emit NewInterestParams(baseRatePerTimestamp, multiplierPerTimestamp);
    }

    /**
     * @notice Calculates the utilization rate of the market: `borrows / (cash + borrows - reserves)`
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market (currently unused)
     * @return The utilization rate as a mantissa between [0, 1e18]
     */
    function utilizationRate(uint256 cash, uint256 borrows, uint256 reserves)
        public
        pure
        returns (uint256)
    {
        // Utilization rate is 0 when there are no borrows
        if (borrows == 0) {
            return 0;
        }

        return borrows.mul(1e18).div(cash.add(borrows).sub(reserves));
    }

    /**
     * @notice Calculates the current borrow rate per timestmp, with the error code expected by the market
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @return The borrow rate percentage per timestmp as a mantissa (scaled by 1e18)
     */
    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves)
        public
        view
        override
        returns (uint256)
    {
        uint256 ur = utilizationRate(cash, borrows, reserves);
        return
            ur.mul(multiplierPerTimestamp).div(1e18).add(baseRatePerTimestamp);
    }

    /**
     * @notice Calculates the current supply rate per timestmp
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @param reserveFactorMantissa The current reserve factor for the market
     * @return The supply rate percentage per timestmp as a mantissa (scaled by 1e18)
     */
    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactorMantissa
    ) public view override returns (uint256) {
        uint256 oneMinusReserveFactor = uint256(1e18).sub(reserveFactorMantissa);
        uint256 borrowRate = getBorrowRate(cash, borrows, reserves);
        uint256 rateToPool = borrowRate.mul(oneMinusReserveFactor).div(1e18);
        return
            utilizationRate(cash, borrows, reserves).mul(rateToPool).div(1e18);
    }
}
