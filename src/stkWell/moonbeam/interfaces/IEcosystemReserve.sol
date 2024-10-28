// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import "../interfaces/IERC20.sol";

interface IEcosystemReserve {
    function approve(IERC20 token, address recipient, uint256 amount) external;

    function transfer(IERC20 token, address recipient, uint256 amount) external;

    function setFundsAdmin(address admin) external;
}
