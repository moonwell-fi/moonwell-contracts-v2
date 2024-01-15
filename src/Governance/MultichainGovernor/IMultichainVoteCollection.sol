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
        uint256 voteCollectionEndTime;
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
    function getVotingPower(address voter, uint256 blockNumber) external view returns (uint256);

    /// @dev emits the vote VAA for a given proposal
    function emitVoteVAA(uint256 proposalId) external;

    /// @dev emits the vote VAA for a given proposal
    function emitVoteVAA(uint256 proposalId) external;

    /// @notice Emits votes to be contabilized on MoomBeam Governor contract
    function emitVotes(uint256 proposalId) external; 

    /// @dev allows MultichainGovernor to create a proposal ID
    function createProposal(bytes memory VAA) external;
}
