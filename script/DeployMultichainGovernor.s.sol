// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";

import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/*
 Utility to deploy xWELL contract on any network

 to simulate:
     forge script script/DeployMultichainGovernor.s.sol:DeployMultichainGovernor -vvvv --rpc-url $chainAlias

 to run:
    forge script script/DeployMultichainGovernor.s.sol:DeployMultichainGovernor -vvvv \ 
    --rpc-url $chainAlias --broadcast --etherscan-api-key $chainAlias --verify
*/
contract DeployMultichainGovernor is Script {
    function run() public {
        vm.startBroadcast();

        MultichainGovernor impl = new MultichainGovernor();

        vm.stopBroadcast();

        Addresses addresses = new Addresses();
        addresses.addAddress("MULTICHAIN_GOVERNOR_PROXY_IMPL", address(impl));
        addresses.printAddresses();
    }
}
