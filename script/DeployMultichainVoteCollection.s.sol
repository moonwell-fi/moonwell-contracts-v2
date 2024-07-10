// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import {printAddresses} from "@proposals/utils/ProposalPrinting.sol";
import {MultichainVoteCollection} from "@protocol/governance/multichain/MultichainVoteCollection.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/*
 Utility to deploy xWELL contract on any network

 to simulate:
     forge script script/DeployMultichainVoteCollection.s.sol:DeployMultichainVoteCollection -vvvv --rpc-url base/baseSepolia

 to run:
    forge script script/DeployMultichainVoteCollection.s.sol:DeployMultichainVoteCollection -vvvv \ 
    --rpc-url base/baseSepolia --broadcast --etherscan-api-key moonbase --verify
*/
contract DeployMultichainVoteCollection is Script {
    function run() public {
        vm.startBroadcast();

        MultichainVoteCollection impl = new MultichainVoteCollection();

        vm.stopBroadcast();

        Addresses addresses = new Addresses();
        addresses.addAddress("NEW_VOTE_COLLECTION_IMPL", address(impl));
        printAddresses(addresses);
    }
}
