// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// test commands:
///
///      forge script DeployMultiRewards -vvv --fork-url base
///
///      forge script DeployMultiRewards -vvv --fork-url optimism
///
contract DeployMultiRewards is Script {
    function run() public {
        Addresses addresses = new Addresses();

        vm.startBroadcast();

        address multiRewards = deployCode(
            "artifacts/foundry/MultiRewards.sol/MultiRewards.json",
            abi.encode(
                addresses.getAddress("TEMPORAL_GOVERNOR"),
                addresses.getAddress("USDC_METAMORPHO_VAULT")
            )
        );

        vm.stopBroadcast();

        addresses.addAddress("MULTI_REWARDS", multiRewards);
        addresses.printAddresses();
    }
}
