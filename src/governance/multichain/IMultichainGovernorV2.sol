// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";

/// @notice pauseable by the guardian
/// @notice upgradeable, constructor disables implementation
interface IMultichainGovernorV2 {
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// ------------------------- ERRORS ------------------------ ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    error ZeroAddress();
    error InvalidProposalId();
    error InvalidProposalState(ProposalState current, ProposalState required);
    error EmptyDescriptionUri();
    error TooManyLiveProposals();
    error ProposalAlreadyFinalized();
    error OnlyProposer();
    error ProposalExpired();
    error UnauthorizedCancel();
    error InvalidVoteValue();
    error AlreadyVoted();
    error NoVotingPower();
    error GasLimitTooLow();
    error ArityMismatch();
    error EmptyArray();
    error CalldataNotWhitelisted();
    error BreakGlassGuardianNotNull();
    error CalldataAlreadyApproved();
    error CalldataNotApproved();
    error InvalidVoteCollectionPeriod();
    error InvalidQuorum();
    error VotingPeriodOutOfBounds();
    error ProposalThresholdOutOfBounds();
    error ProposalRemovalFailed(bool isGlobalProposal);
    error InvalidPayloadLength();
    error VoteAlreadyCollected();
    error OnlyGovernor();
    error OnlyBreakGlassGuardian();
    error VotesBelowProposalThreshold();
    error ExecuteCallFailed();
    error BreakGlassCallFailed();
    error CallToNonContract();

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// ------------------------- EVENTS ------------------------ ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    event VoteCast(
        address voter,
        uint256 proposalId,
        uint8 voteValue,
        uint256 votes
    );
    event ProposalInitialized(
        address proposer,
        uint256 proposalId,
        string descriptionUri
    );
    event ProposalAppended(address proposer, uint256 proposalId);
    event ProposalCreated(
        uint256 id,
        address proposer,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        uint256 votingStartTime,
        uint256 votingEndTime,
        string descriptionUri
    );
    event ProposalCanceled(uint256 id);
    event ProposalQueued(uint256 id, uint256 eta);
    event ProposalExecuted(uint256 id);
    event BreakGlassExecuted(
        address breakGlassGuardian,
        address[] targets,
        bytes[] calldatas
    );
    event QuroumVotesChanged(uint256 oldValue, uint256 newValue);
    event ProposalThresholdChanged(uint256 oldValue, uint256 newValue);
    event VotingPeriodChanged(uint256 oldValue, uint256 newValue);
    event BreakGlassGuardianChanged(address oldValue, address newValue);
    event GovernanceReturnAddressChanged(address oldValue, address newValue);
    event CrossChainVoteCollectionPeriodChanged(
        uint256 oldValue,
        uint256 newValue
    );
    event CrossChainVoteCollected(
        uint256 proposalId,
        uint16 sourceChain,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 abstainVotes
    );
    event CalldataApprovalUpdated(bytes data, bool approved);
    event ProposalRebroadcasted(uint256 proposalId, bytes data);
    event FallbackReceived(address sender, uint256 value);

    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////
    //// --------------- Data Structures -------------- ////
    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////

    /// @notice Possible states that a proposal may be in
    enum ProposalState {
        Active, // Users can cast votes
        CrossChainVoteCollection, // Votes from other chains can be registered
        Canceled, // proposer canceled during active period, proposer votes fell below threshold and was canceled during active period, or contract was paused while proposal was in state Active, CrossChainVoteCollection or Succeeded
        Defeated, // nay votes are greater than or equal to yay votes or total votes are less than quorum
        Succeeded, // yay votes are greater than nay votes, total votes meet or exceed quorum
        Executed, // reached succeeded state, and proposal was successfully executed
        Init // Proposal is in initialization phase, before the proposal is created and bridged out to other chains
    }

    struct ProposalInformation {
        /// @notice Creator of the proposal
        address proposer;
        /// @notice The timestamp at which vote snapshots are taken at
        uint256 voteSnapshotTimestamp;
        /// @notice the timestamp at which users can begin voting
        uint256 votingStartTime;
        /// @notice The timestamp at which voting ends: votes must be cast prior to this time
        uint256 votingEndTime;
        /// @notice The timestamp at which cross chain voting collection ends:
        /// votes must be registered prior to this time
        uint256 crossChainVoteCollectionEndTimestamp;
        /// @notice The block at which voting snapshot is taken: holders must have delegated their votes prior to this block
        uint256 startBlock;
        /// @notice Current number of votes in favor of this proposal
        uint256 forVotes;
        /// @notice Current number of votes in opposition to this proposal
        uint256 againstVotes;
        /// @notice Current number of votes in abstention to this proposal
        uint256 abstainVotes;
        /// @notice The total votes on a proposal.
        uint256 totalVotes;
    }

    struct Proposal {
        /// @notice Creator of the proposal
        address proposer;
        /// @notice the ordered list of target addresses for calls to be made
        address[] targets;
        /// @notice The ordered list of values (i.e. msg.value) to be passed to the calls to be made
        uint256[] values;
        /// @notice The ordered list of calldata to be passed to each call
        bytes[] calldatas;
        /// @notice The timestamp at which vote snapshots are taken at
        uint256 voteSnapshotTimestamp;
        /// @notice the timestamp at which users can begin voting
        uint256 votingStartTime;
        /// @notice The timestamp at which voting ends: votes must be cast prior to this time
        uint256 votingEndTime;
        /// @notice The timestamp at which cross chain voting collection ends:
        /// votes must be registered prior to or by this time
        uint256 crossChainVoteCollectionEndTimestamp;
        /// @notice Current number of votes in favor of this proposal
        uint256 forVotes;
        /// @notice Current number of votes in opposition to this proposal
        uint256 againstVotes;
        /// @notice Current number of votes in abstention to this proposal
        uint256 abstainVotes;
        /// @notice The total votes on a proposal.
        uint256 totalVotes;
        /// @notice Flag marking whether the proposal has been canceled
        bool canceled;
        /// @notice Flag marking whether the proposal has been executed
        bool executed;
        /// @notice Flag marking whether the proposal has been finalized (can no longer be appended to)
        bool finalized;
        /// @notice The URI of the proposal description
        string descriptionUri;
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

    /// @notice The total amount of votes for each option
    struct VoteCounts {
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
    }

    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////
    //// ------------- View Functions ----------------- ////
    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////

    /// @notice return votes for a proposal id on a given chain
    function chainAddressVotes(
        uint256 proposalId,
        uint16 chainId
    )
        external
        view
        returns (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes);

    /// break glass guardian
    function breakGlassGuardian() external view returns (address);

    /// @notice The total number of proposals
    function state(uint256 proposalId) external view returns (ProposalState);

    /// @notice The total amount of live proposals
    /// proposals in the pending, voting or cross chain vote collection period will be included in this list
    /// proposals that were cancelled, executed, or defeated will not be included in this list
    function liveProposals() external view returns (uint256[] memory);

    /// @dev Returns the proposal threshold (minimum number of votes to propose)
    /// changeable through governance proposals
    function proposalThreshold() external view returns (uint256);

    /// @dev Returns the voting period for a proposal to pass
    function votingPeriod() external view returns (uint256);

    /// @dev Returns the cross chain voting period
    function crossChainVoteCollectionPeriod() external view returns (uint256);

    /// @dev Returns the quorum for a proposal to pass
    function quorum() external view returns (uint256);

    /// ---------------------------------------------- ////
    /// ---------------------------------------------- ////
    /// ------------- Permisslionless ---------------- ////
    /// ---------------------------------------------- ////
    /// ---------------------------------------------- ////

    /// @notice Allows for the creation of a new proposal
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory descriptionUri,
        bool finalize
    ) external payable returns (uint256);

    /// @notice Allows for the appending of a new proposal
    function propose(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bool finalize
    ) external payable;

    function execute(uint256 proposalId) external payable;

    /// @dev callable only by the proposer, cancels proposal if it has not been executed
    function cancel(uint256 proposalId) external;

    /// @dev callable by anyone, succeeds in cancellation if user has less votes than proposal threshold
    /// at the current point in time.
    /// reverts otherwise.

    /// @dev allows user to cast vote for a proposal
    function castVote(uint256 proposalId, uint8 voteValue) external;

    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////
    /// ---------- governance only functions ---------- ////
    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////

    /// updates the proposal threshold
    function updateProposalThreshold(uint256 newProposalThreshold) external;

    /// updates the quorum
    function updateQuorum(uint256 newQuorum) external;

    /// updates the voting period
    function updateVotingPeriod(uint256 newVotingPeriod) external;

    /// updates the cross chain voting collection period
    function updateCrossChainVoteCollectionPeriod(
        uint256 newCrossChainVoteCollectionPeriod
    ) external;

    /// @notice sets the break glass guardian address
    /// @param newGuardian the new break glass guardian address
    function setBreakGlassGuardian(address newGuardian) external;

    /// @notice remove trusted senders from external chains
    /// can only remove trusted senders from a chain that is already stored
    /// if the chain doesn't already exist in storage, revert
    /// @param _trustedSenders array of trusted senders to remove
    function removeExternalChainConfigs(
        WormholeTrustedSender.TrustedSender[] memory _trustedSenders
    ) external;

    /// @notice add trusted senders from external chains
    /// can only add one trusted sender per chain,
    /// if more than one trusted sender per chain is added, revert
    /// @param _trustedSenders array of trusted senders to add
    function addExternalChainConfigs(
        WormholeTrustedSender.TrustedSender[] memory _trustedSenders
    ) external;

    /// @notice updates the approval for calldata to be used by break glass guardian
    /// @param data the calldata to update approval for
    /// @param approved whether or not the calldata is approved
    function updateApprovedCalldata(
        bytes calldata data,
        bool approved
    ) external;

    //// @notice array lengths must add up
    /// calldata must be whitelisted
    /// only break glass guardian can call, once, and when they do, their role is revoked
    function executeBreakGlass(
        address[] calldata targets,
        bytes[] calldata calldatas
    ) external;

    /// @notice set a gas limit for the relayer on the external chain
    /// should only be called if there is a change in gas prices on the external chain
    /// @param newGasLimit new gas limit to set
    function setGasLimit(uint96 newGasLimit) external;

    /// @notice grant new pause guardian
    /// @dev can only be called when unpaused, otherwise the
    /// contract can be paused again
    /// @param newPauseGuardian the new pause guardian
    function grantPauseGuardian(address newPauseGuardian) external;
}
