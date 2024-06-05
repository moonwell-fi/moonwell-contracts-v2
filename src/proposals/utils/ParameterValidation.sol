//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19;

import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {JumpRateModel} from "@protocol/irm/JumpRateModel.sol";
import {MToken} from "@protocol/MToken.sol";
import {Comptroller} from "@protocol/Comptroller.sol";

contract ParameterValidation is Test {
    uint256 public constant timestampsPerYear = 60 * 60 * 24 * 365;
    uint256 public constant SCALE = 1e18;

    struct IRParams {
        uint256 kink;
        uint256 baseRatePerTimestamp;
        uint256 multiplierPerTimestamp;
        uint256 jumpMultiplierPerTimestamp;
    }

    function _validateJRM(
        address jrmAddress,
        address tokenAddress,
        IRParams memory params
    ) internal {
        JumpRateModel jrm = JumpRateModel(jrmAddress);
        assertEq(
            address(MToken(tokenAddress).interestRateModel()),
            address(jrm),
            "interest rate model not set correctly"
        );

        assertEq(jrm.kink(), params.kink, "kink verification failed");
        assertEq(
            jrm.timestampsPerYear(),
            timestampsPerYear,
            "timestamps per year verifiacation failed"
        );
        assertEq(
            jrm.baseRatePerTimestamp(),
            (params.baseRatePerTimestamp * SCALE) / timestampsPerYear / SCALE,
            "base rate per timestamp validation failed"
        );
        assertEq(
            jrm.multiplierPerTimestamp(),
            (params.multiplierPerTimestamp * SCALE) / timestampsPerYear / SCALE,
            "multiplier per timestamp validation failed"
        );
        assertEq(
            jrm.jumpMultiplierPerTimestamp(),
            (params.jumpMultiplierPerTimestamp * SCALE) /
                timestampsPerYear /
                SCALE,
            "jump multiplier per timestamp validation failed"
        );
    }

    function _validateCF(
        Addresses addresses,
        address tokenAddress,
        uint256 collateralFactor
    ) internal {
        address unitrollerAddress = addresses.getAddress("UNITROLLER");
        Comptroller unitroller = Comptroller(unitrollerAddress);

        (bool listed, uint256 collateralFactorMantissa) = unitroller.markets(
            tokenAddress
        );

        assertTrue(listed);

        assertEq(
            collateralFactorMantissa,
            collateralFactor,
            "collateral factor validation failed"
        );
    }

    function _validateRF(address tokenAddress, uint256 reserveFactor) internal {
        MToken token = MToken(tokenAddress);

        uint256 reserveFactorMantissa = token.reserveFactorMantissa();

        assertEq(
            reserveFactorMantissa,
            reserveFactor,
            "reserve factor validation failed"
        );
    }
}
