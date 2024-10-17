// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {ITemporalGovernor} from "@protocol/governance/ITemporalGovernor.sol";

contract ProposalView {
    ITemporalGovernor public temporalGovernor;

    /// Uknown can be used to represent a non-existent proposal,
    /// or a proposal that has not been queued/executed yet.
    enum ProposalState {
        Unknown,
        Queued,
        Executed
    }

    mapping(uint256 proposalId => ProposalState state) public proposalStates;

    event ProposalStateChanged(uint256 indexed proposalId, ProposalState state);

    constructor(ITemporalGovernor _temporalGovernor) {
        temporalGovernor = _temporalGovernor;
    }

    /// @notice Function called by the relayer to notify a proposal state change.
    function updateProposalState(
        uint256 proposalId,
        ProposalState state,
        bytes memory VAA
    ) external {
        if (state == ProposalState.Queued) {
            temporalGovernor.queueProposal(VAA);
        } else if (state == ProposalState.Executed) {
            temporalGovernor.executeProposal(VAA);
        } else {
            revert("ProposalView: invalid state");
        }

        proposalStates[proposalId] = state;

        emit ProposalStateChanged(proposalId, state);
    }
}
