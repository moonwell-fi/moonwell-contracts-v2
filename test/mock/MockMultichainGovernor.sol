pragma solidity 0.8.19;

import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";

contract MockMultichainGovernor is MultichainGovernor {
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

    /// @notice returns information on a proposal in a struct format
    /// @param proposalId the id of the proposal to check
    function proposalInformationStruct(
        uint256 proposalId
    ) external view returns (ProposalInformation memory proposalInfo) {
        Proposal storage proposal = proposals[proposalId];

        proposalInfo.proposer = proposal.proposer;
        proposalInfo.voteSnapshotTimestamp = proposal.voteSnapshotTimestamp;
        proposalInfo.votingStartTime = proposal.votingStartTime;
        proposalInfo.votingEndTime = proposal.votingEndTime;
        proposalInfo.crossChainVoteCollectionEndTimestamp = proposal
            .crossChainVoteCollectionEndTimestamp;
        proposalInfo.totalVotes = proposal.totalVotes;
        proposalInfo.forVotes = proposal.forVotes;
        proposalInfo.againstVotes = proposal.againstVotes;
        proposalInfo.abstainVotes = proposal.abstainVotes;
    }
}
