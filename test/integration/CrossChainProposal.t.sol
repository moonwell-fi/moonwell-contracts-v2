// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "@forge-std/Test.sol";

import {Well} from "@protocol/core/Governance/deprecated/Well.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Timelock} from "@protocol/core/Governance/deprecated/Timelock.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {MockWormhole} from "@test/mock/MockWormhole.sol";
import {TestProposals} from "@test/proposals/TestProposals.sol";
import {CrossChainProposal} from "@test/proposals/proposalTypes/CrossChainProposal.sol";
import {MoonwellArtemisGovernor} from "@protocol/core/Governance/deprecated/MoonwellArtemisGovernor.sol";

contract CrossChainProposalUnitTest is Test, ChainIds {
    MoonwellArtemisGovernor governor;
    MockWormhole wormhole;
    TestProposals proposals;
    Addresses addresses;
    Timelock timelock;
    Well well;

    function setUp() public {
        wormhole = new MockWormhole();
        well = new Well(address(this));
        timelock = new Timelock(address(this), 1 minutes);
        governor = new MoonwellArtemisGovernor(
            address(timelock), // timelock
            address(well), // gov token (for voting power)
            address(well), // gov token (for voting power)
            address(well), // gov token (for voting power)
            address(this), // break glass guardian
            address(this), // governance return address
            address(this), // governance return guardian
            1 days // guardian sunset
        );

        vm.prank(address(timelock));
        timelock.setPendingAdmin(address(governor));

        // Run all pending proposals before doing e2e tests
        proposals = new TestProposals();
        proposals.setUp();
        proposals.setDebug(false);
        proposals.testProposals(true, true, true, true, true, false, true);
        addresses = proposals.addresses();

        vm.roll(block.number + 1);
        well.delegate(address(this));
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }

    function testGovernorAcceptsAdmin() public {
        governor.__acceptAdminOnTimelock();

        assertEq(timelock.admin(), address(governor));
        assertEq(address(governor.timelock()), address(timelock));
    }

    function testQueueAndPublishMessageRawBytes() public {
        testGovernorAcceptsAdmin();

        bytes memory payload = CrossChainProposal(
            address(proposals.proposals(0))
        ).getArtemisGovernorCalldata(
                addresses.getAddress("TEMPORAL_GOVERNOR"), /// temporal governor is the ultimate target on the other chain
                address(wormhole)
            );

        (bool success, bytes memory errorString) = address(governor).call(
            payload
        );

        require(success, string(errorString));

        // address[] memory targets = new address[](1);
        // targest[0] = address(wormhole);

        // uint256[] memory values = new uint256[](1); /// 0

        // string[] memory signatures = new string[](1);
        // signatures[0] = "publishMessage(uint32,bytes,uint8)";

        // bytes[] memory calldatas = new bytes[](1);
        // calldatas[0] = payload;

        // string memory description = new string[](1);
        // description[0] = "publish message to wormhole";
    }

    function testQueueAndPublishMessage() public {
        testGovernorAcceptsAdmin();

        address[] memory targets = new address[](1);
        targets[0] = address(wormhole);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        /// bytes to call the Wormhole Core with
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = CrossChainProposal(address(proposals.proposals(0)))
            .getTemporalGovCalldata(addresses.getAddress("TEMPORAL_GOVERNOR"));

        console.log("cross chain gov payload");
        emit log_bytes(payloads[0]);

        console.log("propose artemis gov payload");
        emit log_bytes(
            CrossChainProposal(address(proposals.proposals(0)))
                .getArtemisGovernorCalldata(
                    addresses.getAddress("TEMPORAL_GOVERNOR"),
                    addresses.getAddress(
                        "WORMHOLE_CORE",
                        sendingChainIdToReceivingChainId[block.chainid]
                    ) /// call wormhole core on moonbeam
                )
        );

        string[] memory signatures = new string[](1);
        signatures[0] = ""; /// signature is already in payload

        vm.warp(100);

        uint256 proposalId = governor.propose(
            targets,
            values,
            signatures,
            payloads,
            "Cross chain governance proposal"
        );

        vm.warp(governor.votingDelay() + block.timestamp + 1); /// now active

        governor.castVote(proposalId, 0); /// VOTE YES

        vm.warp(governor.votingPeriod() + block.timestamp + 1);
        governor.queue(proposalId);

        vm.warp(block.timestamp + timelock.delay() + 1); /// finish timelock

        governor.execute(proposalId);

        assertEq(
            CrossChainProposal(address(proposals.proposals(0))).nonce(),
            wormhole.lastNonce()
        );
        assertEq(
            CrossChainProposal(address(proposals.proposals(0)))
                .consistencyLevel(),
            wormhole.lastConsistencyLevel()
        );
        assertEq(
            keccak256(payloads[0]),
            keccak256(
                abi.encodeWithSignature(
                    "publishMessage(uint32,bytes,uint8)",
                    wormhole.lastNonce(),
                    wormhole.lastPayload(),
                    wormhole.lastConsistencyLevel()
                )
            )
        );
    }
}
