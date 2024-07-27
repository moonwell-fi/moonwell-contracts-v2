// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";

import {MultichainVoteCollection} from "@protocol/governance/multichain/MultichainVoteCollection.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/*
 Utility to deploy xWELL contract on any network

 to simulate:
     forge script script/DeployMultichainVoteCollectionLogic.s.sol:DeployMultichainVoteCollectionLogic -vvvv --rpc-url $chainAlias

 to run:
    forge script script/DeployMultichainVoteCollectionLogic.s.sol:DeployMultichainVoteCollectionLogic -vvvv \ 
    --rpc-url $chainAlias --broadcast --etherscan-api-key $chainAlias --verify
*/
contract DeployMultichainVoteCollectionLogic is Script {
    function run() public {
        vm.startBroadcast();

        new MultichainVoteCollection();

        vm.stopBroadcast();
    }
}
