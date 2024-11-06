// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {RateLimitedLibrary, RateLimit} from "@zelt/src/lib/RateLimitedLibrary.sol";
import {RateLimitCommonLibrary} from "@zelt/src/lib/RateLimitCommonLibrary.sol";

abstract contract RateLimitedAllowance {
    using RateLimitedLibrary for RateLimit;
    using RateLimitCommonLibrary for RateLimit;

    event Approved(
        address indexed token,
        address indexed spender,
        address indexed owner,
        uint128 rateLimitPerSecond,
        uint128 bufferCap
    );

    mapping(address owner => mapping(address token => mapping(address spender => RateLimit)))
        public limitedAllowance;

    function approve(
        address token,
        address spender,
        uint128 rateLimitPerSecond,
        uint128 bufferCap
    ) external {
        RateLimit storage limit = limitedAllowance[msg.sender][token][spender];

        limit.lastBufferUsedTime = uint32(block.timestamp);
        limit.setBufferCap(bufferCap);
        limit.bufferStored = bufferCap;

        limit.setRateLimitPerSecond(rateLimitPerSecond);

        emit Approved(
            token,
            spender,
            msg.sender,
            rateLimitPerSecond,
            bufferCap
        );
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount,
        address token
    ) external {
        RateLimit storage limit = limitedAllowance[from][token][msg.sender];

        limit.depleteBuffer(amount);

        _transfer(from, to, amount, token);
    }

    function getRateLimitedAllowance(
        address owner,
        address token,
        address spender
    ) public view returns (uint128 rateLimitPerSecond, uint128 bufferCap) {
        RateLimit memory limit = limitedAllowance[owner][token][spender];

        rateLimitPerSecond = limit.rateLimitPerSecond;
        bufferCap = limit.bufferCap;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount,
        address token
    ) internal virtual {}
}
