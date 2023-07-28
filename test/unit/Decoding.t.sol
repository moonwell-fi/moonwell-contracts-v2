pragma solidity 0.8.19;

import "forge-std/Test.sol";

contract DecodingUnitTest is Test {
    struct json {
        uint256 amount;
        address user;
    }

    struct CTokenConfiguration {
        string addressesString; /// string used to set address in Addresses.sol
        uint256 borrowCap; /// borrow cap
        uint256 collateralFactor; /// collateral factor of the asset
        uint256 initialMintAmount;
        JumpRateModelConfiguration jrm; /// jump rate model configuration information
        string name; /// name of the mToken
        address priceFeed; /// chainlink price oracle
        uint256 reserveFactor; /// reserve factor of the asset
        uint256 seizeShare; /// fee gotten from liquidation
        uint256 supplyCap; /// supply cap
        string symbol; /// symbol of the mToken
        address tokenAddress; /// underlying token address
    }

    struct JumpRateModelConfiguration {
        uint256 baseRatePerYear;
        uint256 jumpMultiplierPerYear;
        uint256 kink;
        uint256 multiplierPerYear;
    }

    function testReadsJson() public view {
        string memory fileContents = vm.readFile("./test/unit/test.json");
        bytes memory rawJson = vm.parseJson(fileContents);

        console.logBytes(rawJson);

        json[] memory decodedJson = abi.decode(rawJson, (json[]));

        for (uint256 i = 0; i < decodedJson.length; i++) {
            console.log("decodedJson.user:", decodedJson[i].user);
            console.log("decodedJson.amount:", decodedJson[i].amount);
        }
    }

    function testReadsMTokenJson() public view {
        string memory fileContents = vm.readFile("./test/unit/mainnetMTokens.json");
        bytes memory rawJson = vm.parseJson(fileContents);

        console.logBytes(rawJson);

        CTokenConfiguration[] memory decodedJson = abi.decode(rawJson, (CTokenConfiguration[]));

        for (uint256 i = 0; i < decodedJson.length; i++) {
            console.log("\n ------ MToken Configuration ------");
            console.log("addressesString:", decodedJson[i].addressesString);
            console.log("borrowCap:", decodedJson[i].borrowCap);
            console.log("collateralFactor:", decodedJson[i].collateralFactor);
            console.log("initialMintAmount:", decodedJson[i].initialMintAmount);
            console.log("name:", decodedJson[i].name);
            console.log("priceFeed:", decodedJson[i].priceFeed);
            console.log("reserveFactor:", decodedJson[i].reserveFactor);
            console.log("seizeShare:", decodedJson[i].seizeShare);
            console.log("supplyCap:", decodedJson[i].supplyCap);
            console.log("symbol:", decodedJson[i].symbol);
            console.log("tokenAddress:", decodedJson[i].tokenAddress);
            console.log("jrm.baseRatePerYear:", decodedJson[i].jrm.baseRatePerYear);
            console.log("jrm.multiplierPerYear:", decodedJson[i].jrm.multiplierPerYear);
            console.log("jrm.jumpMultiplierPerYear:", decodedJson[i].jrm.jumpMultiplierPerYear);
            console.log("jrm.kink:", decodedJson[i].jrm.kink);
        }
    }

    function testSerializeAddress() public {
        string memory wormholeCore = vm.serializeAddress(
            "",
            "UNITROLLER",
            address(0x4a8bc80Ed5a4067f1CCf107057b8270E0cC11A78)
        );
        string memory building = vm.serializeAddress(
            wormholeCore,
            "WORMHOLE_CORE",
            address(0x4a8bc80Ed5a4067f1CCf107057b8270E0cC11A78)
        );

        console.log("json: ", wormholeCore);
        console.log("building: ", building);
    }

    /// note, for some reason, foundry will not read in a JSON where an address is before a uint256
}
