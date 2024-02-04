// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ChainIds} from "@test/utils/ChainIds.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";
import {Well} from "@protocol/Governance/Well.sol";

/*
 Utility to deploy Well contract on a testnet
 to simulate:
     forge script script/DeployWell.s.sol:DeployWell -vvvv --rpc-url moonbase/baseGoerli

 to run:
    forge script script/DeployWell.s.sol:DeployWell -vvvv \ 
    --rpc-url moonbase/baseGoerli --broadcast --etherscan-api-key moonbase/baseGoerli --verify
*/
contract DeployWell is Script, ChainIds {
    /// @notice addresses contract
    Addresses addresses;

    /// @notice deployer private key
    uint256 private PRIVATE_KEY;

    constructor() {
        PRIVATE_KEY = uint256(vm.envBytes32("ETH_PRIVATE_KEY"));

        addresses = new Addresses();
    }

    function run() public {
        // get address from pk
        address owner = vm.addr(PRIVATE_KEY);

        vm.startBroadcast(PRIVATE_KEY);
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
            console.log('{\n        "addr": "%s", ', recordedAddresses[j]);
            console.log('        "chainId": %d,', block.chainid);
            console.log(
                '        "name": "%s"\n}%s',
                recordedNames[j],
                j < recordedNames.length - 1 ? "," : ""
            );
        }
    }
}
