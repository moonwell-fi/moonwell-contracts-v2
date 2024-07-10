// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/*

 Utility to deploy xWELL contract on any network

 to simulate:
     forge script script/DeployXWell.s.sol:DeployXWell -vvvv --rpc-url chainAlias

 to run:
    forge script script/DeployXWell.s.sol:DeployXWell -vvvv \ 
    --rpc-url chainAlias --broadcast --etherscan-api-key chainAlias --verify

*/
contract DeployXWell is Script {
    function run() public {
        vm.startBroadcast();

        xWELL well = new xWELL();

        vm.stopBroadcast();

        Addresses addresses = new Addresses();
        addresses.addAddress("NEW_XWELL_IMPL", address(well));

        addresses.printAddresses();
    }
}
