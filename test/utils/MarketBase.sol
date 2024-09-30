//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";

import {MToken} from "@protocol/MToken.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {ExponentialNoError} from "@protocol/ExponentialNoError.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract MarketBase is ExponentialNoError {
    Comptroller comptroller;
    Addresses addresses;

    function setUp() public virtual {
        addresses = new Addresses();
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
    }

    function _getMaxSupplyAmount(MToken mToken) internal returns (uint256) {
        mToken.accrueInterest();

        uint256 supplyCap = comptroller.supplyCaps(address(mToken));

        if (supplyCap == 0) {
            return type(uint128).max;
        }

        console.log("supply cap", supplyCap);

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
}
