// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "./AggregatorV3Interface.sol";

/// @title StaticPriceFeed
/// @notice A minimal AggregatorV3Interface implementation that returns a fixed
///         price set at construction time. Used as a replacement for deprecated
///         Chainlink feeds on Moonriver.
///
/// @dev This feed is only intended for Moonriver wind-down mode where all
///      collateral factors are 0 and borrowing is paused. The price just
///      needs to be non-zero so getUnderlyingPrice() doesn't revert.
contract StaticPriceFeed is AggregatorV3Interface {
    /// @notice The fixed price answer (in 8-decimal Chainlink format)
    int256 public immutable staticAnswer;

    /// @notice Feed description
    string public feedDescription;

    /// @param _answer The fixed price in 8-decimal format (e.g. 1000000000 = $10)
    /// @param _description Human-readable description (e.g. "MOVR / USD")
    constructor(int256 _answer, string memory _description) {
        require(_answer > 0, "answer must be positive");
        staticAnswer = _answer;
        feedDescription = _description;
    }

    function decimals() external pure override returns (uint8) {
        return 8;
    }

    function description() external view override returns (string memory) {
        return feedDescription;
    }

    function version() external pure override returns (uint256) {
        return 1;
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
        return (1, staticAnswer, block.timestamp, block.timestamp, 1);
    }

    function getRoundData(
        uint80
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
        return (1, staticAnswer, block.timestamp, block.timestamp, 1);
    }

    function latestRound() external pure override returns (uint256) {
        return 1;
    }
}
