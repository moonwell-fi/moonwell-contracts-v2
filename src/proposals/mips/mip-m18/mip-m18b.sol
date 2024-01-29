//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ChainIds} from "@test/utils/ChainIds.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";

/// Proposal to run on Base to create the Multichain Vote Collection Contract
contract mipm18b is HybridProposal, MultichainGovernorDeploy, ChainIds {
    string public constant name = "MIP-M18B";

    constructor() {
        // bytes memory proposalDescription = abi.encodePacked(
        //     vm.readFile("./src/proposals/mips/mip-m18/MIP-M18.md")
        // );
        // _setProposalDescription(proposalDescription);
    }

    function deploy(Addresses addresses, address) public override {
        /// TODO check on these parameters, change `deployStakedWell` function to make temporal gov owner
        /// TODO should pass in the proxy admin here
        /// TODO should receive back both an impl, and a proxy
        address stkWellProxy = address(
            deployStakedWell(addresses.getAddress("xWELL_PROXY"))
        );

        address proxyAdmin = addresses.getAddress("PROXY_ADMIN");
        (
            address collectionProxy,
            address collectionImpl
        ) = deployVoteCollection(
                addresses.getAddress("xWELL_PROXY"),
                stkWellProxy,
                addresses.getAddress( /// fetch multichain governor address on Moonbeam
                    "MULTICHAIN_GOVERNOR_PROXY",
                    sendingChainIdToReceivingChainId[block.chainid]
                ),
                addresses.getAddress("WORMHOLE_BRIDGE_RELAYER"),
                chainIdToWormHoleId[block.chainid],
                proxyAdmin,
                addresses.getAddress("TEMPORAL_GOVERNOR_OWNER")
            );

        addresses.addAddress("VOTE_COLLECTION_PROXY", collectionProxy);
        addresses.addAddress("VOTE_COLLECTION_IMPL", collectionImpl);
        addresses.addAddress("stkWELL_PROXY", stkWellProxy);
        addresses.addAddress("stkWELL_IMPL", address(0));
    }

    function afterDeploy(Addresses addresses, address) public override {}

    function afterDeploySetup(Addresses addresses) public override {}

    function build(Addresses addresses) public override {}

    function teardown(Addresses addresses, address) public pure override {}

    function run(Addresses addresses, address) public override {}

    function validate(Addresses addresses, address) public override {
        /// TODO validate that pending owners have been set where appropriate
        /// TODO validate that new admin/owner has been set where appropriate
    }
}
