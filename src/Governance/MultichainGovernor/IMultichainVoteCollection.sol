pragma solidity 0.8.19;

/// @notice pauseable by the guardian
/// @notice upgradeable, constructor disables implementation
interface IMultichainVoteCollection {
    struct MultichainProposal {
        // unix timestamp when voting will start
        uint256 votingStartTime;
        // unix timestamp when voting will end
        uint256 votingEndTime;
        // unix timestamp when vote collection phase ends
        uint256 votingCollectionEndTime;
        // votes 
        MultichainVotes votes;
    }

    struct MultichainVotes {
        // votes for the proposal
        uint256 forVotes;
        // votes against the proposal
        uint256 againstVotes;
        // votes that abstain
        uint256 abstainVotes;
    }

    /// @dev allows user to cast vote for a proposal
    function castVote(uint256 proposalId, uint8 voteValue) external;

    /// @dev Returns the number of votes for a given user
    function getVotes(address account, uint256 timestamp) external view returns (uint256);

    /// @notice Emits votes to be contabilized on MoomBeam Governor contract
    function emitVotes(uint256 proposalId) external payable;
}
