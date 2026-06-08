pragma solidity 0.8.19;

import { ChainlinkAggregatorV3Interface } from "./ChainlinkAggregatorV3Interface.sol";

contract ChainlinkOracle {
    // ... existing code ...

    function getUnderlyingPrice(address cToken) public view returns (uint) {
        // ... existing code ...

        // Add minAnswer and maxAnswer boundary checks
        uint price = priceFeed.latestAnswer();
        require(price >= minAnswer && price <= maxAnswer, "Price out of bounds");

        // Add staleness check
        uint updatedAt = priceFeed.latestTimestamp();
        require(updatedAt >= block.timestamp - stalenessThreshold, "Price is stale");

        return price;
    }

    // ... existing code ...

    uint public minAnswer;
    uint public maxAnswer;
    uint public stalenessThreshold;

    function setMinAnswer(uint _minAnswer) public {
        minAnswer = _minAnswer;
    }

    function setMaxAnswer(uint _maxAnswer) public {
        maxAnswer = _maxAnswer;
    }

    function setStalenessThreshold(uint _stalenessThreshold) public {
        stalenessThreshold = _stalenessThreshold;
    }
}