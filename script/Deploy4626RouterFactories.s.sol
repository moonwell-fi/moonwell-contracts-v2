pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {deploy4626Router, deployFactory, deployFactoryEth} from "@protocol/4626/4626FactoryDeploy.sol";

/// forge script script/Deploy4626RouterFactories.s.sol:Deploy4626RouterFactories --fork-url base -vvv
contract Deploy4626RouterFactories is Script {
    /// @notice addresses contract
    Addresses addresses;

    constructor() {
        addresses = new Addresses();
    }

    function run() public {
        vm.startBroadcast();
        deployFactory(addresses);
        deployFactoryEth(addresses);
        deploy4626Router(addresses);
        vm.stopBroadcast();
    }
}
