// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "@forge-std/Test.sol";

import {Well} from "@protocol/core/Governance/deprecated/Well.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {MockWormhole} from "@test/mock/MockWormhole.sol";
import {TestProposals} from "@test/proposals/TestProposals.sol";
import {CrossChainProposal} from "@test/proposals/proposalTypes/CrossChainProposal.sol";
import {MoonwellArtemisGovernor} from "@protocol/core/Governance/deprecated/MoonwellArtemisGovernor.sol";

contract PrintCalldataTest is Test, ChainIds {
    TestProposals proposals;
    Addresses addresses;

    function setUp() public {
        // Run all pending proposals before doing e2e tests
        proposals = new TestProposals();
        proposals.setUp();
        proposals.setDebug(false);
    }
    
    function testPrintCalldata() public {
        proposals.testProposals(true, false, false, true, true, false, false); /// set debug to true, build, and run proposal
        addresses = proposals.addresses();

        proposals.printCalldata(
            0,
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            addresses.getAddress("WORMHOLE_CORE", sendingChainIdToReceivingChainId[block.chainid]) /// get moonbase wormhole address so proposal will work
        );
    }
}
