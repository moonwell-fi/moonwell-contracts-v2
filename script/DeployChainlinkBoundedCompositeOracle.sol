// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ChainlinkBoundedCompositeOracle} from "@protocol/oracles/ChainlinkBoundedCompositeOracle.sol";

contract DeployChainlinkBoundedCompositeOracle is Script {
    function run() public {
        Addresses addresses = new Addresses();
        vm.startBroadcast();
        deployChainlinkBoundedCompositeOracle(addresses);
        vm.stopBroadcast();
    }

    function deployChainlinkBoundedCompositeOracle(
        Addresses addresses
    ) public returns (ChainlinkBoundedCompositeOracle oracle) {
        oracle = new ChainlinkBoundedCompositeOracle(
            addresses.getAddress("REDSTONE_LBTC_BTC"), // primary oracle
            addresses.getAddress("CHAINLINK_LBTC_MARKET"), // secondary oracle
            9.9e17, // lowerBound: 0.99
            1.05e18, // upperBound: 1.05
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );

        addresses.addAddress(
            "CHAINLINK_BOUNDED_LBTC_COMPOSITE_ORACLE",
            address(oracle)
        );
    }
}
