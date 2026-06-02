// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {InitParams, LoanStatus} from "@protocol/marketplace/CreditTypes.sol";

interface ICreditLoan {
    function initialize(InitParams calldata params) external;

    function activate() external;

    function makePayment() external;

    function claimMissedPayment() external;

    function forceDefault() external;

    function forceDefaultStaleOracle() external;

    function seizeAll() external;

    function repayLoanAfterDefault(uint256 repayAmount) external;

    function redeemAndReturn() external;

    function status() external view returns (LoanStatus);

    function nextPaymentDueAt() external view returns (uint64);

    function remainingPayments() external view returns (uint32);

    function totalOwedNow()
        external
        view
        returns (uint256 principal, uint256 interest);

    function collateralRemaining() external view returns (uint256);
}
