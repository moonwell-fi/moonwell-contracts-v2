// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console2} from "@forge-std/Script.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {IMulticall3} from "@forge-std/interfaces/IMulticall3.sol";
import "@forge-std/StdJson.sol";

contract ChainlinkRoundsHistoricalData is Script {
    using stdJson for string;

    // Optimism Multicall3 address
    address constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;

    function run(address priceFeedAddress, uint256 chainId) external {
        IMulticall3 multicall = IMulticall3(MULTICALL3);
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            priceFeedAddress
        );

        uint256 sixMonthsAgo = block.timestamp - (6 * 30 days);

        // Initialize JSON content
        string memory jsonContent = "[";
        bool isFirst = true;

        // Get the latest round ID
        uint80 currentRoundId = uint80(priceFeed.latestRound());
        bool reachedTarget = false;
        uint256 batchSize = 10_000;

        while (!reachedTarget) {
            // Prepare batch calls
            IMulticall3.Call3[] memory calls = new IMulticall3.Call3[](
                batchSize
            );

            // Prepare the getRoundData calls
            bytes4 getRoundDataSelector = bytes4(
                keccak256("getRoundData(uint80)")
            );

            for (uint256 i = 0; i < batchSize; i++) {
                uint80 roundId = uint80(currentRoundId - i);
                calls[i] = IMulticall3.Call3({
                    target: priceFeedAddress,
                    callData: abi.encodeWithSelector(
                        getRoundDataSelector,
                        roundId
                    ),
                    allowFailure: true
                });
            }

            // Execute multicall
            IMulticall3.Result[] memory results = multicall.aggregate3(calls);

            // Process results
            uint256 lastValidTimestamp = type(uint256).max;

            for (uint256 i = 0; i < results.length; i++) {
                if (!results[i].success) continue;

                // Decode the result
                (
                    uint80 roundId,
                    int256 answer,
                    uint256 startedAt,
                    uint256 updatedAt,
                    uint80 answeredInRound
                ) = abi.decode(
                        results[i].returnData,
                        (uint80, int256, uint256, uint256, uint80)
                    );

                // Update last valid timestamp
                if (updatedAt < lastValidTimestamp) {
                    lastValidTimestamp = updatedAt;
                }

                // Skip if older than 6 months
                if (updatedAt < sixMonthsAgo) {
                    reachedTarget = true;
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
                    vm.toString(roundId),
                    ",",
                    '"roundPrice":"',
                    vm.toString(answer),
                    '",',
                    '"roundTimestamp":',
                    vm.toString(updatedAt),
                    "}"
                );
            }

            // Update currentRoundId for next batch
            currentRoundId = uint80(currentRoundId - batchSize);

            // Break if we've processed all rounds or reached target
            if (currentRoundId == 0 || reachedTarget) {
                break;
            }

            // Log progress
            console2.log(
                "Processed batch. Last timestamp:",
                lastValidTimestamp,
                "Target:",
                sixMonthsAgo
            );
        }

        // Close JSON array
        jsonContent = string.concat(jsonContent, "]");

        // Prepare JSON file path
        string memory jsonPath = string.concat(
            vm.projectRoot(),
            "/output/chainlink_historical_data_",
            vm.toString(chainId),
            ".json"
        );

        // Write complete JSON to file
        vm.writeFile(jsonPath, jsonContent);

        // Log the file location
        console2.log("Data written to:", jsonPath);
    }
}
