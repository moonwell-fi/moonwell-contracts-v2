// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

interface ITimelock {
    function delay() external view returns (uint256);

    function pendingAdmin() external view returns (address);

    function admin() external view returns (address);

    function acceptAdmin() external;
}
