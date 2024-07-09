pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {xWELLRouter} from "@protocol/xWELL/xWELLRouter.sol";

contract BridgeXWell is Script, Test {
    /// @notice addresses contract
    Addresses addresses;

    constructor() {
        addresses = new Addresses();
    }

    function run() public {
        xWELLRouter router = xWELLRouter(addresses.getAddress("xWELL_ROUTER"));

        uint256 bridgeCost = router.bridgeCost();

        uint256 amount = 100_000 * 1e18;

        vm.startBroadcast();

        router.bridgeToBase{value: bridgeCost}(amount);

        vm.stopBroadcast();
    }
}
