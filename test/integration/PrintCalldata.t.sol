// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {mipb02} from "@proposals/mips/mip-b02/mip-b02.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {TestProposals} from "@proposals/TestProposals.sol";

contract PrintCalldataTest is Test, ChainIds {
    TestProposals proposals;
    Addresses addresses;

    function setUp() public {
        mipb02 mip = new mipb02();
        address[] memory mips = new address[](1);
        mips[0] = address(mip);

        proposals = new TestProposals(mips);
        proposals.setUp();
        addresses = proposals.addresses();
    }

    function testPrintCalldata() public {
        proposals.testProposals(
            true,
            false,
            true,
            true,
            true,
            true,
            true,
            true
        ); /// set debug to true, build, and run proposal
        addresses = proposals.addresses();

        proposals.printCalldata(
            0,
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            addresses.getAddress(
                "WORMHOLE_CORE",
                sendingChainIdToReceivingChainId[block.chainid]
            ) /// get moonbase wormhole address so proposal will work
        );

        proposals.printProposalActionSteps(); /// pretty print proposal action steps
    }
}
