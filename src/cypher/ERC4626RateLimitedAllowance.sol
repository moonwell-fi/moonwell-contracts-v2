// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {IERC4626} from "@forge-std/interfaces/IERC4626.sol";
import {RateLimitedAllowance} from "./RateLimitedAllowance.sol";

/// @title ERC4626RateLimitedAllowance
/// @notice A contract that implements rate-limited allowances for ERC4626 vaults
/// @dev Inherits from RateLimitedAllowance and provides specific implementation for ERC4626 vault transfers
contract ERC4626RateLimitedAllowance is RateLimitedAllowance {
    /// @notice Constructs a new ERC4626RateLimitedAllowance instance
    /// @param owner The address of the owner of the allowance
    /// @param spender The address of the spender of the allowance
    constructor(
        address owner,
        address spender
    ) RateLimitedAllowance(owner, spender) {}

    /// @notice Transfers tokens from an ERC4626 vault
    /// @dev Overrides the _transfer function in the parent contract
    /// @param from The address to transfer from
    /// @param to The address to transfer to
    /// @param amount The amount of tokens to transfer
    /// @param vault The address of the ERC4626 vault
    function _transfer(
        address from,
        address to,
        uint256 amount,
        address vault
    ) internal override {
        IERC4626(vault).withdraw(amount, to, from);
    }
}
