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
        address indexed owner,
        uint128 rateLimitPerSecond,
        uint128 bufferCap
    );

    event SpenderChanged(address newSpender);

    address public spender;

    mapping(address owner => mapping(address token => RateLimit))
        public limitedAllowance;

    constructor(address owner, address _spender) Ownable() {
        spender = _spender;
        _transferOwnership(owner);
    }

    function approve(
        address token,
        uint128 rateLimitPerSecond,
        uint128 bufferCap
    ) external {
        RateLimit storage limit = limitedAllowance[msg.sender][token];

        uint256 lastBufferUsedTime = limit.lastBufferUsedTime;

        limit.setBufferCap(bufferCap);

        if (lastBufferUsedTime == 0) {
            // manually set bufferCap as first call to setBufferCap sets it to 0
            limit.bufferStored = bufferCap;
        }

        limit.setRateLimitPerSecond(rateLimitPerSecond);

        emit Approved(token, msg.sender, rateLimitPerSecond, bufferCap);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount,
        address token
    ) external whenNotPaused {
        require(msg.sender == spender, "Caller is not the authorized spender");
        RateLimit storage limit = limitedAllowance[from][token];

        limit.depleteBuffer(amount);

        _transfer(from, to, amount, token);
    }

    function getRateLimitedAllowance(
        address owner,
        address token
    ) public view returns (uint128 rateLimitPerSecond, uint128 bufferCap) {
        RateLimit memory limit = limitedAllowance[owner][token];

        rateLimitPerSecond = limit.rateLimitPerSecond;
        bufferCap = limit.bufferCap;
    }

    function pause() external whenNotPaused onlyOwner {
        _pause();
    }

    function unpause() external whenPaused onlyOwner {
        _unpause();
    }

    function setSpender(address _spender) external onlyOwner {
        spender = _spender;
        emit SpenderChanged(_spender);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount,
        address token
    ) internal virtual;
}
