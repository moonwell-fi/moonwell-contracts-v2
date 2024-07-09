pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {xWELLRouter} from "@protocol/xWELL/xWELLRouter.sol";
import {BASE_WORMHOLE_CHAIN_ID} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract BridgeXWell is Script, Test {
    /// @notice addresses contract
    Addresses addresses;

    constructor() {
        addresses = new Addresses();
    }

    function run() public {
        xWELLRouter router = xWELLRouter(addresses.getAddress("xWELL_ROUTER"));

        uint256 bridgeCost = router.bridgeCost(BASE_WORMHOLE_CHAIN_ID);

        uint256 amount = 100_000 * 1e18;

        vm.startBroadcast();

        router.bridgeToSender{value: bridgeCost}(
            amount,
            BASE_WORMHOLE_CHAIN_ID
        );

        vm.stopBroadcast();
    }
}
