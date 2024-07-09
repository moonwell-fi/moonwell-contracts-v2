//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ProposalAction, ActionType} from "@proposals/proposalTypes/IProposal.sol";

library ProposalActions {
    /// @notice returns true if a proposal has a specific action type
    function hasType(
        ProposalAction[] storage actions,
        ActionType proposalType
    ) internal view returns (bool) {
        for (uint256 i = 0; i < actions.length; i++) {
            if (actions[i].actionType == proposalType) {
                return true;
            }
        }
        return false;
    }

    /// @notice filters the proposal actions by specified action type
    function filter(
        ProposalAction[] storage actions,
        ActionType proposalType
    ) internal view returns (ProposalAction[] memory filteredActions) {
        filteredActions = new ProposalAction[](
            proposalActionTypeCount(actions, proposalType)
        );
        uint256 index = 0;

        for (uint256 i = 0; i < actions.length; i++) {
            if (actions[i].actionType == proposalType) {
                filteredActions[index] = actions[i];
                index++;
            }
        }
    }

    /// @notice returns the total number of proposal action types in the
    /// proposal
    function proposalActionTypeCount(
        ProposalAction[] storage actions,
        ActionType actionType
    ) internal view returns (uint256 actionTypeCount) {
        for (uint256 i = 0; i < actions.length; i++) {
            if (actions[i].actionType == actionType) {
                actionTypeCount++;
            }
        }
    }
}
