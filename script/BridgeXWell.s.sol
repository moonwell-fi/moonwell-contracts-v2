pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {xWELLRouter} from "@protocol/xWELL/xWELLRouter.sol";

contract BridgeXWell is Script, Test {
    /// @notice addresses contract
    Addresses addresses;

    /// @notice deployer private key
    uint256 private PRIVATE_KEY;

    constructor() {
        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = uint256(vm.envBytes32("ETH_PRIVATE_KEY"));

        addresses = new Addresses();
    }

    function run() public {
        xWELLRouter router = xWELLRouter(addresses.getAddress("xWELL_ROUTER"));

        uint256 bridgeCost = router.bridgeCost();

        uint256 amount = 100_000 * 1e18;

        vm.startBroadcast(PRIVATE_KEY);

        router.bridgeToBase{value: bridgeCost}(amount);

        vm.stopBroadcast();
    }
}
