// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";

import "@utils/ChainIds.sol";

import {MultichainVoteCollection} from "@protocol/governance/multichain/MultichainVoteCollection.sol";
import {MultichainGovernorDeploy} from "@protocol/governance/multichain/MultichainGovernorDeploy.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/*
 Utility to deploy xWELL contract on any network

 to simulate:
     forge script script/DeployMultichainVoteCollection.s.sol:DeployMultichainVoteCollection -vvvv --rpc-url $chainAlias

 to run:
    forge script script/DeployMultichainVoteCollection.s.sol:DeployMultichainVoteCollection -vvvv \ 
    --rpc-url $chainAlias --broadcast --etherscan-api-key $chainAlias --verify
*/
contract DeployMultichainVoteCollection is Script, MultichainGovernorDeploy {
    using ChainIds for uint256;

    function run() public {
        Addresses addresses = new Addresses();

        vm.startBroadcast();

        (
            address collectionProxy,
            address collectionImpl
        ) = deployVoteCollection(
                addresses.getAddress("xWELL_PROXY"),
                addresses.getAddress("STK_GOVTOKEN_PROXY"),
                addresses.getAddress(
                    "MULTICHAIN_GOVERNOR_PROXY",
                    block.chainid.toMoonbeamChainId()
                ),
                addresses.getAddress("WORMHOLE_BRIDGE_RELAYER_PROXY"),
                block.chainid.toMoonbeamWormholeChainId(),
                addresses.getAddress("MRD_PROXY_ADMIN"),
                addresses.getAddress("TEMPORAL_GOVERNOR")
            );

        addresses.addAddress("VOTE_COLLECTION_PROXY", collectionProxy);
        addresses.addAddress("VOTE_COLLECTION_IMPL", collectionImpl);

        vm.stopBroadcast();

        addresses.printAddresses();
    }
}
