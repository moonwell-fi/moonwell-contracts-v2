// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

contract ProposalView {
    address public immutable relayer;

    /// Uknown can be used to represent a non-existent proposal,
    /// or a proposal that has not been queued/executed yet.
    enum ProposalState {
        Unknown,
        Queued,
        Executed
    }

    mapping(uint256 proposalId => ProposalState state) public proposalStates;

    event ProposalStateChanged(uint256 indexed proposalId, ProposalState state);

    constructor(address _relayer) {
        relayer = _relayer;
    }

    /// @notice Function called by the relayer to notify a proposal state change.
    function updateProposalState(
        uint256 proposalId,
        ProposalState state
    ) external {
        require(
            msg.sender == relayer,
            "ProposalView: only relayer can update state"
        );

        proposalStates[proposalId] = state;

        emit ProposalStateChanged(proposalId, state);
    }
}
