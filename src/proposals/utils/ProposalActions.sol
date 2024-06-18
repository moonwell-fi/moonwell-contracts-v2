//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {MIPProposal as Proposal} from "@proposals/MIPProposal.s.sol";

library ProposalActions {
    function hasType(
        Proposal.ProposalAction[] memory actions,
        Proposal.ProposalType proposalType
    ) {
        for (uint256 i = 0; i < actions.length; i++) {
            if (actions[i].proposalType == proposalType) {
                return true;
            }
        }
        return false;
    }
}
