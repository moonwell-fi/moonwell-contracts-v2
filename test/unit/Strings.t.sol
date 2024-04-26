pragma solidity 0.8.19;

import {String} from "@utils/String.sol";
import "@forge-std/Test.sol";

contract StringTest is Test {
    using String for string;

    function testHasChar() public {
        string memory testString = "hello world";
        bytes1 delimiter = " ";
        bool result = testString.hasChar(delimiter);
        assertEq(result, true, "hasChar failed");
    }

    function testCountWords() public {
        string memory testString = "hello world test";
        bytes1 delimiter = " ";
        uint256 count = testString.countWords(delimiter);
        assertEq(count, 3, "countWords failed");
    }

    function testCheckNoDoubleDelimiters() public {
        string memory testString = "hello  world";
        bytes1 delimiter = " ";
        bool result = testString.checkNoDoubleDelimiters(delimiter);
        assertEq(result, false, "checkNoDoubleDelimiters failed");
    }

    function testSplitTwoWords() public {
        string memory testString = "hello world";
        bytes1 delimiter = " ";
        string[] memory splitResult = testString.split(delimiter);
        assertEq(splitResult.length, 2, "split failed");
        assertEq(splitResult[0], "hello", "split failed");
        assertEq(splitResult[1], "world", "split failed");
    }

    function testSplitThreeWords() public {
        string memory testString = "hello world test";
        bytes1 delimiter = " ";
        string[] memory splitResult = testString.split(delimiter);
        assertEq(splitResult.length, 3, "split failed, length is not 3");
        assertEq(splitResult[0], "hello", "split failed, word 1");
        assertEq(splitResult[1], "world", "split failed, word 2");
        assertEq(splitResult[2], "test", "split failed, word 3");
    }

    function testSplitFourChars() public {
        string memory testString = "a b c d";
        bytes1 delimiter = " ";
        string[] memory splitResult = testString.split(delimiter);
        assertEq(splitResult.length, 4, "split failed, length is not 3");
        assertEq(splitResult[0], "a", "split failed, word 1");
        assertEq(splitResult[1], "b", "split failed, word 2");
        assertEq(splitResult[2], "c", "split failed, word 3");
        assertEq(splitResult[3], "d", "split failed, word 4");
    }

    function testSplitCommaDelimitedPaths() public {
        string
            memory testString = "artifacts/foundry/mip-b05.sol/mipb05.json,artifacts/foundry/mip-b04.sol/mipb04.json,artifacts/foundry/mip-b03.sol/mipb03.json";
        bytes1 delimiter = ",";
        string[] memory splitResult = testString.split(delimiter);
        assertEq(splitResult.length, 3, "split failed, length is not 3");
        assertEq(
            splitResult[0],
            "artifacts/foundry/mip-b05.sol/mipb05.json",
            "split failed, word 1"
        );
        assertEq(
            splitResult[1],
            "artifacts/foundry/mip-b04.sol/mipb04.json",
            "split failed, word 2"
        );
        assertEq(
            splitResult[2],
            "artifacts/foundry/mip-b03.sol/mipb03.json",
            "split failed, word 3"
        );
    }

    function testSplitCommaDelimitedMixed() public {
        string
            memory testString = "hello,world,artifacts/foundry/mip-b05.sol/mipb05.json";
        bytes1 delimiter = ",";
        string[] memory splitResult = testString.split(delimiter);
        assertEq(splitResult.length, 3, "split failed, length is not 3");
        assertEq(splitResult[0], "hello", "split failed, word 1");
        assertEq(splitResult[1], "world", "split failed, word 2");
        assertEq(
            splitResult[2],
            "artifacts/foundry/mip-b05.sol/mipb05.json",
            "split failed, word 3"
        );
    }

    function testSplitCommaDelimitedSingle() public {
        string memory testString = "artifacts/foundry/mip-b05.sol/mipb05.json";
        bytes1 delimiter = ",";
        string[] memory splitResult = testString.split(delimiter);
        assertEq(splitResult.length, 1, "split failed, length is not 1");
        assertEq(
            splitResult[0],
            "artifacts/foundry/mip-b05.sol/mipb05.json",
            "split failed, word 1"
        );
    }
}
