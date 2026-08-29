// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {WethUnwrapper} from "@protocol/WethUnwrapper.sol";
import {MErc20Delegate} from "@protocol/MErc20Delegate.sol";

/**
 * @title Moonwell's MWethDelegate Contract
 * @notice MToken which wraps underlying ETH
 * @author Moonwell
 */
contract MWethDelegate is MErc20Delegate {
    /// @notice the WETH unwrapper address
    address public immutable wethUnwrapper;

    /// @notice construct a new MWethDelegate
    /// @param _wethUnwrapper the WETH Unwrapper address
    constructor(address _wethUnwrapper) {
        wethUnwrapper = _wethUnwrapper;
    }

    /// @notice transfer ETH underlying to the recipient
    /// first unwrap the WETH into raw ETH, then transfer
    /// @param to the recipient address
    /// @param amount the amount of ETH to transfer
    function doTransferOut(
        address payable to,
        uint256 amount
    ) internal virtual override {
        /// hand the WETH to the unwrapper through the base implementation so that
        /// `internalCash` is debited in exactly one place
        super.doTransferOut(payable(wethUnwrapper), amount);

        WethUnwrapper(payable(wethUnwrapper)).send(to, amount); /// send to user through wethUnwrapper
    }
}
