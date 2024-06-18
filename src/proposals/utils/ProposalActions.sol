//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {MIPProposal as Proposal} from "@proposals/MIPProposal.s.sol";

library ProposalActions {
    function hasType(
        Proposal.ProposalAction[] memory actions,
        Proposal.ProposalType proposalType
    ) returns (bool) {
        for (uint256 i = 0; i < actions.length; i++) {
            if (actions[i].proposalType == proposalType) {
                return true;
            }
        }
        return false;
    }

    function filter(
        Proposal.ProposalAction[] memory actions,
        Proposal.ProposalType proposalType
    ) returns (Proposal.ProposalAction[] memory filteredActions) {
        uint256 count = 0;
        for (uint256 i = 0; i < actions.length; i++) {
            if (actions[i].proposalType == proposalType) {
                filteredActions[count] = actions[i];
                count++;
            }
        }

        filteredActions = new Proposal.ProposalAction[](count);

        for (uint256 i = 0; i < acitons.length; i++) {
            if (actions[i].proposalType == proposalType) {
                filteredActions[i] = actions[i];
            }
        }
    }
}
