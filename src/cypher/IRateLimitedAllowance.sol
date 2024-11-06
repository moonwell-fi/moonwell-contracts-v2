// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

interface IRateLimitedAllowance {
    function transferFrom(
        address from,
        address to,
        uint160 amount,
        address token
    ) external;

    function approve(
        address token,
        address spender,
        uint160 amount,
        uint48 rateLimitPerSecond,
        uint48 bufferCap
    ) external;
}
