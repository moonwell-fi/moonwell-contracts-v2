// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";

import {WETH9} from "@protocol/router/IWETH.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

/// @title ChainlinkFeedOEVWrapper
/// @notice A wrapper for Chainlink price feeds that allows early updates with a fee
/// @dev This contract implements the AggregatorV3Interface and adds OEV (Oracle Extractable Value) functionality
contract ChainlinkFeedOEVWrapper is AggregatorV3Interface, Ownable {
    /// @notice Emitted when the fee multiplier is changed
    /// @param newFee The new fee multiplier value
    event FeeMultiplierChanged(uint16 newFee);

    /// @notice Emitted when the early update window is changed
    /// @param newWindow The new early update window value
    event EarlyUpdateWindowChanged(uint256 newWindow);

    /// @notice Emitted when the price is updated
    /// @param receiver The address that received the update
    /// @param revenueAdded The amount of ETH added to the ETH market
    event ProtocolOEVRevenueUpdated(
        address indexed receiver,
        uint256 revenueAdded
    );

    /// @notice The original Chainlink price feed contract
    AggregatorV3Interface public immutable originalFeed;

    /// @notice The address of the WETH contract
    WETH9 public immutable WETH;

    /// @notice The address of the ETH market
    MErc20 public immutable WETHMarket;

    /// @notice The fee multiplier applied to the original feed's fee
    /// @dev Represented as a percentage
    uint16 public feeMultiplier;

    /// @notice The time window before the next update where early updates are allowed
    uint256 public earlyUpdateWindow;

    /// @notice The timestamp of the last cached price update
    uint256 public cachedTimestamp;

    /// @notice The last cached price value
    int256 public cachedPrice;

    /// @notice Constructor to initialize the wrapper
    /// @param _originalFeed Address of the original Chainlink feed
    /// @param _earlyUpdateWindow Time window for early updates
    /// @param _feeMultiplier Multiplier for the fee calculation
    /// @param _owner Address of the contract owner
    /// @param _ethMarket Address of the ETH market
    /// @param _weth Address of the WETH contract
    constructor(
        address _originalFeed,
        uint256 _earlyUpdateWindow,
        uint16 _feeMultiplier,
        address _owner,
        address _ethMarket,
        address _weth
    ) {
        originalFeed = AggregatorV3Interface(_originalFeed);
        WETHMarket = MErc20(_ethMarket);
        WETH = WETH9(_weth);

        earlyUpdateWindow = _earlyUpdateWindow;
        feeMultiplier = _feeMultiplier;

        // Initialize cache with current data
        (, int256 price, , uint256 timestamp, ) = originalFeed
            .latestRoundData();

        cachedPrice = price;
        cachedTimestamp = timestamp;

        transferOwnership(_owner);
    }

    /// @notice Get the latest round data
    /// @dev Returns cached data if within early update window, otherwise fetches from original feed
    /// @return roundId The round ID
    /// @return answer The price
    /// @return startedAt The timestamp when the round started
    /// @return updatedAt The timestamp when the round was updated
    /// @return answeredInRound The round ID in which the answer was computed
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

    /// @notice Update the price earlier than the standard update interval
    /// @dev Requires payment of a fee based on gas price and fee multiplier
    function updatePriceEarly() external payable returns (int256) {
        require(
            msg.value >= (tx.gasprice - block.basefee) * uint256(feeMultiplier),
            "ChainlinkOEVWrapper: Insufficient tax"
        );
        require(
            block.timestamp > cachedTimestamp,
            "ChainlinkOEVWrapper: New timestamp must be greater than current"
        );
        (
            uint80 roundId,
            int256 price,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = originalFeed.latestRoundData();

        require(price > 0, "Chainlink price cannot be lower than 0");
        require(updatedAt != 0, "Round is in incompleted state");
        require(answeredInRound >= roundId, "Stale price");

        cachedPrice = price;
        cachedTimestamp = block.timestamp;

        // wrap the ETH send into WETH and add to ETH market reserves
        WETH.deposit{value: msg.value}();
        WETH.approve(address(WETHMarket), msg.value);
        uint256 success = WETHMarket._addReserves(msg.value);
        require(success == 0, "ChainlinkOEVWrapper: Failed to add reserves");

        emit ProtocolOEVRevenueUpdated(address(WETHMarket), msg.value);

        return price;
    }

    /// @notice Get the number of decimals in the feed
    /// @return The number of decimals
    function decimals() external view override returns (uint8) {
        return originalFeed.decimals();
    }

    /// @notice Get the description of the feed
    /// @return The description string
    function description() external view override returns (string memory) {
        return originalFeed.description();
    }

    /// @notice Get the version number of the aggregator
    /// @return The version number
    function version() external view override returns (uint256) {
        return originalFeed.version();
    }

    /// @notice Get data about a specific round
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
        return originalFeed.getRoundData(_roundId);
    }

    /// @notice Set a new fee multiplier for early updates
    /// @param newMultiplier The new fee multiplier to set
    /// @dev Only callable by the contract owner
    function setFeeMultiplier(uint16 newMultiplier) public onlyOwner {
        feeMultiplier = newMultiplier;
        emit FeeMultiplierChanged(newMultiplier);
    }

    /// @notice Set a new early update window
    /// @param newWindow The new early update window duration in seconds
    /// @dev Only callable by the contract owner
    function setEarlyUpdateWindow(uint256 newWindow) public onlyOwner {
        earlyUpdateWindow = newWindow;
        emit EarlyUpdateWindowChanged(newWindow);
    }
}
