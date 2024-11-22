// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./AggregatorV3Interface.sol";

contract ChainlinkFeedOEVWrapper is AggregatorV3Interface {
    AggregatorV3Interface public immutable originalFeed;

    uint16 public feeMultiplier = 99;
    uint256 public earlyUpdateWindow = 30 seconds;
    uint256 private cachedTimestamp;
    int256 private cachedPrice;

    constructor(
        address _originalFeed,
        uint256 earlyUpdateWindow,
        uint16 feeMultiplier
    ) {
        originalFeed = AggregatorV3Interface(_originalFeed);

        // Initialize cache with current data
        (, int256 price, , uint256 timestamp, ) = originalFeed
            .latestRoundData();

        cachedPrice = price;
        cachedTimestamp = timestamp;
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        if (block.timestamp >= cachedTimestamp + earlyUpdateWindow) {
            return originalFeed.latestRoundData();
        } else {
            return (0, cachedPrice, 0, cachedTimestamp, 0);
        }
    }

    function updatePriceEarly(int256 price) external payable {
        require(msg.value >= _currentPriorityFeePerGas() * feeMultiplier);
        require(
            block.timestamp > cachedTimestamp,
            "New timestamp must be greather than current"
        );

        cachedPrice = price;
        cachedTimestamp = block.timestamp;
    }

    function decimals() external view override returns (uint8) {
        return originalFeed.decimals();
    }

    function description() external view override returns (string memory) {
        return originalFeed.description();
    }

    function version() external view override returns (uint256) {
        return originalFeed.version();
    }

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return originalFeed.getRoundData(_roundId);
    }

    /// @notice Returns the current priority fee per gas.
    /// @return Priority fee per gas.
    function _currentPriorityFeePerGas() internal view returns (uint256) {
        return tx.gasprice - block.basefee;
    }
}
