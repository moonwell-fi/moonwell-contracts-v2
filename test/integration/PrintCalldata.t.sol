// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "@forge-std/Test.sol";

import {Well} from "@protocol/Governance/deprecated/Well.sol";
import {mipb02} from "@proposals/mips/mip-b02/mip-b02.sol";
import {Configs} from "@proposals/Configs.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {MockWormhole} from "@test/mock/MockWormhole.sol";
import {TestProposals} from "@proposals/TestProposals.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {MoonwellArtemisGovernor} from "@protocol/Governance/deprecated/MoonwellArtemisGovernor.sol";

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
