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
            unchecked {
                calls[i].callData = abi.encodeWithSelector(
                    selector,
                    uint80(startRound - i) // Use unchecked for round decrement
                );
            }
        }

        return calls;
    }

    function formatRoundData(
        uint80 roundId,
        int256 answer,
        uint256 updatedAt,
        bool needsComma
    ) public pure returns (string memory) {
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

// time forge script script/ChainlinkRoundsHistoricalData.s.sol:ChainlinkRoundsHistoricalData \
//    --rpc-url optimism \
//    --sig "run(address)" \
//    0x13e3Ee699D1909E989722E753853AE30b17e08c5 \
//    --fork-retries 10
//  --fork-retry-backoff 1000
contract ChainlinkRoundsHistoricalData is Script {
    using stdJson for string;

    address constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;
    uint256 constant BATCH_SIZE = 200;

    RoundDataHelper helper;
    string private jsonPath;
    string private existingJson;
    bool private hasExistingData;
    uint256 private sixMonthsAgo;

    function processResults(
        IMulticall3.Result[] memory results
    )
        private
        view
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
                console2.log("Reached target timestamp. Current:", updatedAt);
                console2.log("Target:", sixMonthsAgo);
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
        string memory filePath = string.concat(
            vm.projectRoot(),
            "/output/chainlink_historical_data_",
            vm.toString(block.chainid),
            ".json"
        );

        string memory content;
        if (hasExistingData) {
            // If we have existing data, just append the new batch
            content = string.concat(existingJson, batchJson, "]");
        } else {
            // If this is a new file, create a fresh JSON array
            content = string.concat("[", batchJson, "]");
        }

        vm.writeFile(filePath, content);
        hasExistingData = true;
        existingJson = substring(content, 0, bytes(content).length - 1);
    }

    function run(address priceFeedAddress) external {
        console2.log("Starting script with price feed:", priceFeedAddress);

        helper = new RoundDataHelper();
        unchecked {
            sixMonthsAgo = block.timestamp - (180 days); // Use unchecked for timestamp subtraction
        }
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
                // Find the last valid JSON object
                bytes memory contentBytes = bytes(content);
                uint256 closingBracketPos = 0;
                uint256 lastValidObjectEnd = 0;

                // First find the closing bracket of the array
                for (uint i = 0; i < contentBytes.length; i++) {
                    if (contentBytes[i] == "]") {
                        closingBracketPos = i;
                        break;
                    }
                }

                if (closingBracketPos > 0) {
                    // Now find the last complete object before the closing bracket
                    uint256 openBraces = 0;
                    for (uint i = 0; i < closingBracketPos; i++) {
                        if (contentBytes[i] == "{") {
                            openBraces++;
                        } else if (contentBytes[i] == "}") {
                            openBraces--;
                            if (openBraces == 0) {
                                lastValidObjectEnd = i + 1;
                            }
                        }
                    }

                    if (lastValidObjectEnd > 0) {
                        // Get the content up to the last valid object
                        content = substring(content, 0, lastValidObjectEnd);
                        existingJson = content;
                        hasExistingData = true;

                        // Parse the last object to get the roundId
                        uint256 lastObjectStart = 0;
                        for (uint i = 0; i < lastValidObjectEnd; i++) {
                            if (contentBytes[i] == "{") {
                                lastObjectStart = i;
                            }
                        }

                        string memory lastObject = substring(
                            content,
                            lastObjectStart,
                            lastValidObjectEnd
                        );
                        try vm.parseJson(lastObject, ".roundId") returns (
                            bytes memory roundIdBytes
                        ) {
                            currentRoundId =
                                abi.decode(roundIdBytes, (uint80)) +
                                uint80(1);
                            console2.log(
                                "Continuing from round ID:",
                                currentRoundId
                            );
                        } catch {
                            console2.log(
                                "Failed to parse last round ID, starting fresh"
                            );
                            currentRoundId = uint80(
                                AggregatorV3Interface(priceFeedAddress)
                                    .latestRound()
                            );
                        }
                    } else {
                        console2.log("No valid objects found, starting fresh");
                        existingJson = "[";
                        hasExistingData = false;
                        currentRoundId = uint80(
                            AggregatorV3Interface(priceFeedAddress)
                                .latestRound()
                        );
                    }
                } else {
                    console2.log("No closing bracket found, starting fresh");
                    existingJson = "[";
                    hasExistingData = false;
                    currentRoundId = uint80(
                        AggregatorV3Interface(priceFeedAddress).latestRound()
                    );
                }
            } else {
                console2.log("Empty file, starting fresh");
                existingJson = "[";
                hasExistingData = false;
                currentRoundId = uint80(
                    AggregatorV3Interface(priceFeedAddress).latestRound()
                );
            }
        } catch {
            console2.log("File doesn't exist, starting fresh");
            existingJson = "[";
            hasExistingData = false;
            currentRoundId = uint80(
                AggregatorV3Interface(priceFeedAddress).latestRound()
            );
        }

        if (!hasExistingData) {
            console2.log("Starting from latest round ID:", currentRoundId);
        }

        bool reachedTarget = false;
        while (!reachedTarget) {
            console2.log("Processing batch from round:", currentRoundId);

            IMulticall3.Call3[] memory calls = helper.createMulticallBatch(
                priceFeedAddress,
                currentRoundId,
                BATCH_SIZE
            );

            (bool success, bytes memory returnData) = MULTICALL3.call(
                abi.encodeWithSelector(IMulticall3.aggregate3.selector, calls)
            );

            if (!success) {
                console2.log("Multicall failed");
                break;
            }

            IMulticall3.Result[] memory results = abi.decode(
                returnData,
                (IMulticall3.Result[])
            );

            (
                string memory batchJson,
                bool targetReached,
                uint80 lastRound
            ) = processResults(results);

            if (bytes(batchJson).length > 0) {
                saveToFile(batchJson);
            }

            if (targetReached) {
                console2.log("Reached target timestamp");
                reachedTarget = true;
                break;
            }

            if (lastRound > 0) {
                unchecked {
                    currentRoundId = lastRound - 1; // Use unchecked for round ID decrement
                }
            } else {
                // If we didn't get any valid results in this batch, try the next batch
                if (currentRoundId > BATCH_SIZE) {
                    unchecked {
                        currentRoundId -= uint80(BATCH_SIZE); // Use unchecked for batch size subtraction
                    }
                } else {
                    break; // Prevent underflow
                }
            }
        }

        console2.log("Script completed");
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
