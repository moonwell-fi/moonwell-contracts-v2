pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {xWELLRouter} from "@protocol/xWELL/xWELLRouter.sol";

/*
 to simulate:
  moonbeam:
     forge script script/DeployXWellRouter.s.sol:DeployXWellRouter \
     \ -vvvvv --rpc-url moonbeam

  to run:
    forge script script/DeployXWellRouter.s.sol:DeployXWellRouter \
     \ -vvvvv --rpc-url moonbeam --broadcast --etherscan-api-key moonbeam --verify
*/
contract DeployXWellRouter is Script, Test {
    /// @notice addresses contract
    Addresses addresses;

    constructor() {
        addresses = new Addresses();
    }

    function run() public returns (xWELLRouter router) {
        vm.startBroadcast();

        router = new xWELLRouter(
            addresses.getAddress("xWELL_PROXY"),
            addresses.getAddress("GOVTOKEN"),
            addresses.getAddress("xWELL_LOCKBOX"),
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        vm.stopBroadcast();
    }
}
