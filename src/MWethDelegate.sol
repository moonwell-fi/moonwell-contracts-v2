// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {WETH9} from "@protocol/router/IWETH.sol";
import {WethUnwrapper} from "@protocol/WethUnwrapper.sol";
import {MErc20Delegate} from "@protocol/MErc20Delegate.sol";

/**
 * @title Moonwell's MWethDelegate Contract
 * @notice MToken which wraps underlying ETH
 * @author Moonwell
 */
contract MWethDelegate is MErc20Delegate {
    using SafeERC20 for IERC20;

    /// @notice the WETH unwrapper address
    address constant public wethUnwrapper = 0x876fa6f4EB3Aad22f9893f82784095401499d6cA;

    /// @notice transfer ETH underlying to the recipient
    /// first unwrap the WETH into raw ETH, then transfer
    /// @param to the recipient address
    /// @param amount the amount of ETH to transfer
    function doTransferOut(
        address payable to,
        uint256 amount
    ) internal virtual override {
        IERC20 weth = IERC20(underlying);

        weth.safeTransfer(wethUnwrapper, amount);
        WethUnwrapper(payable(wethUnwrapper)).send(address(underlying), to, amount); /// send and destruct wrapper
    }
}
