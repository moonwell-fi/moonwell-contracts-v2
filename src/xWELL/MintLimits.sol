pragma solidity 0.8.19;

import {RateLimitedMidpointLibrary} from "@zelt/src/lib/RateLimitedMidpointLibrary.sol";
import {RateLimitMidPoint, RateLimitMidpointCommonLibrary} from "@zelt/src/lib/RateLimitMidpointCommonLibrary.sol";

contract MintLimits {
    using RateLimitMidpointCommonLibrary for RateLimitMidPoint;
    using RateLimitedMidpointLibrary for RateLimitMidPoint;

    /// @notice maximum rate limit per second governance can set for this contract
    uint256 public constant MAX_RATE_LIMIT_PER_SECOND = 10_000_000 * 1e18;

    /// @notice rate limit for each bridge contract
    mapping(address => RateLimitMidPoint) public rateLimits;

    struct RateLimitMidPoint {
        uint112 bufferCap;
        uint128 rateLimitPerSecond;
        address rateLimited;
    }

    /// @notice RateLimitedV2 constructor
    /// @param _maxRateLimitPerSecond maximum rate limit per second that governance can set
    /// @param _rateLimitPerSecond starting rate limit per second
    /// @param _bufferCap cap on buffer size for this rate limited instance
    constructor(
        RateLimitMidPoint[] memory _rateLimits
    ) {
        for (uint256 i = 0; i < _rateLimits.length; i++) {
            RateLimitMidPoint memory rateLimit = _rateLimits[i];
            require(
                rateLimit.rateLimitPerSecond <= MAX_RATE_LIMIT_PER_SECOND
                "MintLimits: rateLimitPerSecond too high"
            );
            rateLimits[rateLimit.rateLimited].bufferCap = rateLimit.bufferCap;
            rateLimits[rateLimit.rateLimited].lastBufferUsedTime = uint32(block.timestamp);
            rateLimits[rateLimit.rateLimited].bufferStored = uint112(_bufferCap / 2); /// manually set this as first call to setBufferCap sets it to 0
            rateLimits[rateLimit.rateLimited].midPoint = uint112(_bufferCap / 2);
    
            require(
                _rateLimitPerSecond <= MAX_RATE_LIMIT_PER_SECOND
                "MintLimits: rateLimitPerSecond too high"
            );
            rateLimits[from].setRateLimitPerSecond(_rateLimitPerSecond);
        }

        MAX_RATE_LIMIT_PER_SECOND = _maxRateLimitPerSecond;
    }

    /// @notice the amount of action used before hitting limit
    /// @dev replenishes at rateLimitPerSecond per second up to bufferCap
    function buffer(address from) public view returns (uint256) {
        return rateLimits[from].buffer();
    }

    /// @notice the amount of action used before hitting limit
    /// @dev replenishes at rateLimitPerSecond per second up to bufferCap
    function bufferCap(address from) public view returns (uint256) {
        return rateLimits[from].bufferCap;
    }

    /// @notice the method that enforces the rate limit.
    /// Decreases buffer by "amount".
    /// If buffer is <= amount, revert
    /// @param amount to decrease buffer by
    function _depleteBuffer(address from, uint256 amount) internal {
        rateLimits[from].depleteBuffer(amount);
    }

    /// @notice function to replenish buffer
    /// @param amount to increase buffer by if under buffer cap
    function _replenishBuffer(address from, uint256 amount) internal {
        rateLimits[from].replenishBuffer(amount);
    }

    /// @notice function to set rate limit per second
    /// @dev updates the current buffer and last buffer used time first,
    /// then sets the new rate limit per second
    /// @param newRateLimitPerSecond new rate limit per second
    function _setRateLimitPerSecond(
        address from,
        uint128 newRateLimitPerSecond
    ) internal {
        require(
            newRateLimitPerSecond <= MAX_RATE_LIMIT_PER_SECOND,
            "MintLimits: rateLimitPerSecond too high"
        );
        rateLimits[from].setRateLimitPerSecond(newRateLimitPerSecond);
    }

    /// @notice function to set buffer cap
    /// @dev updates the current buffer and last buffer used time first,
    /// then sets the new buffer cap
    /// @param newBufferCap new buffer cap
    function _setBufferCap(address from, uint112 newBufferCap) internal {
        rateLimits[from].setBufferCap(newBufferCap);
    }
}
