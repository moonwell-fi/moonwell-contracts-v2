// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import {WETH9} from "@protocol/router/IWETH.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {WETHRouter} from "@protocol/router/WETHRouter.sol";
import {mip00 as mip} from "@test/proposals/mips/mip00.sol";

/*
How to use:
forge script test/proposals/DeployWethRouter.s.sol:DeployWethRouter \
    -vvvv \
    --rpc-url base \
    --broadcast
Remove --broadcast if you want to try locally first, without paying any gas.
*/

contract DeployWethRouter is Script {
    uint256 public PRIVATE_KEY;
    Addresses addresses;

    function setUp() public {
        addresses = new Addresses();

        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = vm.envOr(
            "MOONWELL_DEPLOY_PK",
            77814517325470205911140941194401928579557062014761831930645393041380819009408
        );
    }

    function run() public {
        address deployerAddress = vm.addr(PRIVATE_KEY);

        vm.startBroadcast(PRIVATE_KEY);

        WETHRouter router = new WETHRouter(
            WETH9(addresses.getAddress("WETH")),
            MErc20(addresses.getAddress("MOONWELL_WETH"))
        );

        console.log("successfully deployed WETHRouter at %s", address(router));

        vm.stopBroadcast();
    }
}
