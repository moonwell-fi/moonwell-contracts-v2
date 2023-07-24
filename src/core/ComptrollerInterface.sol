// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

abstract contract ComptrollerInterface {
    /// @notice Indicator that this is a Comptroller contract (for inspection)
    bool public constant isComptroller = true;

    /*** Assets You Are In ***/

    function enterMarkets(address[] calldata mTokens) virtual external returns (uint[] memory);
    function exitMarket(address mToken) virtual external returns (uint);

    /*** Policy Hooks ***/

    function mintAllowed(address mToken, address minter, uint mintAmount) virtual external returns (uint);

    function redeemAllowed(address mToken, address redeemer, uint redeemTokens) virtual external returns (uint);

    // Do not remove, still used by MToken
    function redeemVerify(address mToken, address redeemer, uint redeemAmount, uint redeemTokens) pure virtual external;

    function borrowAllowed(address mToken, address borrower, uint borrowAmount) virtual external returns (uint);

    function repayBorrowAllowed(
        address mToken,
        address payer,
        address borrower,
        uint repayAmount) virtual external returns (uint);

    function liquidateBorrowAllowed(
        address mTokenBorrowed,
        address mTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount) virtual external view returns (uint);

    function seizeAllowed(
        address mTokenCollateral,
        address mTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) virtual external returns (uint);

    function transferAllowed(address mToken, address src, address dst, uint transferTokens) virtual external returns (uint);

    /*** Liquidity/Liquidation Calculations ***/

    function liquidateCalculateSeizeTokens(
        address mTokenBorrowed,
        address mTokenCollateral,
        uint repayAmount) virtual external view returns (uint, uint);
}

// The hooks that were patched out of the comptroller to make room for the supply caps, if we need them
abstract contract ComptrollerInterfaceWithAllVerificationHooks is ComptrollerInterface {

    function mintVerify(address mToken, address minter, uint mintAmount, uint mintTokens) virtual external;

    // Included in ComptrollerInterface already
    // function redeemVerify(address mToken, address redeemer, uint redeemAmount, uint redeemTokens) virtual external;

    function borrowVerify(address mToken, address borrower, uint borrowAmount) virtual external;

    function repayBorrowVerify(
        address mToken,
        address payer,
        address borrower,
        uint repayAmount,
        uint borrowerIndex) virtual external;

    function liquidateBorrowVerify(
        address mTokenBorrowed,
        address mTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount,
        uint seizeTokens) virtual external;

    function seizeVerify(
        address mTokenCollateral,
        address mTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) virtual external;

    function transferVerify(address mToken, address src, address dst, uint transferTokens) virtual external;
}