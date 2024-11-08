// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

/// @title IRateLimitedAllowance
/// @notice Interface for rate-limited token allowances
interface IRateLimitedAllowance {
    /// @notice Approves a rate-limited allowance for a token
    /// @param token The address of the token to approve
    /// @param rateLimitPerSecond The maximum amount that can be spent per second
    /// @param bufferCap The maximum amount that can be accumulated in the buffer
    function approve(
        address token,
        uint128 rateLimitPerSecond,
        uint128 bufferCap
    ) external;

    /// @notice Transfers tokens from one address to another, respecting the rate limit
    /// @param from The address to transfer from
    /// @param to The address to transfer to
    /// @param amount The amount of tokens to transfer
    /// @param token The address of the token to transfer
    function transferFrom(
        address from,
        address to,
        uint256 amount,
        address token
    ) external;
}
