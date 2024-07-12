// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";

import {MultichainVoteCollection} from "@protocol/governance/multichain/MultichainVoteCollection.sol";

/*
 Utility to deploy xWELL contract on any network

 to simulate:
     forge script script/DeployMultichainVoteCollection.s.sol:DeployMultichainVoteCollection -vvvv --rpc-url $chainAlias

 to run:
    forge script script/DeployMultichainVoteCollection.s.sol:DeployMultichainVoteCollection -vvvv \ 
    --rpc-url $chainAlias --broadcast --etherscan-api-key $chainAlias --verify
*/
contract DeployMultichainVoteCollection is Script {
    function run() public returns (MultichainVoteCollection) {
        vm.startBroadcast();

        MultichainVoteCollection impl = new MultichainVoteCollection();

        vm.stopBroadcast();

        return impl;
    }
}
