// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Proposal} from "@test/proposals/proposalTypes/Proposal.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {TestProposals} from "@test/proposals/TestProposals.sol";
import {Configs} from "@test/proposals/Configs.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {TemporalGovernor} from "@protocol/core/Governance/TemporalGovernor.sol";

/// validate the deployment on sepolia testnet
contract InitProposalSucceedsTest is Test, ChainIds {
    TestProposals proposals;
    Addresses addresses;

    function setUp() public {
        proposals = new TestProposals();
        proposals.setUp();
        proposals.setDebug(true);
        addresses = proposals.addresses();

        console.log("chainid: ", block.chainid);
    }

    function testInitProposalSucceeds() public {
        Configs(address(proposals.proposals(0))).init(addresses); /// init configs
        Configs(address(proposals.proposals(0))).initEmissions(
            addresses,
            0xc191A4db4E05e478778eDB6a201cb7F13A257C23
        ); /// init configs
        proposals.testProposals(
            true,
            false,
            false,
            false,
            true,
            true,
            false,
            false
        );
        proposals.printCalldata(
            0,
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            addresses.getAddress(
                "WORMHOLE_CORE",
                sendingChainIdToReceivingChainId[block.chainid]
            )
        ); /// print calldata out
    }

    function testAfterCrosschainProposalValidateSucceeds() public {
        Configs(address(proposals.proposals(0))).init(addresses); /// init configs
        Configs(address(proposals.proposals(0))).initEmissions(
            addresses,
            0xc191A4db4E05e478778eDB6a201cb7F13A257C23
        ); /// init configs
        proposals.testProposals(
            true,
            false,
            false,
            false,
            false,
            false,
            false,
            true
        );
    }

    function testDeployAfterDeployBuildRunValidateProposalSucceeds() public {
        proposals.testProposals(true, true, true, true, true, true, false, true);
    }

    function testValidateSucceeds() public {
        testInitProposalSucceeds();

        /// validate mip 00 after gov proposal succeeds
        /// moonbeam timelock corresponds to EOA owner on sepolia testnet
        proposals.proposals(0).validate(
            addresses,
            addresses.getAddress("MOONBEAM_TIMELOCK")
        );
    }

    function testBuildProcessRequestSucceeds() public view {
        console.log("queueProposal: ");
        console.logBytes(
            abi.encodePacked(TemporalGovernor.queueProposal.selector)
        );

        console.log("executeProposal: ");
        console.logBytes(
            abi.encodePacked(TemporalGovernor.executeProposal.selector)
        );
    }
}
