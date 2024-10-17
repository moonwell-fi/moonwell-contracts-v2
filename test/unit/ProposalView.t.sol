// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Address} from "@utils/Address.sol";
import {ProposalView} from "@protocol/views/ProposalView.sol";
import {MockWormholeCore} from "@test/mock/MockWormholeCore.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {ITemporalGovernor} from "@protocol/governance/ITemporalGovernor.sol";

contract ProposalViewUnitTest is Test {
    using Address for address;

    event ProposalStateChanged(
        uint256 indexed proposalId,
        ProposalView.ProposalState state
    );

    ProposalView public proposalView;
    MockWormholeCore public mockCore;

    function setUp() public {
        uint16 trustedChainid = 10_000;
        address admin = address(100_000_000);

        ITemporalGovernor.TrustedSender[]
            memory trustedSenders = new ITemporalGovernor.TrustedSender[](1);
        trustedSenders[0] = ITemporalGovernor.TrustedSender({
            chainId: trustedChainid,
            addr: admin
        });

        mockCore = new MockWormholeCore();

        ITemporalGovernor temporalGovernor = new TemporalGovernor(
            address(mockCore),
            1 days,
            30 days,
            trustedSenders
        );

        address[] memory targets = new address[](1);
        targets[0] = address(temporalGovernor);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory payloads = new bytes[](1);

        payloads[0] = abi.encodeWithSignature( /// if issues use encode with selector
                "setTrustedSenders((uint16,address)[])",
                trustedSenders
            );

        /// to be unbundled by the temporal governor
        bytes memory payload = abi.encode(
            address(temporalGovernor),
            targets,
            values,
            payloads
        );

        mockCore.setStorage(
            true,
            trustedChainid,
            admin.toBytes(),
            "reason",
            payload
        );

        proposalView = new ProposalView(address(this), temporalGovernor);
    }

    function testOnlyOwnerCanUpdateState() public {
        vm.startPrank(address(1));

        vm.expectRevert("ProposalView: only relayer can update state");
        proposalView.updateProposalState(
            1,
            ProposalView.ProposalState.Queued,
            ""
        );
    }

    function testUpdateProposalStateQueued() public {
        proposalView.updateProposalState(
            1,
            ProposalView.ProposalState.Queued,
            ""
        );
        assertEq(
            uint256(proposalView.proposalStates(1)),
            uint256(ProposalView.ProposalState.Queued)
        );
    }

    function testUpdateProposalStateExecuted() public {
        testUpdateProposalStateQueued();

        vm.warp(2 days);

        proposalView.updateProposalState(
            1,
            ProposalView.ProposalState.Executed,
            ""
        );
        assertEq(
            uint256(proposalView.proposalStates(1)),
            uint256(ProposalView.ProposalState.Executed)
        );
    }

    function testUpdateProposalStateQueuedEmitsEvent() public {
        vm.expectEmit();
        emit ProposalStateChanged(1, ProposalView.ProposalState.Queued);
        proposalView.updateProposalState(
            1,
            ProposalView.ProposalState.Queued,
            ""
        );
    }

    function testRevertInvalidState() public {
        vm.expectRevert("ProposalView: invalid state");
        proposalView.updateProposalState(
            1,
            ProposalView.ProposalState.Unknown,
            ""
        );
    }
}
