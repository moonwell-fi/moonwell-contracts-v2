// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import {Well} from "@protocol/governance/Well.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/*
 Utility to deploy Well contract on a testnet
 to simulate:
     forge script script/DeployWell.s.sol:DeployWell -vvvv --rpc-url moonbase
 to run:
    forge script script/DeployWell.s.sol:DeployWell -vvvv \ 
    --rpc-url moonbase/baseGoerli --broadcast --etherscan-api-key moonbase --verify
*/
contract DeployWell is Script {
    function run() public {
        Addresses addresses = new Addresses();
        vm.startBroadcast();

        (, address owner, ) = vm.readCallers();

        Well well = new Well(owner);

        vm.stopBroadcast();

        addresses.addAddress("WELL", address(well));

        addresses.printAddresses();
    }
}
