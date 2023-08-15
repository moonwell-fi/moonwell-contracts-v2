// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "@forge-std/Test.sol";

import {Well} from "@protocol/Governance/deprecated/Well.sol";
import {mipb01} from "@test/proposals/mips/mip-b01/mip-b01.sol";
import {Configs} from "@test/proposals/Configs.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {MockWormhole} from "@test/mock/MockWormhole.sol";
import {TestProposals} from "@test/proposals/TestProposals.sol";
import {TestProposals2} from "@test/proposals/TestProposals2.sol";
import {CrossChainProposal} from "@test/proposals/proposalTypes/CrossChainProposal.sol";
import {MoonwellArtemisGovernor} from "@protocol/Governance/deprecated/MoonwellArtemisGovernor.sol";

contract PrintCalldataTest is Test, ChainIds {
    TestProposals proposals;
    TestProposals2 proposals2;
    Addresses addresses;
    Addresses addresses2;

    function setUp() public {
        mipb01 mip = new mipb01();
        address[] memory mips = new address[](1);
        mips[0] = address(mip);

        proposals2 = new TestProposals2(mips);
        proposals2.setUp();

        // Run all pending proposals before doing e2e tests
        proposals = new TestProposals();

        proposals.setUp();
        addresses = proposals.addresses();
    }

    function testPrintCalldata() public {
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
            false,
            false,
            false
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

    function testPrintCalldatamipb01() public {
        proposals2.testProposals(
            false,
            false,
            false,
            false,
            true,
            true,
            false,
            true
        ); /// set debug to true, build, run and validate proposal
        addresses2 = proposals2.addresses();

        proposals2.printCalldata(
            0,
            addresses2.getAddress("TEMPORAL_GOVERNOR"),
            addresses2.getAddress(
                "WORMHOLE_CORE",
                sendingChainIdToReceivingChainId[block.chainid]
            ) /// get moonbase wormhole address so proposal will work
        );
    }
}
