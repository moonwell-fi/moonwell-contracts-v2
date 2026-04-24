// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

/// @notice Mock that pretends to be an OEV wrapper: exposes `priceFeed()`
///         returning a configurable inner aggregator, and proxies the rest
///         of AggregatorV3Interface to its own stored values.
contract MockOEVWrapperFeed is AggregatorV3Interface {
    AggregatorV3Interface public priceFeed;

    uint8 private _decimals;
    string private _description;
    uint256 private _version;

    uint80 public r_roundId;
    int256 public r_answer;
    uint256 public r_startedAt;
    uint256 public r_updatedAt;
    uint80 public r_answeredInRound;

    constructor(address inner, uint8 dec, string memory desc, uint256 ver) {
        priceFeed = AggregatorV3Interface(inner);
        _decimals = dec;
        _description = desc;
        _version = ver;
    }

    function setPriceFeed(address inner) external {
        priceFeed = AggregatorV3Interface(inner);
    }

    function setLatestRound(
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) external {
        r_roundId = roundId;
        r_answer = answer;
        r_startedAt = startedAt;
        r_updatedAt = updatedAt;
        r_answeredInRound = answeredInRound;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external view override returns (string memory) {
        return _description;
    }

    function version() external view override returns (uint256) {
        return _version;
    }

    function latestRound() external view override returns (uint256) {
        return uint256(r_roundId);
    }

    function getRoundData(
        uint80
    )
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (
            r_roundId,
            r_answer,
            r_startedAt,
            r_updatedAt,
            r_answeredInRound
        );
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (
            r_roundId,
            r_answer,
            r_startedAt,
            r_updatedAt,
            r_answeredInRound
        );
    }
}
