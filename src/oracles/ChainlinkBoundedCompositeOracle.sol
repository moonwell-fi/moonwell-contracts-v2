// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin-contracts/contracts/utils/Address.sol";

import {WETH9} from "@protocol/router/IWETH.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

/// @title ChainlinkBoundedCompositeOracle
/// @notice Oracle that checks if a primary price feed is within bounds, then either:
/// - If within bounds: Combines it with a second price feed
/// - If out of bounds: Falls back to a backup price feed
/// @dev Includes OEV (Oracle Extractable Value) functionality for early updates
contract ChainlinkBoundedCompositeOracle is AggregatorV3Interface, Ownable {
    using Address for address;
    using SafeCast for *;

    /// @notice Emitted when bounds are updated
    event BoundsUpdated(
        int256 oldLower,
        int256 newLower,
        int256 oldUpper,
        int256 newUpper
    );

    /// @notice Emitted when the fee multiplier is updated
    event FeeMultiplierUpdated(
        uint16 oldFeeMultiplier,
        uint16 newFeeMultiplier
    );

    /// @notice Emitted when the early update window is updated
    event EarlyUpdateWindowUpdated(uint256 oldWindow, uint256 newWindow);

    /// @notice Emitted when primary oracle address is updated
    event PrimaryOracleUpdated(
        address oldPrimaryOracle,
        address newPrimaryOracle
    );

    /// @notice Emitted when BTC oracle address is updated
    event BTCOracleUpdated(address oldBTCOracle, address newBTCOracle);

    /// @notice Emitted when fallback oracle address is updated
    event FallbackOracleUpdated(
        address oldFallbackOracle,
        address newFallbackOracle
    );

    /// @notice Primary oracle to check bounds against
    AggregatorV3Interface public primaryLBTCOracle;

    /// @notice Fallback market rate oracle to use if primary is out of bounds
    AggregatorV3Interface public fallbackLBTCOracle;

    /// @notice Lower bound for primary oracle price
    int256 public lowerBound;

    /// @notice Upper bound for primary oracle price
    int256 public upperBound;

    /// @notice Scaling factor for price calculations
    uint8 public constant decimals = 18;

    /// @notice constructor to initialize the oracle with price feeds and configuration
    /// @param _primaryOracle The address of the primary oracle to check bounds against
    /// @param _fallbackOracle The address of the fallback oracle to use if primary is out of bounds
    /// @param _lowerBound The lower bound for the primary oracle price
    /// @param _upperBound The upper bound for the primary oracle price
    /// @param _earlyUpdateWindow The time window before next update where early updates are allowed
    /// @param _feeMultiplier The multiplier for early update fees
    /// @param _governor The address of the governor to own the oracle
    constructor(
        address _primaryOracle,
        address _fallbackOracle,
        int256 _lowerBound,
        int256 _upperBound,
        uint256 _earlyUpdateWindow,
        uint16 _feeMultiplier,
        address _governor
    ) {
        primaryLBTCOracle = AggregatorV3Interface(_primaryOracle);
        fallbackLBTCOracle = AggregatorV3Interface(_fallbackOracle);

        require(
            _lowerBound < _upperBound,
            "ChainlinkBoundedCompositeOracle: Invalid bounds"
        );

        lowerBound = _lowerBound;
        upperBound = _upperBound;

        _transferOwnership(_governor);
    }

    /// @notice Get the latest price data from the oracle
    /// @dev Checks primary oracle first, if within bounds combines with BTC price, otherwise uses fallback
    /// @return roundId The round ID (always 0)
    /// @return answer The price in USD with 18 decimals
    /// @return startedAt The timestamp when the round started (always 0)
    /// @return updatedAt The timestamp of the price update
    /// @return answeredInRound The round ID in which the answer was computed (always 0)
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
        // Get primary price and scale it
        (
            ,
            int256 primaryPrice,
            uint256 primaryTimestamp,

        ) = _getValidatedOracleData(primaryLBTCOracle);

        uint8 primaryDecimals = primaryLBTCOracle.decimals();
        primaryPrice = scalePrice(primaryPrice, primaryDecimals, decimals);

        // Check primary lbtc/btc PoR exchange rate,
        // if out of bounds, fall back to market rate oracle
        if (primaryPrice < lowerBound || primaryPrice > upperBound) {
            // fall back to market rate oracle if primary is out of bounds
            (, primaryPrice, primaryTimestamp, ) = _getValidatedOracleData(
                fallbackLBTCOracle
            );
            uint8 fallbackDecimals = fallbackLBTCOracle.decimals();
            primaryPrice = scalePrice(primaryPrice, fallbackDecimals, decimals);
        }

        return (0, primaryPrice, 0, primaryTimestamp, 0);
    }

    /// @notice Get data about a specific round from the fallback oracle
    /// @param _roundId The round ID to retrieve data for
    /// @return roundId The round ID
    /// @return answer The price
    /// @return startedAt The timestamp when the round started
    /// @return updatedAt The timestamp when the round was updated
    /// @return answeredInRound The round ID in which the answer was computed
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
        return fallbackLBTCOracle.getRoundData(_roundId);
    }

    /// @notice Set new primary LBTC/BTC oracle address
    /// @param _primaryOracle The address of the new primary oracle
    function setPrimaryOracle(address _primaryOracle) external onlyOwner {
        require(
            _primaryOracle.isContract(),
            "ChainlinkBoundedCompositeOracle: Primary oracle must be a contract"
        );
        address oldOracle = address(primaryLBTCOracle);
        primaryLBTCOracle = AggregatorV3Interface(_primaryOracle);
        emit PrimaryOracleUpdated(oldOracle, _primaryOracle);
    }

    /// @notice Set new fallback LBTC/BTC oracle address
    /// @param _fallbackOracle The address of the new fallback oracle
    function setFallbackOracle(address _fallbackOracle) external onlyOwner {
        require(
            _fallbackOracle.isContract(),
            "ChainlinkBoundedCompositeOracle: Fallback oracle must be a contract"
        );
        address oldOracle = address(fallbackLBTCOracle);
        fallbackLBTCOracle = AggregatorV3Interface(_fallbackOracle);
        emit FallbackOracleUpdated(oldOracle, _fallbackOracle);
    }

    /// @notice Set new bounds for the primary oracle price
    /// @param _lowerBound The new lower bound (scaled to 1e18)
    /// @param _upperBound The new upper bound (scaled to 1e18)
    function setBounds(
        int256 _lowerBound,
        int256 _upperBound
    ) external onlyOwner {
        require(
            _lowerBound < _upperBound,
            "ChainlinkBoundedCompositeOracle: Invalid bounds"
        );

        int256 oldLower = lowerBound;
        int256 oldUpper = upperBound;
        lowerBound = _lowerBound;
        upperBound = _upperBound;

        emit BoundsUpdated(oldLower, _lowerBound, oldUpper, _upperBound);
    }

    /// @notice Get the description of this oracle
    /// @return A string describing this oracle
    function description() external pure override returns (string memory) {
        return "Moonwell Bounded Composite Oracle";
    }

    /// @notice Get the version number of this oracle
    /// @return The version number
    function version() external pure override returns (uint256) {
        return 1;
    }

    /// @notice Internal function to validate oracle data
    /// @param oracle The oracle to validate data from
    /// @return roundId The round ID from the oracle
    /// @return price The validated price from the oracle
    /// @return timestamp The timestamp of the price update
    /// @return answeredInRound The round in which the answer was computed
    function _getValidatedOracleData(
        AggregatorV3Interface oracle
    )
        internal
        view
        returns (
            uint80 roundId,
            int256 price,
            uint256 timestamp,
            uint80 answeredInRound
        )
    {
        (roundId, price, , timestamp, answeredInRound) = oracle
            .latestRoundData();

        require(price > 0, "ChainlinkBoundedCompositeOracle: Invalid price");
        require(
            timestamp != 0,
            "ChainlinkBoundedCompositeOracle: Round is in incomplete state"
        );
        require(
            answeredInRound >= roundId,
            "ChainlinkBoundedCompositeOracle: Stale price"
        );

        return (roundId, price, timestamp, answeredInRound);
    }

    /// @notice Scale price to desired decimal places
    /// @param price The price to scale
    /// @param priceDecimals The current decimal places of the price
    /// @param expectedDecimals The desired decimal places
    /// @return The scaled price
    function scalePrice(
        int256 price,
        uint8 priceDecimals,
        uint8 expectedDecimals
    ) public pure returns (int256) {
        if (priceDecimals < expectedDecimals) {
            return
                price *
                (10 ** uint256(expectedDecimals - priceDecimals)).toInt256();
        } else if (priceDecimals > expectedDecimals) {
            return
                price /
                (10 ** uint256(priceDecimals - expectedDecimals)).toInt256();
        }

        /// if priceDecimals == expectedDecimals, return price without any changes

        return price;
    }
}
