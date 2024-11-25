pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {DeployChainlinkOEVWrapper} from "@script/DeployChainlinkOEVWrapper.sol";
import {ChainlinkFeedOEVWrapper} from "@protocol/oracles/ChainlinkFeedOEVWrapper.sol";

contract ChainlinkOEVWrapperIntegrationTest is Test {
    Addresses public addresses;

    ChainlinkFeedOEVWrapper public wrapper;

    function setUp() public {
        addresses = new Addresses();

        DeployChainlinkOEVWrapper deployScript = new DeployChainlinkOEVWrapper();
        wrapper = deployScript.deployChainlinkOEVWrapper(
            addresses,
            address(this)
        );
    }

    function testCanUpdatePriceEarly() public {
        vm.deal(address(this), 0 ether);
        int256 price = wrapper.updatePriceEarly{value: 0 ether}();

        (, int256 answer, , , ) = wrapper.latestRoundData();

        assertEq(price, answer, "Price should be the same");
    }
}
