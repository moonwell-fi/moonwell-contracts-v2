// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Configs} from "@test/proposals/Configs.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {mip0x as mip} from "@test/proposals/mips/examples/mip-market-listing/mip-market-listing.sol";
import {TestProposals} from "@test/proposals/TestProposals.sol";

contract PrintNewMarketAddCalldataTest is Test, ChainIds {
    TestProposals proposals;
    Addresses addresses;

    function setUp() public {
        address[] memory mips = new address[](1);
        mips[0] = address(new mip());

        proposals = new TestProposals(mips);
        proposals.setUp();
        addresses = proposals.addresses();
    }

    function testPrintNewMarketCalldataDeployMToken() public {
        proposals.testProposals(
            true,
            true,
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
    }

    function testPrintNewMarketCalldataAlreadyDeployedMToken() public {
        proposals.testProposals(
            true,
            false,
            false,
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
    }
}
