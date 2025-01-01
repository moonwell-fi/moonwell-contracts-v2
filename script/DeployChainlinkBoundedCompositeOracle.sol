// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {TransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
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
        oracle = new ChainlinkBoundedCompositeOracle();

        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,int256,int256,address)",
            addresses.getAddress("REDSTONE_LBTC_BTC"), // primary oracle
            addresses.getAddress("CHAINLINK_LBTC_MARKET"), // secondary oracle
            9.9e7, // lowerBound: 0.99
            1.05e8, // upperBound: 1.05
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );

        address proxy = address(
            new TransparentUpgradeableProxy(
                address(oracle),
                addresses.getAddress("MRD_PROXY_ADMIN"),
                initData
            )
        );

        addresses.addAddress(
            "CHAINLINK_BOUNDED_LBTC_COMPOSITE_ORACLE_LOGIC",
            address(oracle)
        );
        addresses.addAddress(
            "CHAINLINK_BOUNDED_LBTC_COMPOSITE_ORACLE_PROXY",
            proxy
        );

        oracle = ChainlinkBoundedCompositeOracle(proxy);
    }
}
