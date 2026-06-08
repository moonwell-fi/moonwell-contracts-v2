pragma solidity 0.8.19;

import { ChainlinkAggregatorV3Interface } from "./ChainlinkAggregatorV3Interface.sol";

contract ChainlinkCompositeOracle {
    // ... existing code ...

    function getUnderlyingPrice(address cToken) public view returns (uint) {
        // ... existing code ...

        // Add multiplier validation
        require(multiplier != address(0), "Multiplier is not set");

        // ... existing code ...
    }

    // ... existing code ...

    address public multiplier;

    function setMultiplier(address _multiplier) public {
        require(_multiplier != address(0), "Multiplier cannot be zero");
        multiplier = _multiplier;
    }
}