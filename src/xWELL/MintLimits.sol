pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {RateLimitedMidpointLibrary} from "@zelt/src/lib/RateLimitedMidpointLibrary.sol";
import {RateLimitMidPoint, RateLimitMidpointCommonLibrary} from "@zelt/src/lib/RateLimitMidpointCommonLibrary.sol";

/// @notice struct for initializing rate limit
struct RateLimitMidPointInfo {
    uint112 bufferCap;
    uint128 rateLimitPerSecond;
    address rateLimited;
}

contract MintLimits is Initializable {
    using RateLimitMidpointCommonLibrary for RateLimitMidPoint;
    using RateLimitedMidpointLibrary for RateLimitMidPoint;

    /// @notice maximum rate limit per second governance can set for this contract
    uint256 public constant MAX_RATE_LIMIT_PER_SECOND = 10_000_000 * 1e18;

    /// @notice rate limit for each bridge contract
    mapping(address => RateLimitMidPoint) public rateLimits;

    /// @notice Mint Limits initializer function, conform to OZ initializer naming convention
    /// @param _rateLimits cap on buffer size for this rate limited instance
    function __Mint_Limits(
        RateLimitMidPointInfo[] memory _rateLimits
    ) internal onlyInitializing {
        for (uint256 i = 0; i < _rateLimits.length; i++) {
            RateLimitMidPointInfo memory rateLimit = _rateLimits[i];
            require(
                rateLimit.rateLimitPerSecond <= MAX_RATE_LIMIT_PER_SECOND,
                "MintLimits: rateLimitPerSecond too high"
            );

            rateLimits[rateLimit.rateLimited] = RateLimitMidPoint({
                bufferCap: rateLimit.bufferCap,
                lastBufferUsedTime: uint32(block.timestamp),
                bufferStored: uint112(rateLimit.bufferCap / 2),
                midPoint: uint112(rateLimit.bufferCap / 2),
                rateLimitPerSecond: rateLimit.rateLimitPerSecond
            });
        }
    }

    /// @notice the amount of action used before hitting limit
    /// @dev replenishes at rateLimitPerSecond per second up to bufferCap
    function buffer(address from) public view returns (uint256) {
        return rateLimits[from].buffer();
    }

    /// @notice the cap of the buffer for this address
    function bufferCap(address from) public view returns (uint256) {
        return rateLimits[from].bufferCap;
    }

    /// @notice the amount the buffer replenishes towards the midpoint per second
    function rateLimitPerSecond(address from) public view returns (uint256) {
        return rateLimits[from].rateLimitPerSecond;
    }

    /// @notice the method that enforces the rate limit.
    /// Decreases buffer by "amount".
    /// If buffer is <= amount, revert
    /// @param amount to decrease buffer by
    function _depleteBuffer(address from, uint256 amount) internal {
        require(amount != 0, "MintLimits: deplete amount cannot be 0");
        rateLimits[from].depleteBuffer(amount);
    }

    /// @notice function to replenish buffer
    /// @param amount to increase buffer by if under buffer cap
    function _replenishBuffer(address from, uint256 amount) internal {
        require(amount != 0, "MintLimits: replenish amount cannot be 0");
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
