// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";
import {console} from "@forge-std/console.sol";

import {WETH9} from "@protocol/router/IWETH.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

/// @title ChainlinkFeedOEVWrapper
/// @notice A wrapper for Chainlink price feeds that allows early updates with a fee
/// @dev This contract implements the AggregatorV3Interface and adds OEV (Oracle Extractable Value) functionality
contract ChainlinkFeedOEVWrapper is AggregatorV3Interface, Ownable {
    /// @notice Emitted when the fee multiplier is changed
    /// @param oldFee The old fee multiplier value
    /// @param newFee The new fee multiplier value
    event FeeMultiplierChanged(uint8 oldFee, uint8 newFee);

    /// @notice Emitted when the price is updated
    /// @param receiver The address that received the update
    /// @param revenueAdded The amount of ETH added to the ETH market
    event ProtocolOEVRevenueUpdated(
        address indexed receiver,
        uint256 revenueAdded,
        uint256 roundId
    );

    /// @notice Emitted when the max decrements value is changed
    /// @param oldMaxDecrements The old maximum number of decrements
    /// @param newMaxDecrements The new maximum number of decrements
    event MaxDecrementsChanged(uint8 oldMaxDecrements, uint8 newMaxDecrements);

    /// @notice Emitted when the max round delay is changed
    /// @param oldMaxRoundDelay The old maximum round delay
    /// @param newMaxRoundDelay The new maximum round delay
    event NewMaxRoundDelay(uint8 oldMaxRoundDelay, uint8 newMaxRoundDelay);

    /// @notice The original Chainlink price feed contract
    AggregatorV3Interface public immutable originalFeed;

    /// @notice The address of the WETH contract
    WETH9 public immutable WETH;

    /// @notice The address of the ETH market
    MErc20 public immutable WETHMarket;

    /// @notice The fee multiplier applied to the original feed's fee
    /// @dev Represented as a percentage
    uint8 public feeMultiplier;

    /// @notice The maximum number of times to decrement the round before falling back to latest price
    uint8 public maxDecrements;

    /// @notice The max delay a round can have before falling back to latest price
    uint8 public maxRoundDelay;

    /// @notice The last cached round id
    uint256 public cachedRoundId;

    /// @notice Constructor to initialize the wrapper
    /// @param _originalFeed Address of the original Chainlink feed
    /// @param _feeMultiplier The fee multiplier to apply to the original feed's fee
    /// @param _owner Address of the contract owner
    /// @param _ethMarket Address of the ETH market
    /// @param _weth Address of the WETH contract
    /// @param _maxDecrements The maximum number of decrements before falling back to latest price
    /// @param _maxRoundDelay The max delay a round can have before falling back to latest price
    constructor(
        address _originalFeed,
        uint8 _feeMultiplier,
        address _owner,
        address _ethMarket,
        address _weth,
        uint8 _maxDecrements,
        uint8 _maxRoundDelay
    ) {
        originalFeed = AggregatorV3Interface(_originalFeed);
        WETHMarket = MErc20(_ethMarket);
        WETH = WETH9(_weth);

        feeMultiplier = _feeMultiplier;
        maxDecrements = _maxDecrements;
        maxRoundDelay = _maxRoundDelay;

        cachedRoundId = originalFeed.latestRound();

        transferOwnership(_owner);
    }

    /// @notice Get the latest round data
    /// @dev Returns cached data if the current round is the same as the cached round and 10 seconds have not passed
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
        (roundId, answer, startedAt, updatedAt, answeredInRound) = originalFeed
            .latestRoundData();

        console.log("block.timestamp", block.timestamp);
        console.log("updateAt", updatedAt);
        console.log("max round delay", maxRoundDelay);
        console.log("currentRoundId", roundId);
        console.log("cachedRoundId", cachedRoundId);

        // Return the current round data if either:
        // 1. This round has already been cached (meaning someone paid for it)
        // 2. The round is too old
        if (
            roundId == cachedRoundId ||
            block.timestamp >= updatedAt + maxRoundDelay
        ) {
            _validateRoundData(roundId, answer, updatedAt, answeredInRound);
            return (roundId, answer, startedAt, updatedAt, answeredInRound);
        }

        uint256 startRoundId = roundId;

        // If the current round is not too old and hasn't been paid for,
        // attempt to find the most recent valid round by checking previous rounds
        for (uint256 i = 0; i < maxDecrements && --startRoundId > 0; i++) {
            try originalFeed.getRoundData(uint80(startRoundId)) returns (
                uint80 r,
                int256 a,
                uint256 s,
                uint256 u,
                uint80 ar
            ) {
                _validateRoundData(r, a, u, ar);

                roundId = r;
                answer = a;
                startedAt = s;
                updatedAt = u;
                answeredInRound = ar;
                return (roundId, answer, startedAt, updatedAt, answeredInRound);
            } catch {
                // Decrement the round ID for next iteration
                startRoundId--;
            }
        }
    }

    /// @notice Update the price earlier than the standard update interval
    /// @return The latest round ID
    /// @dev Requires payment of a fee based on gas price and fee multiplier
    function updatePriceEarly() external payable returns (uint256) {
        require(
            msg.value >= (tx.gasprice - block.basefee) * uint256(feeMultiplier),
            "ChainlinkOEVWrapper: Insufficient tax"
        );

        // Get latest round data and validate it
        (
            uint256 latestRoundId,
            int256 latestAnswer,
            ,
            uint256 latestUpdatedAt,
            uint80 latestAnsweredInRound
        ) = originalFeed.latestRoundData();

        _validateRoundData(
            uint80(latestRoundId),
            latestAnswer,
            latestUpdatedAt,
            latestAnsweredInRound
        );

        require(
            latestRoundId > cachedRoundId,
            "ChainlinkOEVWrapper: New round is not higher than cached"
        );

        // Convert ETH to WETH and approve it for the ETH market
        WETH.deposit{value: msg.value}();
        WETH.approve(address(WETHMarket), msg.value);

        // Add the ETH to the market's reserves
        require(
            WETHMarket._addReserves(msg.value) == 0,
            "ChainlinkOEVWrapper: Failed to add reserves"
        );

        emit ProtocolOEVRevenueUpdated(
            address(WETHMarket),
            msg.value,
            latestRoundId
        );

        cachedRoundId = latestRoundId;
        return cachedRoundId;
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
        (roundId, answer, startedAt, updatedAt, answeredInRound) = originalFeed
            .getRoundData(_roundId);
    }

    /// @notice Get the latest round ID
    /// @return The latest round ID
    function latestRound() external view override returns (uint256) {
        return originalFeed.latestRound();
    }

    /// @notice Set a new fee multiplier for early updates
    /// @param newMultiplier The new fee multiplier to set
    /// @dev Only callable by the contract owner
    function setFeeMultiplier(uint8 newMultiplier) external onlyOwner {
        uint8 oldMultiplier = feeMultiplier;
        feeMultiplier = newMultiplier;

        emit FeeMultiplierChanged(oldMultiplier, newMultiplier);
    }

    /// @notice Set the maximum number of decrements before falling back to latest price
    /// @param _maxDecrements The new maximum number of decrements
    function setMaxDecrements(uint8 _maxDecrements) external onlyOwner {
        uint8 oldMaxDecrements = maxDecrements;
        maxDecrements = _maxDecrements;

        emit MaxDecrementsChanged(oldMaxDecrements, _maxDecrements);
    }

    /// @notice Set the maximum round delay
    /// @param _maxRoundDelay The new maximum round delay
    function setMaxRoundDelay(uint8 _maxRoundDelay) external onlyOwner {
        uint8 oldMaxRoundDelay = maxRoundDelay;
        maxRoundDelay = _maxRoundDelay;

        emit NewMaxRoundDelay(oldMaxRoundDelay, maxRoundDelay);
    }

    /// @notice Validate the round data from Chainlink
    /// @param roundId The round ID to validate
    /// @param answer The price to validate
    /// @param updatedAt The timestamp when the round was updated
    /// @param answeredInRound The round ID in which the answer was computed
    function _validateRoundData(
        uint80 roundId,
        int256 answer,
        uint256 updatedAt,
        uint80 answeredInRound
    ) internal pure {
        require(answer > 0, "Chainlink price cannot be lower or equal to 0");
        require(updatedAt != 0, "Round is in incompleted state");
        require(answeredInRound >= roundId, "Stale price");
    }
}
