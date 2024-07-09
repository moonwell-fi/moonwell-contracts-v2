// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";
import {Well} from "@protocol/governance/Well.sol";

/*
 Utility to deploy Well contract on a testnet
 to simulate:
     forge script script/DeployWell.s.sol:DeployWell -vvvv --rpc-url moonbase
 to run:
    forge script script/DeployWell.s.sol:DeployWell -vvvv \ 
    --rpc-url moonbase/baseGoerli --broadcast --etherscan-api-key moonbase --verify
*/
contract DeployWell is Script {
    Addresses addresses;

    constructor() {
        addresses = new Addresses();
    }

    function run() public {
        vm.startBroadcast();

        (, address owner, ) = vm.readCallers();

        Well well = new Well(owner);

        vm.stopBroadcast();

        addresses.addAddress("WELL", address(well));

        printAddresses();
    }

    function printAddresses() private view {
        (
            string[] memory recordedNames,
            ,
            address[] memory recordedAddresses
        ) = addresses.getRecordedAddresses();
        for (uint256 j = 0; j < recordedNames.length; j++) {
            console.log("{\n        'addr': '%s', ", recordedAddresses[j]);
            console.log("        'chainId': %d,", block.chainid);
            console.log(
                "        'name': '%s'\n}%s",
                recordedNames[j],
                j < recordedNames.length - 1 ? "," : ""
            );
        }
    }
}
