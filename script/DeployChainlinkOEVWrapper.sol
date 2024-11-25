pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ChainlinkFeedOEVWrapper} from "@protocol/oracles/ChainlinkFeedOEVWrapper.sol";

contract DeployChainlinkOEVWrapper is Script {
    function run() public {
        Addresses addresses = new Addresses();
        vm.startBroadcast();
        deployChainlinkOEVWrapper(addresses, address(this));
        vm.stopBroadcast();
    }

    function deployChainlinkOEVWrapper(
        Addresses addresses,
        address deployer
    ) public returns (ChainlinkFeedOEVWrapper wrapper) {
        vm.startBroadcast(deployer);
        wrapper = new ChainlinkFeedOEVWrapper(
            addresses.getAddress("CHAINLINK_ETH_USD"),
            30 seconds,
            99,
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            addresses.getAddress("MOONWELL_WETH"),
            addresses.getAddress("WETH")
        );
        vm.stopBroadcast();
    }
}
