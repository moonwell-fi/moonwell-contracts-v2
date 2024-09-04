// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import {WethUnwrapper} from "@protocol/WethUnwrapper.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/*
How to use:
forge script script/DeployWethUnwrapper.s.sol:DeployWethUnwrapper \
    -vvvv \
    --rpc-url base \
    --broadcast
Remove --broadcast if you want to try locally first, without paying any gas.
*/

contract DeployWethUnwrapper is Script {
    Addresses addresses;

    function setUp() public {
        addresses = new Addresses();
    }

    function run() public {
        vm.startBroadcast();

        WethUnwrapper unwrapper = new WethUnwrapper(
            addresses.getAddress("WETH")
        );

        console.log(
            "successfully deployed WethUnwrapper at %s",
            address(unwrapper)
        );

        vm.stopBroadcast();
    }
}
