pragma solidity 0.8.19;

/// @notice pauseable by the guardian
/// @notice upgradeable, constructor disables implementation
interface IMultichainVoteCollection {
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// ------------------------- EVENTS ------------------------ ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice An event emitted when a proposal is created
    /// @param proposalId the id of the proposal
    /// @param votingStartTime the timestamp when voting starts
    /// @param votingEndTime the timestamp when voting ends
    /// @param votingCollectionEndTime the timestamp when voting collection ends
    event ProposalCreated(
        uint256 proposalId,
        uint256 votingStartTime,
        uint256 votingEndTime,
        uint256 votingCollectionEndTime
    );

    /// @notice emitted when votes are emitted to the Moonbeam chain
    /// @param proposalId the proposal id
    /// @param forVotes number of votes for the proposal
    /// @param againstVotes number of votes against the proposal
    /// @param abstainVotes number of votes abstaining the proposal
    event VotesEmitted(
        uint256 proposalId,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 abstainVotes
    );

    /// @notice event emitted when a vote has been cast on a proposal
    /// @param voter the address of the voter
    /// @param proposalId the id of the proposal
    /// @param voteValue the value of the vote
    /// @param votes the number of votes cast
    event VoteCast(
        address voter,
        uint256 proposalId,
        uint8 voteValue,
        uint256 votes
    );

    /// @notice event emitted when the new staked well is set
    event NewStakedWellSet(address newStakedWell);

    /// @notice event emitted when the old staked well is unset
    event OldStakedWellUnset();

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// ----------------------- DATA TYPES ---------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

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

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// ----------------------- FUNCTIONS ----------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////
    //// --------------- PERMISSIONLESS --------------- ////
    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////

    /// @notice allows user to cast vote for a proposal
    /// @param proposalId the id of the proposal to vote on
    /// @param voteValue the value of the vote
    function castVote(uint256 proposalId, uint8 voteValue) external;

    /// @notice Emits votes to be contabilized on Moonbeam Governor contract
    /// @param proposalId the proposal id
    function emitVotes(uint256 proposalId) external payable;

    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////
    //// ------------------ VIEW ONLY ----------------- ////
    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////

    /// @notice returns a user's vote receipt on a given proposal
    /// @param proposalId the id of the proposal to check
    /// @param voter the address of the voter to check
    function getReceipt(
        uint256 proposalId,
        address voter
    ) external view returns (bool hasVoted, uint8 voteValue, uint256 votes);

    /// @notice returns information on a proposal
    /// @param proposalId the id of the proposal to check
    function proposalInformation(
        uint256 proposalId
    )
        external
        view
        returns (
            uint256 voteSnapshotTimestamp,
            uint256 votingStartTime,
            uint256 votingEndTime,
            uint256 crossChainVoteCollectionEndTimestamp,
            uint256 totalVotes,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 abstainVotes
        );

    /// @notice returns the vote counts for a proposal
    /// includes the total vote count, for, against and abstain votes
    /// @param proposalId the id of the proposal to check
    function proposalVotes(
        uint256 proposalId
    )
        external
        view
        returns (
            uint256 totalVotes,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 abstainVotes
        );

    /// @notice returns the total voting power for an address at a given block number and timestamp
    /// returns the sum of votes across both xWELL and stkWELL at the given timestamp
    /// @param account The address of the account to check
    /// @param timestamp The unix timestamp in seconds to check the balance at
    function getVotes(
        address account,
        uint256 timestamp
    ) external view returns (uint256);

    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////
    //// ----------------- ADMIN ONLY ----------------- ////
    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////

    /// @notice set a gas limit for the relayer on the external chain
    /// should only be called if there is a change in gas prices on the external chain
    /// @param newGasLimit new gas limit to set
    function setGasLimit(uint96 newGasLimit) external;
}
