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

    /// @notice Emitted when protocol receives OEV revenue
    event ProtocolOEVRevenueUpdated(
        address indexed receiver,
        uint256 revenueAdded
    );

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

    /// @notice BTC oracle to multiply LBTC with primary if within bounds
    AggregatorV3Interface public btcChainlinkOracle;

    /// @notice Fallback market rate oracle to use if primary is out of bounds
    AggregatorV3Interface public fallbackLBTCOracle;

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
    /// @param _governor The address of the governor to own the oracle
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
        address _governor,
        address _ethMarket,
        address _weth
    ) {
        primaryLBTCOracle = AggregatorV3Interface(_primaryOracle);
        btcChainlinkOracle = AggregatorV3Interface(_secondaryOracle);
        fallbackLBTCOracle = AggregatorV3Interface(_fallbackOracle);

        require(
            _lowerBound < _upperBound,
            "ChainlinkBoundedCompositeOracle: Invalid bounds"
        );

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
        return fallbackLBTCOracle.getRoundData(_roundId);
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

    /// @notice Set new BTC/USD oracle address
    /// @param _btcOracle The address of the new BTC oracle
    function setBTCOracle(address _btcOracle) external onlyOwner {
        require(
            _btcOracle.isContract(),
            "ChainlinkBoundedCompositeOracle: BTC oracle must be a contract"
        );
        address oldOracle = address(btcChainlinkOracle);
        btcChainlinkOracle = AggregatorV3Interface(_btcOracle);
        emit BTCOracleUpdated(oldOracle, _btcOracle);
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

    /// @notice Set new fee multiplier for early updates
    /// @param newMultiplier The new fee multiplier value
    function setFeeMultiplier(uint16 newMultiplier) external onlyOwner {
        uint16 oldMultiplier = feeMultiplier;
        feeMultiplier = newMultiplier;
        emit FeeMultiplierUpdated(oldMultiplier, newMultiplier);
    }

    /// @notice Set new early update window duration
    /// @param newWindow The new window duration in seconds
    function setEarlyUpdateWindow(uint256 newWindow) external onlyOwner {
        uint256 oldWindow = earlyUpdateWindow;
        earlyUpdateWindow = newWindow;
        emit EarlyUpdateWindowUpdated(oldWindow, newWindow);
    }

    /// @notice Get the description of this oracle
    /// @return A string describing this oracle
    function description() external pure override returns (string memory) {
        return "Moonwell Bounded Composite Oracle with OEV";
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

        ) = _getValidatedOracleData(primaryLBTCOracle);

        uint8 primaryDecimals = primaryLBTCOracle.decimals();
        primaryPrice = scalePrice(primaryPrice, primaryDecimals, decimals);

        // get BTC/USD price
        (, int256 btcUsdPrice, , ) = _getValidatedOracleData(
            btcChainlinkOracle
        );

        uint8 btcDecimals = btcChainlinkOracle.decimals();
        btcUsdPrice = scalePrice(btcUsdPrice, btcDecimals, decimals);

        // Check primary lbtc exchange rate oracle,
        // if primary is out of bounds, fall back to market rate oracle
        if (primaryPrice < lowerBound || primaryPrice > upperBound) {
            // fall back to market rate oracle if primary is out of bounds
            (, primaryPrice, primaryTimestamp, ) = _getValidatedOracleData(
                fallbackLBTCOracle
            );
            uint8 fallbackDecimals = fallbackLBTCOracle.decimals();
            primaryPrice = scalePrice(primaryPrice, fallbackDecimals, decimals);
        }

        answer = ((primaryPrice * btcUsdPrice) / (10 ** decimals).toInt256());

        return (0, answer, 0, primaryTimestamp, 0);
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
