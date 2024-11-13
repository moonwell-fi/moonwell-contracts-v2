// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin-contracts/contracts/security/Pausable.sol";

import {RateLimitedLibrary, RateLimit} from "@zelt/src/lib/RateLimitedLibrary.sol";
import {RateLimitCommonLibrary} from "@zelt/src/lib/RateLimitCommonLibrary.sol";

/// @title Rate Limited Allowance Contract
/// @notice This contract implements a rate-limited allowance mechanism for token transfers
/// @dev Inherits from Pausable and Ownable
abstract contract RateLimitedAllowance is Pausable, Ownable {
    using RateLimitedLibrary for RateLimit;
    using RateLimitCommonLibrary for RateLimit;

    /// @notice Emitted when a new allowance is approved
    /// @param token The address of the token
    /// @param owner The address of the owner
    /// @param rateLimitPerSecond The rate limit per second
    /// @param bufferCap The buffer cap
    event Approved(
        address indexed token,
        address indexed owner,
        uint128 rateLimitPerSecond,
        uint128 bufferCap
    );

    /// @notice Emitted when the spender address is changed
    /// @param newSpender The address of the new spender
    event SpenderChanged(address newSpender);

    /// @notice The address of the authorized spender
    address public spender;

    /// @notice Mapping of owner to token to rate limit
    mapping(address owner => mapping(address token => RateLimit))
        public limitedAllowance;

    /// @notice Constructor to initialize the contract
    /// @param owner The address of the contract owner
    /// @param _spender The address of the authorized spender
    constructor(address owner, address _spender) Ownable() {
        spender = _spender;
        _transferOwnership(owner);
    }

    /// @notice Approves a rate-limited allowance for a token
    /// @param token The address of the token
    /// @param rateLimitPerSecond The rate limit per second
    /// @param bufferCap The buffer cap
    function approve(
        address token,
        uint128 rateLimitPerSecond,
        uint128 bufferCap
    ) external {
        RateLimit storage limit = limitedAllowance[msg.sender][token];

        limit.setBufferCap(bufferCap);
        limit.bufferStored = bufferCap;
        limit.setRateLimitPerSecond(rateLimitPerSecond);

        emit Approved(token, msg.sender, rateLimitPerSecond, bufferCap);
    }

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
    ) external whenNotPaused {
        require(msg.sender == spender, "Caller is not the authorized spender");
        RateLimit storage limit = limitedAllowance[from][token];

        limit.depleteBuffer(amount);

        _transfer(from, to, amount, token);
    }

    /// @notice Gets the rate-limited allowance for a token
    /// @param owner The address of the owner
    /// @param token The address of the token
    /// @return rateLimitPerSecond The rate limit per second
    /// @return bufferCap the bufferCap
    function getRateLimitedAllowance(
        address owner,
        address token
    )
        public
        view
        returns (
            uint128 rateLimitPerSecond,
            uint128 bufferCap,
            uint256 buffer,
            uint256 lastBufferUsedTime
        )
    {
        // has to be storage to call buffer()
        RateLimit storage limit = limitedAllowance[owner][token];

        rateLimitPerSecond = limit.rateLimitPerSecond;
        bufferCap = limit.bufferCap;
        buffer = limit.buffer();
        lastBufferUsedTime = limit.lastBufferUsedTime;
    }

    /// @notice Pauses the contract
    /// @dev Can only be called by the contract owner when the contract is not paused
    function pause() external whenNotPaused onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract
    /// @dev Can only be called by the contract owner when the contract is paused
    function unpause() external whenPaused onlyOwner {
        _unpause();
    }

    /// @notice Sets a new authorized spender address
    /// @dev Can only be called by the contract owner
    /// @param _spender The address of the new spender
    function setSpender(address _spender) external onlyOwner {
        spender = _spender;

        emit SpenderChanged(_spender);
    }

    /// @notice Internal function to transfer tokens
    /// @dev This function should be implemented by the inheriting contract
    /// @param from The address to transfer from
    /// @param to The address to transfer to
    /// @param amount The amount of tokens to transfer
    /// @param token The address of the token to transfer
    function _transfer(
        address from,
        address to,
        uint256 amount,
        address token
    ) internal virtual;
}
