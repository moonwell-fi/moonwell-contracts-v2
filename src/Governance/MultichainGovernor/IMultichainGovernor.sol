pragma solidity 0.8.19;

import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";

/// @notice pauseable by the guardian
/// @notice upgradeable, constructor disables implementation
interface IMultichainGovernor {
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// ------------------------- EVENTS ------------------------ ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice An event emitted when the first vote is cast in a proposal
    event StartBlockSet(uint256 proposalId, uint256 startBlock);

    /// @notice An event emitted when a vote has been cast on a proposal
    event VoteCast(
        address voter,
        uint256 proposalId,
        uint8 voteValue,
        uint256 votes
    );

    /// @notice An event emitted when a new proposal is created
    event ProposalCreated(
        uint256 id,
        address proposer,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        uint256 votingStartTime,
        uint256 votingEndTime,
        string description
    );

    /// @notice An event emitted when a proposal has been canceled
    event ProposalCanceled(uint256 id);

    /// @notice An event emitted when a proposal has been queued in the Timelock
    event ProposalQueued(uint256 id, uint256 eta);

    /// @notice An event emitted when a proposal has been executed in the Timelock
    event ProposalExecuted(uint256 id);

    /// @notice An event emitted when the guardian breaks glass
    event BreakGlassExecuted(
        address breakGlassGuardian,
        address[] targets,
        bytes[] calldatas
    );

    /// @notice An event emitted when thee quorum votes is changed.
    event QuroumVotesChanged(uint256 oldValue, uint256 newValue);

    /// @notice An event emitted when the proposal threshold is changed.
    event ProposalThresholdChanged(uint256 oldValue, uint256 newValue);

    /// @notice An event emitted when the voting period is changed.
    event VotingPeriodChanged(uint256 oldValue, uint256 newValue);

    /// @notice An event emitted when the break glass guardian is changed.
    event BreakGlassGuardianChanged(address oldValue, address newValue);

    /// @notice An event emitted when the governance return address is changed.
    event GovernanceReturnAddressChanged(address oldValue, address newValue);

    /// @notice An event emitted when the cross chain vote collection period has changed.
    event CrossChainVoteCollectionPeriodChanged(
        uint256 oldValue,
        uint256 newValue
    );

    /// @notice An event emitted when the max user live proposals has changed.
    event UserMaxProposalsChanged(uint256 oldValue, uint256 newValue);

    /// @notice emitted when a cross chain vote is collected
    /// @param proposalId the proposal id
    /// @param sourceChain the wormhole chain id the vote was collected from
    /// @param forVotes the number of votes for the proposal
    /// @param againstVotes the number of votes against the proposal
    /// @param abstainVotes the number of votes abstaining from the proposal
    event CrossChainVoteCollected(
        uint256 proposalId,
        uint16 sourceChain,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 abstainVotes
    );

    /// @notice emitted when a chain config is updated
    /// @param chainId the chain id of the chain config
    /// @param destinationAddress the destination address of the chain config
    /// @param removed whether or not the chain config was removed
    event ChainConfigUpdated(
        uint16 chainId,
        address destinationAddress,
        bool removed
    );

    /// @notice emitted when a calldata approval is changed for break glass guardian
    /// @param data the calldata that was approved or unapproved
    /// @param approved whether or not the calldata was approved or unapproved
    event CalldataApprovalUpdated(bytes data, bool approved);

    /// @notice emitted when a proposal is rebroadcasted
    /// @param proposalId the proposal id
    /// @param data the calldata that was rebroadcasted
    event ProposalRebroadcasted(uint256 proposalId, bytes data);

    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////
    //// --------------- Data Structures -------------- ////
    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////

    /// @notice Possible states that a proposal may be in
    enum ProposalState {
        Active,
        CrossChainVoteCollection,
        Canceled,
        Defeated,
        Succeeded,
        Executed
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
        /// TODO on naming here
        /// @notice The timestamp at which vote snapshots are taken at
        uint256 voteSnapshotTimestamp;
        /// @notice the timestamp at which users can begin voting
        uint256 votingStartTime;
        /// @notice The timestamp at which voting ends: votes must be cast prior to this time
        uint256 votingEndTime;
        /// @notice The timestamp at which cross chain voting collection ends:
        /// votes must be registered prior to or by this time
        uint256 crossChainVoteCollectionEndTimestamp;
        /// @notice The block at which voting snapshot is taken: holders must have delegated their votes prior to this block
        uint256 voteSnapshotBlock;
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

    /// whether or not the calldata is whitelisted for break glass guardian
    /// functions to whitelist are:
    /// - transferOwnership to rollback address
    /// - setPendingAdmin to rollback address
    /// - setAdmin to rollback address
    /// - publishMessage that adds rollback address as trusted sender in TemporalGovernor, with calldata for each chain
    function whitelistedCalldatas(bytes calldata) external view returns (bool);

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

    /// @dev Returns the maximum number of live proposals per user
    /// changeable through governance proposals
    function maxUserLiveProposals() external view returns (uint256);

    /// @dev Returns the number of live proposals for a given user
    function currentUserLiveProposals(
        address user
    ) external view returns (uint256);

    /// returns the total voting power for an address at a given block number and timestamp
    /// @param account The address of the account to check
    /// @param timestamp The unix timestamp in seconds to check the balance at
    /// @param blockNumber The block number to check the balance at
    function getVotes(
        address account,
        uint256 timestamp,
        uint256 blockNumber
    ) external view returns (uint256);

    /// ---------------------------------------------- ////
    /// ---------------------------------------------- ////
    /// ------------- Permisslionless ---------------- ////
    /// ---------------------------------------------- ////
    /// ---------------------------------------------- ////

    /// @dev Returns the proposal ID for the proposed proposal
    /// only callable if user has proposal threshold or more votes
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external payable returns (uint256);

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

    /// updates the maximum user live proposals
    function updateMaxUserLiveProposals(uint256 newMaxLiveProposals) external;

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
}
