// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

interface ITokenSaleDistributorProxy {
    function setPendingImplementation(address newImplementation) external;

    function admin() external view returns (address);

    function pendingAdmin() external view returns (address);
}
