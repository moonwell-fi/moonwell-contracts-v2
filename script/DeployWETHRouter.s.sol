// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {WETH9} from "@protocol/router/IWETH.sol";
import {WETHRouter} from "@protocol/router/WETHRouter.sol";

/*
How to use:
forge script src/proposals/DeployWETHRouter.s.sol:DeployWETHRouter \
    -vvvv \
    --rpc-url base \
    --broadcast
Remove --broadcast if you want to try locally first, without paying any gas.
*/

contract DeployWETHRouter is Script {
    function run() public {
        Addresses addresses = new Addresses();
        vm.startBroadcast();

        WETHRouter router = new WETHRouter(
            WETH9(addresses.getAddress("WETH")),
            MErc20(addresses.getAddress("MOONWELL_WETH"))
        );

        console.log("router address: ", address(router));

        vm.stopBroadcast();
    }
}
