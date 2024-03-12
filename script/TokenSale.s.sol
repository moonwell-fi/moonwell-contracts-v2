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
        PRIVATE_KEY = uint256(vm.envBytes32("ETH_PRIVATE_KEY"));

        addresses = new Addresses();
    }

    function run() public returns (xWELLRouter router) {
        vm.startBroadcast(PRIVATE_KEY);

        router = new xWELLRouter(
            addresses.getAddress("xWELL_PROXY"),
            addresses.getAddress("WELL"),
            addresses.getAddress("xWELL_LOCKBOX"),
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        vm.stopBroadcast();
    }
}
