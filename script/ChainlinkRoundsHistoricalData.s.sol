// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console2} from "@forge-std/Script.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import "@forge-std/StdJson.sol";

contract ChainlinkRoundsHistoricalData is Script {
    using stdJson for string;

    function run(address priceFeedAddress, uint256 chainId) external {
        // Set up the price feed interface
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            priceFeedAddress
        );

        uint256 currentTimestamp = block.timestamp;

        // 6 months ago timestamp (approximately)
        uint256 sixMonthsAgo = currentTimestamp - (6 months);

        // Prepare JSON file path
        string memory jsonPath = string.concat(
            vm.projectRoot(),
            "/output/chainlink_historical_data_",
            vm.toString(chainId),
            ".json"
        );

        // Initialize JSON content with array opening
        string memory jsonContent = "[";
        bool isFirst = true;

        // Get the latest round ID
        uint80 latestRoundId = uint80(priceFeed.latestRound());

        // Loop through rounds backwards
        for (uint80 roundId = latestRoundId; roundId > 0; roundId--) {
            try priceFeed.getRoundData(roundId) returns (
                uint80 roundIdData,
                int256 answer,
                uint256 startedAt,
                uint256 updatedAt,
                uint80 answeredInRound
            ) {
                // Break if we've gone back more than 6 months
                if (updatedAt < sixMonthsAgo) {
                    break;
                }

                // Add comma if not first entry
                if (!isFirst) {
                    jsonContent = string.concat(jsonContent, ",");
                }
                isFirst = false;

                // Add object to JSON array
                jsonContent = string.concat(
                    jsonContent,
                    "{",
                    '"roundId":',
                    vm.toString(roundIdData),
                    ",",
                    '"roundPrice":"',
                    vm.toString(answer),
                    '",',
                    '"roundTimestamp":',
                    vm.toString(updatedAt),
                    "}"
                );
            } catch {
                // Skip rounds that can't be retrieved
                continue;
            }
        }

        // Close JSON array
        jsonContent = string.concat(jsonContent, "]");

        // Write complete JSON to file
        vm.writeFile(jsonPath, jsonContent);
    }
}
