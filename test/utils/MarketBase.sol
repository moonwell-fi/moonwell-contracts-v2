//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";

import {MToken} from "@protocol/MToken.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {ExponentialNoError} from "@protocol/ExponentialNoError.sol";

contract MarketBase is ExponentialNoError {
    Comptroller comptroller;

    constructor(Comptroller _comptroller) {
        comptroller = _comptroller;
    }

    function getMaxSupplyAmount(MToken mToken) public returns (uint256) {
        mToken.accrueInterest();

        uint256 supplyCap = comptroller.supplyCaps(address(mToken));

        if (supplyCap == 0) {
            return type(uint128).max;
        }

        uint256 totalCash = mToken.getCash();
        uint256 totalBorrows = mToken.totalBorrows();
        uint256 totalReserves = mToken.totalReserves();

        uint256 totalSupplies = sub_(
            add_(totalCash, totalBorrows),
            totalReserves
        );

        if (totalSupplies - 1 >= supplyCap) {
            return 0;
        }

        return supplyCap - totalSupplies - 1;
    }

    function getMaxBorrowAmount(MToken mToken) public view returns (uint256) {
        uint256 borrowCap = comptroller.borrowCaps(address(mToken));
        uint256 totalBorrows = mToken.totalBorrows();

        return borrowCap > 0 ? borrowCap - totalBorrows : type(uint128).max;
    }

    function getMaxUserBorrowAmount(
        MToken mToken,
        address user
    ) public view returns (uint256) {
        uint256 borrowCap = comptroller.borrowCaps(address(mToken));
        uint256 totalBorrows = mToken.totalBorrows();

        (, uint256 mTokenBalance, , uint256 exchangeRate) = mToken
            .getAccountSnapshot(user);

        uint256 oraclePrice = comptroller.oracle().getUnderlyingPrice(mToken);

        (, uint256 collateralFactor) = comptroller.markets(address(mToken));

        uint256 tokenToDenom = mul_(
            mul_(collateralFactor, exchangeRate) / 1e18,
            oraclePrice
        ) / 1e18;

        uint256 usdLiquidity = mul_(tokenToDenom, mTokenBalance);

        uint256 maxUserBorrow = usdLiquidity / oraclePrice;

        uint256 borrowableAmount = borrowCap > 0
            ? borrowCap - totalBorrows
            : type(uint128).max;

        if (maxUserBorrow == 0 || borrowableAmount == 0) {
            return 0;
        }

        return (
            borrowableAmount > maxUserBorrow
                ? maxUserBorrow - 1
                : borrowableAmount - 1
        );
    }
}
