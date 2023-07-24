pragma solidity 0.8.19;

import "forge-std/Test.sol";

contract DecodingUnitTest is Test {
    struct json {
        uint256 amount;
        address user;
    }

    function testReadsJson() public view {
        string memory fileContents = vm.readFile("./test/unit/test.json");
        bytes memory rawJson = vm.parseJson(fileContents);

        console.logBytes(rawJson);

        json[] memory decodedJson = abi.decode(rawJson, (json[]));

        console.log("decodedJson.user:", decodedJson[0].user);
        console.log("decodedJson.amount:", decodedJson[0].amount);
    }

    function testSerializeAddress() public {
        string memory wormholeCore = vm.serializeAddress("", "UNITROLLER", address(0x4a8bc80Ed5a4067f1CCf107057b8270E0cC11A78));
        string memory building = vm.serializeAddress(wormholeCore, "WORMHOLE_CORE", address(0x4a8bc80Ed5a4067f1CCf107057b8270E0cC11A78));

        console.log("json: ", wormholeCore);
        console.log("building: ", building);
    }

    /// note, for some reason, foundry will not read in a JSON where an address is before a uint256
}
