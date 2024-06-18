// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {WethUnwrapper} from "@protocol/WethUnwrapper.sol";

/*
How to use:
forge script src/proposals/DeployWethUnwrapper.s.sol:DeployWethUnwrapper \
    -vvvv \
    --rpc-url base \
    --broadcast
Remove --broadcast if you want to try locally first, without paying any gas.
*/

contract DeployWethUnwrapper is Script {
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
        console.log("deployer address: ", vm.addr(PRIVATE_KEY));

        vm.startBroadcast(PRIVATE_KEY);

        WethUnwrapper unwrapper = new WethUnwrapper(
            addresses.getAddress("MOONWELL_WETH"),
            addresses.getAddress("WETH")
        );

        console.log(
            "successfully deployed WethUnwrapper at %s",
            address(unwrapper)
        );

        vm.stopBroadcast();
    }
}
