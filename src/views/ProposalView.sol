// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

contract ProposalView {
    address public relayer;

    constructor(address _relayer) {
        relayer = _relayer;
    }

    enum ProposalState {
        Queued,
        Executed
    }

    event ProposalStateChanged(uint256 indexed proposalId, ProposalState state);

    function emitEvent(uint256 proposalId, ProposalState state) external {
        emit ProposalStateChanged(proposalId, state);
    }
}
