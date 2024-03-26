// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import "./IEcosystemReserve.sol";
import "./IERC20.sol";
import {Ownable} from "./Ownable.sol";

/*
 * @title EcosystemReserveController
 * @dev Proxy smart contract to control the EcosystemReserve, in order for the governance to call its
 * user-face functions (as the governance is also the proxy admin of the EcosystemReserve)
 * @author Moonwell
 */
contract EcosystemReserveController is Ownable {
    IEcosystemReserve public ECOSYSTEM_RESERVE;
    bool public initialized;

    function setEcosystemReserve(address ecosystemReserve) external onlyOwner {
        require(!initialized, "ECOSYSTEM_RESERVE has been initialized");
        initialized = true;
        ECOSYSTEM_RESERVE = IEcosystemReserve(ecosystemReserve);
    }

    function approve(
        IERC20 token,
        address recipient,
        uint256 amount
    ) external onlyOwner {
        ECOSYSTEM_RESERVE.approve(token, recipient, amount);
    }

    function transfer(
        IERC20 token,
        address recipient,
        uint256 amount
    ) external onlyOwner {
        ECOSYSTEM_RESERVE.transfer(token, recipient, amount);
    }

    function setFundsAdmin(address admin) external onlyOwner {
        ECOSYSTEM_RESERVE.setFundsAdmin(admin);
    }
}
