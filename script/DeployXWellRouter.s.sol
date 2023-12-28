pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";
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

    /// @notice deployer private key
    uint256 private PRIVATE_KEY;

    constructor() {
        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = vm.envOr(
            "ETH_PRIVATE_KEY",
            77814517325470205911140941194401928579557062014761831930645393041380819009408
        );

        addresses = new Addresses();
    }

    function run() public returns (xWELLRouter router) {
        router = new xWELLRouter(
            addresses.getAddress("xWELL_PROXY"),
            addresses.getAddress("WELL"),
            addresses.getAddress("xWELL_LOCKBOX"),
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
    }
}
