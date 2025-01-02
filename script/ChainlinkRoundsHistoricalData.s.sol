// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console2} from "@forge-std/Script.sol";
import "@forge-std/StdJson.sol";
import {IMulticall3} from "@forge-std/interfaces/IMulticall3.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {Vm} from "@forge-std/Vm.sol";

contract RoundDataHelper is Script {
    function createMulticallBatch(
        address priceFeedAddress,
        uint80 startRound,
        uint256 batchSize
    ) public pure returns (IMulticall3.Call3[] memory) {
        IMulticall3.Call3[] memory calls = new IMulticall3.Call3[](batchSize);
        bytes4 selector = bytes4(keccak256("getRoundData(uint80)"));

        for (uint256 i = 0; i < batchSize; i++) {
            calls[i].target = priceFeedAddress;
            calls[i].allowFailure = true;
            calls[i].callData = abi.encodeWithSelector(
                selector,
                uint80(startRound - i)
            );
        }

        return calls;
    }

    function formatRoundData(
        uint80 roundId,
        int256 answer,
        uint256 updatedAt,
        bool needsComma
    ) public view returns (string memory) {
        return
            string.concat(
                needsComma ? "," : "",
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
}

contract ChainlinkRoundsHistoricalData is Script {
    using stdJson for string;

    address constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;
    uint256 constant BATCH_SIZE = 1000;

    RoundDataHelper helper;
    string private jsonPath;
    string private existingJson;
    bool private hasExistingData;
    uint256 private sixMonthsAgo;

    function processResults(
        IMulticall3.Result[] memory results
    )
        private
        returns (string memory batchJson, bool reachedTarget, uint80 lastRound)
    {
        string memory json = "";
        uint256 lastTimestamp = type(uint256).max;
        bool needsComma = hasExistingData;
        uint256 successCount = 0;

        for (uint256 i = 0; i < results.length; i++) {
            if (!results[i].success) {
                console2.log("Failed call at index:", i);
                continue;
            }

            (uint80 roundId, int256 answer, , uint256 updatedAt, ) = abi.decode(
                results[i].returnData,
                (uint80, int256, uint256, uint256, uint80)
            );

            if (updatedAt < sixMonthsAgo) {
                console2.log(
                    "Reached target timestamp. Current:",
                    updatedAt,
                    "Target:",
                    sixMonthsAgo
                );
                reachedTarget = true;
                break;
            }

            json = string.concat(
                json,
                helper.formatRoundData(roundId, answer, updatedAt, needsComma)
            );

            needsComma = true;
            lastRound = roundId;
            successCount++;

            if (updatedAt < lastTimestamp) {
                lastTimestamp = updatedAt;
            }
        }

        console2.log("Processed batch. Successful calls:", successCount);
        if (lastTimestamp != type(uint256).max) {
            console2.log("Latest timestamp in batch:", lastTimestamp);
        }

        return (json, reachedTarget, lastRound);
    }

    function saveToFile(string memory batchJson) private {
        string memory fullJson = string.concat(existingJson, batchJson, "]");
        vm.writeFile(jsonPath, fullJson);
        console2.log(
            "Saved progress to file. Current JSON length:",
            bytes(fullJson).length
        );

        existingJson = string.concat(existingJson, batchJson);
        hasExistingData = true;
    }

    function run(address priceFeedAddress) external {
        console2.log("Starting script with price feed:", priceFeedAddress);

        helper = new RoundDataHelper();
        sixMonthsAgo = block.timestamp - (6 * 30 days);
        console2.log("Current time:", block.timestamp);
        console2.log("Target time (6 months ago):", sixMonthsAgo);

        jsonPath = string.concat(
            vm.projectRoot(),
            "/output/chainlink_historical_data_",
            vm.toString(block.chainid),
            ".json"
        );
        console2.log("Output file:", jsonPath);

        uint80 currentRoundId;
        try vm.readFile(jsonPath) returns (string memory content) {
            if (bytes(content).length > 0) {
                // Get the last round ID from the file
                bytes memory parsed = vm.parseJson(content, ".[-1].roundId");
                currentRoundId = uint80(abi.decode(parsed, (uint256)));
                existingJson = substring(content, 0, bytes(content).length - 1);
                hasExistingData = true;
                console2.log(
                    "Found existing data. Last roundId:",
                    currentRoundId
                );
            } else {
                existingJson = "[";
                hasExistingData = false;
                console2.log("Starting fresh - no existing data");
                currentRoundId = uint80(
                    AggregatorV3Interface(priceFeedAddress).latestRound()
                );
                console2.log("Starting from latest round ID:", currentRoundId);
            }
        } catch {
            existingJson = "[";
            hasExistingData = false;
            console2.log("Starting fresh - no existing data (file not found)");
            currentRoundId = uint80(
                AggregatorV3Interface(priceFeedAddress).latestRound()
            );
            console2.log("Starting from latest round ID:", currentRoundId);
        }

        IMulticall3 multicall = IMulticall3(MULTICALL3);
        bool reachedTarget = false;
        while (!reachedTarget && currentRoundId > 0) {
            console2.log("Processing batch from round:", currentRoundId);

            IMulticall3.Call3[] memory calls = helper.createMulticallBatch(
                priceFeedAddress,
                currentRoundId,
                BATCH_SIZE
            );

            IMulticall3.Result[] memory results = multicall.aggregate3(calls);
            console2.log("Got multicall results. Length:", results.length);

            (
                string memory batchJson,
                bool batchReachedTarget,
                uint80 lastProcessedRound
            ) = processResults(results);

            if (bytes(batchJson).length > 0) {
                saveToFile(batchJson);
            } else {
                console2.log("No data in this batch");
            }

            reachedTarget = batchReachedTarget;
            currentRoundId = uint80(currentRoundId - BATCH_SIZE);
        }

        console2.log("Completed processing all rounds");
    }

    function substring(
        string memory str,
        uint256 start,
        uint256 end
    ) private pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = strBytes[i];
        }
        return string(result);
    }
}
