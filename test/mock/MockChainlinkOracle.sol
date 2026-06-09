// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

contract MockChainlinkOracle is AggregatorV3Interface {
    // fixed value
    int256 public _value;
    uint8 public _decimals;

    // mocked data
    uint80 _roundId;
    uint256 _startedAt;
    uint256 _updatedAt;
    uint80 _answeredInRound;

    // circuit breaker bounds
    int256 public _minAnswer;
    int256 public _maxAnswer;

    constructor(int256 value, uint8 oracleDecimals) {
        _value = value;
        _decimals = oracleDecimals;
        _roundId = 42;
        _startedAt = 1620651856;
        _updatedAt = 1620651856;
        _answeredInRound = 42;
        _minAnswer = type(int256).min;
        _maxAnswer = type(int256).max;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external pure override returns (string memory) {
        return "Mock Oracle";
    }

    function getRoundData(
        uint80 _getRoundId
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
        return (_getRoundId, _value, _startedAt, _updatedAt, _answeredInRound);
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
        return (_roundId, _value, _startedAt, _updatedAt, _answeredInRound);
    }

    function set(
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) external {
        _roundId = roundId;
        _value = answer;
        _startedAt = startedAt;
        _updatedAt = updatedAt;
        _answeredInRound = answeredInRound;
    }

    function setMinMax(int256 minAnswer, int256 maxAnswer) external {
        _minAnswer = minAnswer;
        _maxAnswer = maxAnswer;
    }

    function minAnswer() external view override returns (int256) {
        return _minAnswer;
    }

    function maxAnswer() external view override returns (int256) {
        return _maxAnswer;
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function latestRound() external view override returns (uint256) {
        return _roundId;
    }
}
