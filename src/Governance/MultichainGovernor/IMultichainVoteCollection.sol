pragma solidity 0.8.19;

/// @notice pauseable by the guardian
/// @notice upgradeable, constructor disables implementation
interface IMultichainVoteCollection {
    struct MultichainProposal {
        /// @notice the timestamp at which users can begin voting
        uint256 votingStartTime;
        /// @notice The timestamp at which vote snapshots are taken at
        uint256 voteSnapshotTimestamp;
        /// @notice unix timestamp when voting will end
        uint256 votingEndTime;
        /// @notice unix timestamp when vote collection phase ends
        uint256 crossChainVoteCollectionEndTimestamp;
        /// @notice votes
        MultichainVotes votes;
        /// @notice Receipts of ballots for the entire set of voters
        mapping(address => Receipt) receipts;
        /// @notice votes has been emitted to Moonbeam Governor
        bool emitted;
    }

    /// @notice Ballot receipt record for a voter
    struct Receipt {
        /// @notice Whether or not a vote has been cast
        bool hasVoted;
        /// @notice The value of the vote.
        uint8 voteValue;
        /// @notice The number of votes the voter had, which were cast
        uint256 votes;
    }

    struct MultichainVotes {
        // @notice votes for the proposal
        uint256 forVotes;
        // @notice votes against the proposal
        uint256 againstVotes;
        // @notice votes that abstain
        uint256 abstainVotes;
        // @notice total votes
        uint256 totalVotes;
    }

    /// @notice allows user to cast vote for a proposal
    function castVote(uint256 proposalId, uint8 voteValue) external;

    /// @notice Returns the number of votes for a given user
    function getVotes(
        address account,
        uint256 timestamp
    ) external view returns (uint256);

    /// @notice Emits votes to be counted on Moonbeam Governor contract
    function emitVotes(uint256 proposalId) external payable;
}
