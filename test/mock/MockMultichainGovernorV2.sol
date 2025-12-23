pragma solidity 0.8.19;

import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {MultichainGovernorV2} from "@protocol/governance/multichain/MultichainGovernorV2.sol";

/// @notice Mock MultichainGovernorV2 for testing purposes
/// @dev Adds helper functions to expose internal state for testing
contract MockMultichainGovernorV2 is MultichainGovernorV2 {
    using EnumerableSet for EnumerableSet.UintSet;

    function newFeature() external pure returns (uint256) {
        return 1;
    }

    function proposalValid(uint256 proposalId) external view returns (bool) {
        return
            proposalCount >= proposalId &&
            proposalId > 0 &&
            proposals[proposalId].proposer != address(0);
    }

    function userHasProposal(
        uint256 proposalId,
        address proposer
    ) external view returns (bool) {
        return _userLiveProposals[proposer].contains(proposalId);
    }

    /// @notice Helper to check if calldata is whitelisted
    /// @param data The calldata to check
    function whitelistedCalldatas(
        bytes memory data
    ) external view returns (bool) {
        return _whitelistedCalldatas[data];
    }

    /// @notice Returns the number of live proposals for a user
    /// @param user The address to check
    function getUserLiveProposalCount(
        address user
    ) external view returns (uint256) {
        return _userLiveProposals[user].length();
    }
}
