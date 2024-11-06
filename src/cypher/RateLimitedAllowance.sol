// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin-contracts/contracts/security/Pausable.sol";

import {RateLimitedLibrary, RateLimit} from "@zelt/src/lib/RateLimitedLibrary.sol";
import {RateLimitCommonLibrary} from "@zelt/src/lib/RateLimitCommonLibrary.sol";

abstract contract RateLimitedAllowance is Pausable, Ownable {
    using RateLimitedLibrary for RateLimit;
    using RateLimitCommonLibrary for RateLimit;

    event Approved(
        address indexed token,
        address indexed spender,
        address indexed owner,
        uint128 rateLimitPerSecond,
        uint128 bufferCap
    );

    constructor(address owner) Ownable() {
        _transferOwnership(owner);
    }

    mapping(address owner => mapping(address token => mapping(address spender => RateLimit)))
        public limitedAllowance;

    function approve(
        address token,
        address spender,
        uint128 rateLimitPerSecond,
        uint128 bufferCap
    ) external {
        RateLimit storage limit = limitedAllowance[msg.sender][token][spender];

        uint256 lastBufferUsedTime = limit.lastBufferUsedTime;

        limit.setBufferCap(bufferCap);

        // manually set bufferCap this as first call to setBufferCap sets it to 0
        if (lastBufferUsedTime == 0) {
            limit.bufferStored = bufferCap;
        }

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
    ) external whenNotPaused {
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

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function _transfer(
        address from,
        address to,
        uint256 amount,
        address token
    ) internal virtual {}
}
