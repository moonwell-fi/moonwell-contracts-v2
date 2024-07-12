// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/*
 Utility to deploy xWELL contract on a testnet
 to simulate:
     forge script script/DeployxWellLogic.s.sol:DeployxWellLogic -vvvv --rpc-url moonbeam
     forge script script/DeployxWellLogic.s.sol:DeployxWellLogic -vvvv --rpc-url base

 to run:
    forge script script/DeployxWellLogic.s.sol:DeployxWellLogic -vvvv \ 
    --rpc-url moonbase/baseGoerli --broadcast --etherscan-api-key moonbase --verify
*/
contract DeployxWellLogic is Script {
    function run() public returns (xWELL) {
        vm.startBroadcast();

        xWELL well = new xWELL();

        vm.stopBroadcast();

        return well;
    }
}
