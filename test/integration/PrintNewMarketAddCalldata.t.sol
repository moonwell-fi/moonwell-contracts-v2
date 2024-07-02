// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ChainIds} from "@utils/ChainIds.sol";
import {Configs} from "@proposals/Configs.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {mip0x as mip} from "@proposals/mips/examples/mip-market-listing/mip-market-listing.sol";
import {TestProposals} from "@proposals/TestProposals.sol";

contract PrintNewMarketAddCalldataTest is Test {
    using ChainIds for uint256;
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
        proposals.testProposals(true, true, true, true, true, true, true, true); /// set debug to true, build, and run proposal
        addresses = proposals.addresses();

        proposals.printCalldata(
            0,
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            addresses.getAddress(
                "WORMHOLE_CORE_MOONBASE",
                block.chainid.toMoonbeamChainId()
            ) /// get moonbase wormhole address so proposal will work
        );

        proposals.printProposalActionSteps();
    }

    function testPrintNewMarketCalldataAlreadyDeployedMToken() public {
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
                "WORMHOLE_CORE_MOONBASE",
                block.chainid.toMoonbeamChainId()
            ) /// get moonbase wormhole address so proposal will work
        );
    }
}
