// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {WETH9} from "@protocol/router/IWETH.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

/// @title ChainlinkBoundedCompositeOracle
/// @notice Oracle that checks if a primary price feed is within bounds, then either:
/// - If within bounds: Combines it with a second price feed
/// - If out of bounds: Falls back to a backup price feed
/// @dev Includes OEV (Oracle Extractable Value) functionality for early updates
contract ChainlinkBoundedCompositeOracle is AggregatorV3Interface, Ownable {
    using SafeCast for *;

    /// @notice Emitted when oracle addresses are updated
    event OracleAddressesUpdated(
        address primaryOracle,
        address secondaryOracle,
        address fallbackOracle
    );

    /// @notice Emitted when bounds are updated
    event BoundsUpdated(int256 lowerBound, int256 upperBound);

    /// @notice Emitted when the fee multiplier is changed
    event FeeMultiplierChanged(uint16 newFee);

    /// @notice Emitted when the early update window is changed
    event EarlyUpdateWindowChanged(uint256 newWindow);

    /// @notice Emitted when protocol receives OEV revenue
    event ProtocolOEVRevenueUpdated(
        address indexed receiver,
        uint256 revenueAdded
    );

    /// @notice Primary oracle to check bounds against
    AggregatorV3Interface public primaryOracle;

    /// @notice Secondary oracle to multiply with primary if within bounds
    AggregatorV3Interface public secondaryOracle;

    /// @notice Fallback oracle to use if primary is out of bounds
    AggregatorV3Interface public fallbackOracle;

    /// @notice Lower bound for primary oracle price
    int256 public lowerBound;

    /// @notice Upper bound for primary oracle price
    int256 public upperBound;

    /// @notice The WETH contract
    WETH9 public immutable WETH;

    /// @notice The ETH market
    MErc20 public immutable WETHMarket;

    /// @notice Fee multiplier for early updates
    uint16 public feeMultiplier;

    /// @notice Window before next update where early updates are allowed
    uint256 public earlyUpdateWindow;

    /// @notice Last cached timestamp
    uint256 public cachedTimestamp;

    /// @notice Last cached price
    int256 public cachedPrice;

    /// @notice Scaling factor for price calculations
    uint8 public constant decimals = 18;

    /// @notice constructor to initialize the oracle with price feeds and configuration
    /// @param _primaryOracle The address of the primary oracle to check bounds against
    /// @param _secondaryOracle The address of the secondary oracle to multiply with primary if within bounds
    /// @param _fallbackOracle The address of the fallback oracle to use if primary is out of bounds
    /// @param _lowerBound The lower bound for the primary oracle price
    /// @param _upperBound The upper bound for the primary oracle price
    /// @param _earlyUpdateWindow The time window before next update where early updates are allowed
    /// @param _feeMultiplier The multiplier for early update fees
    /// @param _ethMarket The address of the ETH market for OEV revenue
    /// @param _weth The address of the WETH contract
    constructor(
        address _primaryOracle,
        address _secondaryOracle,
        address _fallbackOracle,
        int256 _lowerBound,
        int256 _upperBound,
        uint256 _earlyUpdateWindow,
        uint16 _feeMultiplier,
        address _ethMarket,
        address _weth
    ) {
        primaryOracle = AggregatorV3Interface(_primaryOracle);
        secondaryOracle = AggregatorV3Interface(_secondaryOracle);
        fallbackOracle = AggregatorV3Interface(_fallbackOracle);

        lowerBound = _lowerBound;
        upperBound = _upperBound;

        WETHMarket = MErc20(_ethMarket);
        WETH = WETH9(_weth);

        earlyUpdateWindow = _earlyUpdateWindow;
        feeMultiplier = _feeMultiplier;

        // Initialize cache
        (, int256 price, , uint256 timestamp, ) = _getCompositePrice();
        cachedPrice = price;
        cachedTimestamp = timestamp;
    }

    /// @notice Get the latest round data from either cache or fresh composite price
    /// @return roundId The round ID (always 0)
    /// @return answer The composite price
    /// @return startedAt The timestamp when the round started (always 0)
    /// @return updatedAt The timestamp when the round was updated
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
        if (block.timestamp >= cachedTimestamp + earlyUpdateWindow) {
            (
                roundId,
                answer,
                startedAt,
                updatedAt,
                answeredInRound
            ) = _getCompositePrice();
        } else {
            return (0, cachedPrice, 0, cachedTimestamp, 0);
        }
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
        return fallbackOracle.getRoundData(_roundId);
    }

    /// @notice Update price earlier than the standard update interval by paying a fee
    /// @return The updated composite price
    function updatePriceEarly() external payable returns (int256) {
        require(
            msg.value >= (tx.gasprice - block.basefee) * uint256(feeMultiplier),
            "ChainlinkBoundedCompositeOracle: Insufficient fee"
        );
        require(
            block.timestamp > cachedTimestamp,
            "ChainlinkBoundedCompositeOracle: Too early"
        );

        (, int256 price, , , ) = _getCompositePrice();

        cachedPrice = price;
        cachedTimestamp = block.timestamp;

        // Add fee to ETH market reserves
        WETH.deposit{value: msg.value}();
        WETH.approve(address(WETHMarket), msg.value);
        uint256 success = WETHMarket._addReserves(msg.value);
        require(
            success == 0,
            "ChainlinkBoundedCompositeOracle: Failed to add reserves"
        );

        emit ProtocolOEVRevenueUpdated(address(WETHMarket), msg.value);

        return price;
    }

    /// @notice Set new oracle addresses
    /// @param _primaryOracle The address of the new primary oracle
    /// @param _secondaryOracle The address of the new secondary oracle
    /// @param _fallbackOracle The address of the new fallback oracle
    function setOracleAddresses(
        address _primaryOracle,
        address _secondaryOracle,
        address _fallbackOracle
    ) external onlyOwner {
        primaryOracle = AggregatorV3Interface(_primaryOracle);
        secondaryOracle = AggregatorV3Interface(_secondaryOracle);
        fallbackOracle = AggregatorV3Interface(_fallbackOracle);

        emit OracleAddressesUpdated(
            _primaryOracle,
            _secondaryOracle,
            _fallbackOracle
        );
    }

    /// @notice Set new price bounds for the primary oracle
    /// @param _lowerBound The new lower bound price
    /// @param _upperBound The new upper bound price
    function setPriceBounds(
        int256 _lowerBound,
        int256 _upperBound
    ) external onlyOwner {
        require(
            _lowerBound < _upperBound,
            "ChainlinkBoundedCompositeOracle: Invalid bounds"
        );
        lowerBound = _lowerBound;
        upperBound = _upperBound;

        emit BoundsUpdated(_lowerBound, _upperBound);
    }

    /// @notice Set new fee multiplier for early updates
    /// @param newMultiplier The new fee multiplier value
    function setFeeMultiplier(uint16 newMultiplier) external onlyOwner {
        feeMultiplier = newMultiplier;
        emit FeeMultiplierChanged(newMultiplier);
    }

    /// @notice Set new early update window
    /// @param newWindow The new early update window duration
    function setEarlyUpdateWindow(uint256 newWindow) external onlyOwner {
        earlyUpdateWindow = newWindow;
        emit EarlyUpdateWindowChanged(newWindow);
    }

    // Required interface methods
    function description() external pure override returns (string memory) {
        return "Moonwell Bounded Composite Oracle with OEV";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    /// @notice Helper function to get validated price data from a Chainlink oracle
    /// @param oracle The address of the Chainlink oracle to query
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

        require(price > 0, "Invalid price");
        require(timestamp != 0, "Round is in incomplete state");
        require(answeredInRound >= roundId, "Stale price");

        return (roundId, price, timestamp, answeredInRound);
    }

    /// @notice Internal function to get composite price and scale appropriately
    /// @return roundId The round ID (always 0)
    /// @return answer The composite price after scaling
    /// @return startedAt The timestamp when the round started (always 0)
    /// @return updatedAt The timestamp of the primary oracle update
    /// @return answeredInRound The round ID in which the answer was computed (always 0)
    function _getCompositePrice()
        internal
        view
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

        ) = _getValidatedOracleData(primaryOracle);

        uint8 primaryDecimals = primaryOracle.decimals();
        primaryPrice = scalePrice(primaryPrice, primaryDecimals, decimals);

        // Check bounds
        if (primaryPrice >= lowerBound && primaryPrice <= upperBound) {
            // Within bounds - combine with secondary
            (, int256 secondaryPrice, , ) = _getValidatedOracleData(
                secondaryOracle
            );

            // Scale secondary price
            uint8 secondaryDecimals = secondaryOracle.decimals();
            secondaryPrice = scalePrice(
                secondaryPrice,
                secondaryDecimals,
                decimals
            );

            // Calculate composite price
            // Both prices are now scaled to 18 decimals
            // Divide by 10^18 to get final price in 18 decimals
            answer = ((primaryPrice * secondaryPrice) /
                (10 ** decimals).toInt256());
        } else {
            // Out of bounds - use fallback
            (, answer, primaryTimestamp, ) = _getValidatedOracleData(
                fallbackOracle
            );

            // Scale fallback price to match expected decimals
            uint8 fallbackDecimals = fallbackOracle.decimals();
            answer = scalePrice(answer, fallbackDecimals, decimals);
        }

        return (0, answer, 0, primaryTimestamp, 0);
    }

    /// @notice scale price up or down to the desired amount of decimals
    /// @param price The price to scale
    /// @param priceDecimals The amount of decimals the price has
    /// @param expectedDecimals The amount of decimals the price should have
    /// @return the scaled price
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
