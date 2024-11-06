// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {RateLimitedLibrary, RateLimit} from "@zelt/src/lib/RateLimitedLibrary.sol";
import {RateLimitCommonLibrary} from "@zelt/src/lib/RateLimitCommonLibrary.sol";

abstract contract RateLimitedAllowance {
    using RateLimitedLibrary for RateLimit;
    using RateLimitCommonLibrary for RateLimit;

    mapping(address owner => mapping(address token => mapping(address spender => RateLimit)))
        public limitedAllowance;

    function approve(
        address token,
        address spender,
        uint160 amount,
        uint48 rateLimitPerSecond,
        uint48 bufferCap
    ) external {
        RateLimit storage limit = limitedAllowance[msg.sender][token][spender];

        rateLimit.lastBufferUsedTime = uint32(block.timestamp);
        rateLimit.setBufferCap(_bufferCap);
        rateLimit.bufferStored = _bufferCap;

        rateLimit.setRateLimitPerSecond(_rateLimitPerSecond);
    }

    function transferFrom(
        address from,
        address to,
        uint160 amount,
        address token
    ) external {
        RateLimit storage limit = limitedAllowance[from][token][msg.sender];

        limit.depleteBuffer(amount);

        _transfer(from, to, amount, token);
    }

    function _transfer(
        address from,
        address to,
        uint160 amount,
        address token
    ) internal virtual {}
}
