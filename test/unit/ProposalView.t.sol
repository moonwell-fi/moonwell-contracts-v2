// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ProposalView} from "@protocol/views/ProposalView.sol";

contract ProposalViewUnitTest is Test {
    event ProposalStateChanged(
        uint256 indexed proposalId,
        ProposalView.ProposalState state
    );

    ProposalView public proposalView;

    function setUp() public {
        proposalView = new ProposalView(address(this));
    }

    function testOnlyOwnerCanUpdateState() public {
        vm.startPrank(address(1));

        vm.expectRevert("ProposalView: only relayer can update state");
        proposalView.updateProposalState(1, ProposalView.ProposalState.Queued);
    }

    function testUpdateProposalStateQueued() public {
        proposalView.updateProposalState(1, ProposalView.ProposalState.Queued);
        assertEq(
            uint256(proposalView.proposalStates(1)),
            uint256(ProposalView.ProposalState.Queued)
        );
    }

    function testUpdateProposalStateExecuted() public {
        proposalView.updateProposalState(
            1,
            ProposalView.ProposalState.Executed
        );
        assertEq(
            uint256(proposalView.proposalStates(1)),
            uint256(ProposalView.ProposalState.Executed)
        );
    }

    function testUpdateProposalStateQueuedEmitsEvent() public {
        vm.expectEmit();
        emit ProposalStateChanged(1, ProposalView.ProposalState.Queued);
        proposalView.updateProposalState(1, ProposalView.ProposalState.Queued);
    }
}
