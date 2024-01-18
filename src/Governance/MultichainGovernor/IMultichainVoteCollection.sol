pragma solidity 0.8.19;

/// @notice pauseable by the guardian
/// @notice upgradeable, constructor disables implementation
interface IMultichainVoteCollection {
    struct MultichainProposal {
        // @notice unix timestamp when voting will start
        uint256 votingStartTime;
        // @notice unix timestamp when voting will end
        uint256 votingEndTime;
        // @notice unix timestamp when vote collection phase ends
        uint256 votingCollectionEndTime;
        // @notice votes
        MultichainVotes votes;
        // @notice votes has been emitted to Moonbeam Governor
        bool emitted;
    }

    struct MultichainVotes {
        // @notice votes for the proposal
        uint256 forVotes;
        // @notice votes against the proposal
        uint256 againstVotes;
        // @notice votes that abstain
        uint256 abstainVotes;
    }

    /// @dev allows user to cast vote for a proposal
    function castVote(uint256 proposalId, uint8 voteValue) external;

    /// @dev Returns the number of votes for a given user
    function getVotes(address account, uint256 timestamp) external view returns (uint256);

    /// @notice Emits votes to be contabilized on MoomBeam Governor contract
    function emitVotes(uint256 proposalId) external payable;
}
