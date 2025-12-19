// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {Constants} from "@protocol/governance/multichain/Constants.sol";
import {WormholeBridgeBase} from "@protocol/wormhole/WormholeBridgeBase.sol";
import {IMultichainGovernorV2} from "@protocol/governance/multichain/IMultichainGovernorV2.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {ConfigurablePauseGuardian} from "@protocol/xWELL/ConfigurablePauseGuardian.sol";
import {IVotingPowerAggregator} from "@protocol/governance/multichain/IVotingPowerAggregator.sol";

/// @title MultichainGovernorV2
/// @notice This contract allows users with voting power to propose and vote on governance proposals across multiple
/// chains. Uses wormhole to relay proposal information and collect votes from other chains. Pausable by guardian;
/// supports break glass rollback to previous governance.
contract MultichainGovernorV2 is
    IMultichainGovernorV2,
    ConfigurablePauseGuardian,
    WormholeBridgeBase
{
    using EnumerableSet for EnumerableSet.UintSet;

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// -------------------- STATE VARIABLES -------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice The total number of proposals
    /// proposal ID 0 is invalid and should never be 0
    uint256 public proposalCount;

    /// Invariant: _liveProposals.length == _userLiveProposals[allUsers].length

    /// Invariant: _liveProposals[x] is in the _userLiveProposals[_liveProposals[x].proposer] set
    /// if that is broken, the contract is bricked because _syncTotalLiveProposals will fail,
    /// causing pause, propose and execute to be bricked.

    /// @notice all live proposals, executed and cancelled proposals are removed
    /// when a new proposal is created, it is added to this set and any stale
    /// items are removed
    EnumerableSet.UintSet internal _liveProposals;

    /// @notice active proposals user has proposed
    /// will automatically clear executed or cancelled
    /// proposals from set when called by user
    mapping(address user => EnumerableSet.UintSet userProposals)
        internal _userLiveProposals;

    /// @notice the number of votes for a given proposal on a given chainid
    mapping(uint16 wormholeChainId => mapping(uint256 proposalId => VoteCounts))
        public chainVoteCollectorVotes;

    /// @notice the proposal information for a given proposal
    mapping(uint256 proposalId => Proposal) public proposals;

    /// @notice whether or not a calldata bytes is allowed for break glass guardian
    /// whether or not the calldata is whitelisted for break glass guardian
    /// functions to whitelist are based on previous whitelisted functions in the
    /// Artemis Governor contracts.
    /// Artemis Governor Break Glass calldata:
    /// - transferOwnership
    /// - _setPendingAdmin
    /// - setPendingAdmin
    /// - setAdmin
    /// - changeAdmin
    /// - setEmissionsManager
    /// new calldata:
    /// - publishMessage that adds rollback address as trusted sender in TemporalGovernor, with calldata for each chain
    mapping(bytes whitelistedCalldata => bool) internal _whitelistedCalldatas;

    /// --------------------------------------------------------- ///
    /// --------------------- VOTING PARAMS --------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice the voting power aggregator contract
    IVotingPowerAggregator public votingPower;

    /// @notice the period of time in which a proposal can have
    /// cross chain votes collected.
    /// if this period is changed in a governance proposal, it will not impact
    /// current or in flight proposal state, only the proposals that are created
    /// after this parameter is updated.
    uint256 public override crossChainVoteCollectionPeriod;

    /// @notice quorum needed for a proposal to pass
    /// if multiple governance proposals are in flight, and the first one to execute
    /// changes quorum, then this new quorum will go into effect on the next proposal.
    uint256 public override quorum;

    /// @notice the minimum number of votes needed to propose
    /// possible to cancel a proposal if proposal threshold increases during a live proposal
    /// where user has less than the new proposal threshold
    uint256 public override proposalThreshold;

    /// @notice the voting period in seconds
    /// changing this variable only affects the proposals created after the change
    uint256 public override votingPeriod;

    /// --------------------------------------------------------- ///
    /// ------------------------- SAFETY ------------------------ ///
    /// --------------------------------------------------------- ///

    /// @notice the break glass guardian address
    /// can only break glass one time, and then role is revoked
    /// and needs to be reinstated by governance
    address public override breakGlassGuardian;

    /// @notice disable the initializer to stop governance hijacking
    /// and avoid selfdestruct attacks.
    constructor() {
        _disableInitializers();
    }

    /// @notice struct containing initializer data
    struct InitializeData {
        /// voting power aggregator address
        address votingPower;
        /// proposal threshold
        uint256 proposalThreshold;
        /// voting period in seconds
        uint256 votingPeriodSeconds;
        /// cross chain voting collection period in seconds
        uint256 crossChainVoteCollectionPeriod;
        /// number of total votes required to meet quorum
        uint256 quorum;
        /// pause duration in seconds
        uint128 pauseDuration;
        /// running proposal count from previous governor
        uint128 startingProposalCount;
        /// pause guardian address
        address pauseGuardian;
        /// break glass guardian address
        address breakGlassGuardian;
        /// wormhole relayer
        address wormholeRelayer;
    }

    /// @notice initialize the governor contract
    /// @param initData initialization data
    /// @param trustedSenders that can relay messages to this contract
    /// @param calldatas calldatas to whitelist for break glass guardian
    function initialize(
        InitializeData memory initData,
        WormholeTrustedSender.TrustedSender[] memory trustedSenders,
        bytes[] calldata calldatas
    ) external initializer {
        if (initData.votingPower == address(0)) {
            revert ZeroAddress();
        }
        votingPower = IVotingPowerAggregator(initData.votingPower);

        _setProposalThreshold(initData.proposalThreshold);
        _setVotingPeriod(initData.votingPeriodSeconds);
        _setCrossChainVoteCollectionPeriod(
            initData.crossChainVoteCollectionPeriod
        );
        _setQuorum(initData.quorum);
        _setBreakGlassGuardian(initData.breakGlassGuardian);

        __Pausable_init();

        _updatePauseDuration(initData.pauseDuration);

        /// set the pause guardian
        _grantGuardian(initData.pauseGuardian);

        _setWormholeRelayer(address(initData.wormholeRelayer));

        /// sets vote collection contracts
        _addTargetAddresses(trustedSenders);

        _setGasLimit(Constants.MIN_GAS_LIMIT); /// set the gas limit to 400k

        proposalCount = uint256(initData.startingProposalCount);

        unchecked {
            for (uint256 i = 0; i < calldatas.length; i++) {
                _updateApprovedCalldata(calldatas[i], true);
            }
        }
    }

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// ----------------------- MODIFIERS ----------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice modifier to restrict function access to only governor address
    modifier onlyGovernor() {
        if (msg.sender != address(this)) {
            revert OnlyGovernor();
        }
        _;
    }

    /// @notice modifier to restrict function access to only break glass guardian
    /// immediately sets break glass guardian to address 0 on use, and emits the
    /// BreakGlassGuardianChanged event
    modifier onlyBreakGlassGuardian() {
        if (msg.sender != breakGlassGuardian) {
            revert OnlyBreakGlassGuardian();
        }

        emit BreakGlassGuardianChanged(breakGlassGuardian, address(0));

        breakGlassGuardian = address(0);

        _;
    }

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// -------------------- VIEW FUNCTIONS --------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice returns a user's vote receipt on a given proposal
    /// @param proposalId the id of the proposal to check
    /// @param voter the address of the voter to check
    /// if hasVoted is false, this implies that vote value and votes are both 0
    function getReceipt(
        uint256 proposalId,
        address voter
    ) external view returns (bool hasVoted, uint8 voteValue, uint256 votes) {
        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = proposal.receipts[voter];

        hasVoted = receipt.hasVoted;
        voteValue = receipt.voteValue;
        votes = receipt.votes;
    }

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
        )
    {
        Proposal storage proposal = proposals[proposalId];

        totalVotes = proposal.totalVotes;
        forVotes = proposal.forVotes;
        againstVotes = proposal.againstVotes;
        abstainVotes = proposal.abstainVotes;
    }

    /// @notice returns information about a proposal
    /// @param proposalId the id of the proposal to check
    function getProposalData(
        uint256 proposalId
    )
        external
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        )
    {
        targets = proposals[proposalId].targets;
        values = proposals[proposalId].values;
        calldatas = proposals[proposalId].calldatas;
    }

    /// @notice returns the currently live proposals
    /// live proposals are defined as being in the
    /// Active, or CrossChainVoteCollection period.
    function liveProposals() external view override returns (uint256[] memory) {
        uint256 liveProposalCount = getNumLiveProposals();
        uint256[] memory liveProposalIds = new uint256[](liveProposalCount);

        uint256[] memory allProposals = _liveProposals.values();
        uint256 liveProposalIndex = 0;

        unchecked {
            for (uint256 i = 0; i < allProposals.length; i++) {
                if (proposalActive(allProposals[i])) {
                    /// these values should never go above uint_max
                    liveProposalIds[liveProposalIndex] = allProposals[i];
                    liveProposalIndex++;
                }
            }
        }

        return liveProposalIds;
    }

    /// @notice returns the number of live proposals,
    /// live proposals are defined as being in the
    /// Active, or CrossChainVoteCollection period.
    function getNumLiveProposals() public view returns (uint256 count) {
        uint256[] memory allProposals = _liveProposals.values();

        unchecked {
            for (uint256 i = 0; i < allProposals.length; i++) {
                if (proposalActive(allProposals[i])) {
                    count++;
                }
            }
        }
    }

    /// @notice returns the number of live proposals a user has
    /// a proposal is considered live if it is active or in
    /// cross chain vote collection period
    /// If canceled it is not considered counted as a live proposal
    /// If succeeded it is not considered counted as a live proposal as it could be executed at any time
    /// If failed it is not considered counted as a live proposal as it can never be executed
    /// If executed it is not considered counted as a live proposal as it can never be executed again
    /// @param user The address of the user to check
    /// this number should never be greater than the constant MAX_USER_LIVE_PROPOSALS
    function currentUserLiveProposals(
        address user
    ) public view returns (uint256) {
        uint256[] memory userProposals = _userLiveProposals[user].values();

        uint256 totalLiveProposals = 0;
        unchecked {
            for (uint256 i = 0; i < userProposals.length; i++) {
                if (proposalActive(userProposals[i])) {
                    totalLiveProposals++;
                }
            }
        }

        return totalLiveProposals;
    }

    /// @notice returns whether or not a given propsal is active
    /// @param proposalId the id of the proposal to check
    function proposalActive(uint256 proposalId) public view returns (bool) {
        ProposalState proposalState = state(proposalId);

        return
            proposalState == ProposalState.Active ||
            proposalState == ProposalState.CrossChainVoteCollection;
    }

    /// @notice return the votes for a particular chain and proposal
    /// @param proposalId the id of the proposal to check
    /// @param wormholeChainId the chain id to check votes from
    function chainAddressVotes(
        uint256 proposalId,
        uint16 wormholeChainId
    )
        external
        view
        returns (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes)
    {
        VoteCounts storage voteCounts = chainVoteCollectorVotes[
            wormholeChainId
        ][proposalId];
        forVotes = voteCounts.forVotes;
        againstVotes = voteCounts.againstVotes;
        abstainVotes = voteCounts.abstainVotes;
    }

    /// @notice The current state of a given proposal
    /// @param proposalId The id of the proposal to check
    function state(uint256 proposalId) public view returns (ProposalState) {
        if (proposalId == 0 || proposalId > proposalCount) {
            revert InvalidProposalId();
        }

        Proposal storage proposal = proposals[proposalId];

        // First check if the proposal cancelled as proposal can
        /// be canceled at any time during the lifecycle.
        if (proposal.canceled) {
            return ProposalState.Canceled;
            // Then check if the proposal is pending or active, in which case nothing else can be determined at this time.
        } else if (block.timestamp <= proposal.votingEndTime) {
            return ProposalState.Active;
            // Then, check if the proposal is in cross chain vote collection period
        } else if (
            block.timestamp <= proposal.crossChainVoteCollectionEndTimestamp
        ) {
            return ProposalState.CrossChainVoteCollection;
            /// anything from here on out means the proposal is no longer active, and no change in votes can be registered.
            // Then, check if the proposal is defeated. To hit this case, either (1) majority of yay/nay votes were nay or
            // (2) total votes was less than the quorum amount.
        } else if (
            proposal.forVotes <= proposal.againstVotes ||
            proposal.totalVotes < quorum
        ) {
            return ProposalState.Defeated;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        } else {
            /// Succeeded implies != defeated, executed, canceled, CrossChainVoteCollection, active or pending
            /// Succeeded implies for votes outweigh against votes, and quorum is met
            /// Succeeded implies block.timestamp > crossChainVoteCollectionEndTimestamp

            return ProposalState.Succeeded;
        }
    }

    /// ---------------------------------------------- ///
    /// ---------------------------------------------- ///
    /// ------------- Permisslionless ---------------- ///
    /// ---------------------------------------------- ///
    /// ---------------------------------------------- ///

    /// @notice allows for re-broadcasting of a proposal in case the
    /// wormhole relayer or wormhole core contract is paused.
    /// @dev can only be called if the proposal is in the active state
    /// @param proposalId the id of the proposal to rebroadcast
    function rebroadcastProposal(uint256 proposalId) external payable {
        ProposalState proposalState = state(proposalId);
        if (proposalState != ProposalState.Active) {
            revert InvalidProposalState(proposalState, ProposalState.Active);
        }

        Proposal storage proposal = proposals[proposalId];

        bytes memory payload = abi.encode(
            proposalId,
            proposal.voteSnapshotTimestamp,
            proposal.votingStartTime,
            proposal.votingEndTime,
            proposal.crossChainVoteCollectionEndTimestamp
        );

        _bridgeOutAll(payload);

        emit ProposalRebroadcasted(proposalId, payload);
    }

    /// @notice Allows for the creation of a new proposal
    /// @dev Only callable if user has proposal threshold or more votes. If finalize is set to false, it is the
    /// proposer's responsibility to finalize it by calling propose with the proposalId and finalize set to true.
    /// @param targets the list of target addresses for calls to be made
    /// @param values the list of values to be used for the calls
    /// @param calldatas the list of calldatas to be used for the calls
    /// @param descriptionUri the URI of the proposal description
    /// @param finalize whether or not to finalize the proposal (ie: true if there are no more targets)
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory descriptionUri,
        bool finalize
    ) external payable override whenNotPaused returns (uint256) {
        /// get user voting power from all voting sources
        _checkProposalThreshold(msg.sender);

        _validateProposalArrays(targets, values, calldatas, true);

        if (bytes(descriptionUri).length == 0) {
            revert EmptyDescriptionUri();
        }

        _syncTotalLiveProposals(); /// remove inactive proposals and remove from inactive proposals from user list

        if (
            currentUserLiveProposals(msg.sender) >=
            Constants.MAX_USER_PROPOSAL_COUNT
        ) {
            revert TooManyLiveProposals();
        }

        _checkValueOverflow(values);

        uint256 proposalId = ++proposalCount;
        Proposal storage newProposal = proposals[proposalId];

        _initializeProposal(
            newProposal,
            targets,
            values,
            calldatas,
            descriptionUri
        );

        /// post proposal checks
        if (!_userLiveProposals[msg.sender].add(proposalId)) {
            revert ProposalAlreadyExists();
        }
        if (!_liveProposals.add(proposalId)) {
            revert ProposalAlreadyExists();
        }

        if (finalize) {
            _finalizeProposal(proposalId, newProposal);
        } else {
            emit ProposalInitialized(msg.sender, proposalId, descriptionUri);
        }

        return proposalId;
    }

    /// @notice Allows for the appending of a new proposal
    /// @dev Only callable by the proposer and while the proposal is not finalized
    /// @param proposalId the id of the proposal to append to
    /// @param targets the list of target addresses for calls to be made
    /// @param values the list of values to be used for the calls
    /// @param calldatas the list of calldatas to be used for the calls
    /// @param finalize whether or not to finalize the proposal (ie: true if there are no more targets)
    function propose(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bool finalize
    ) external payable override whenNotPaused {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.finalized) {
            revert ProposalAlreadyFinalized();
        }
        if (msg.sender != proposal.proposer) {
            revert OnlyProposer();
        }

        _checkProposalThreshold(msg.sender);
        _validateProposalArrays(targets, values, calldatas, false);
        _checkValueOverflow(values);

        _appendToProposal(proposal, targets, values, calldatas);

        if (finalize) {
            _finalizeProposal(proposalId, proposal);
        }
    }

    /// @notice execute a proposal
    /// can only be called if the proposal is in the succeeded state
    /// can only be called when the contract is not paused
    /// the sum of the values must be equal to the msg.value
    /// the native token balance of this contract will remain unchanged before and after a proposal is executed
    /// @param proposalId the id of the proposal to execute
    function execute(
        uint256 proposalId
    ) external payable override whenNotPaused {
        Proposal storage proposal = proposals[proposalId];

        ProposalState proposalState = state(proposalId);
        if (proposalState != ProposalState.Succeeded) {
            revert InvalidProposalState(proposalState, ProposalState.Succeeded);
        }
        if (
            block.timestamp >
            proposal.crossChainVoteCollectionEndTimestamp +
                Constants.EXECUTION_WINDOW
        ) {
            revert ProposalExpired();
        }

        proposal.executed = true;

        /// remove the proposal that is about to be executed from all proposals,
        /// and remove from inactive proposals from user list
        _syncTotalLiveProposals();

        unchecked {
            for (uint256 i = 0; i < proposal.targets.length; i++) {
                _functionCallWithValue(
                    proposal.targets[i],
                    proposal.calldatas[i],
                    proposal.values[i]
                );
            }
        }

        emit ProposalExecuted(proposalId);
    }

    /// @dev callable only by the proposer, cancels proposal if it has not been executed
    ///  cancellation is allowed in either of these flows:
    ///  - proposer cancels
    ///  - permissionless cancel, user voting power currently drops below threshold
    /// and
    /// proposal is in one of the following states:
    /// - succeeded
    /// - active
    /// - cross chain vote collection period
    /// Edge Case:
    ///   If proposal threshold is increased in an active governance proposal, and a user has proposed
    /// when they met the old proposal threshold, but not the new one, then anyone can cancel their proposal.
    function cancel(uint256 proposalId) external override {
        if (
            msg.sender != proposals[proposalId].proposer &&
            votingPower.getCurrentVotes(proposals[proposalId].proposer) >=
            proposalThreshold
        ) {
            revert UnauthorizedCancel();
        }

        ProposalState proposalState = state(proposalId);

        if (proposalState != ProposalState.Active) {
            revert InvalidProposalState(proposalState, ProposalState.Active);
        }

        Proposal storage proposal = proposals[proposalId];
        proposal.canceled = true;

        /// remove the proposal that is canceled from all proposals,
        /// and remove it from inactive proposals in the user list
        _syncTotalLiveProposals();

        emit ProposalCanceled(proposalId);
    }

    /// @dev allows user to cast vote for a proposal
    /// @param proposalId the id of the proposal to vote on
    /// @param voteValue the value of the vote, can be either YES, NO, or ABSTAIN
    function castVote(
        uint256 proposalId,
        uint8 voteValue
    ) external override whenNotPaused {
        ProposalState proposalState = state(proposalId);
        if (proposalState != ProposalState.Active) {
            revert InvalidProposalState(proposalState, ProposalState.Active);
        }
        if (voteValue > Constants.VOTE_VALUE_ABSTAIN) {
            revert InvalidVoteValue();
        }

        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = proposal.receipts[msg.sender];

        if (receipt.hasVoted) {
            revert AlreadyVoted();
        }

        /// if a user tries to vote at the start timestamp or the start block, then it will fail,
        /// but that is not possible because both of those are in the past as set in the propose
        /// function.
        uint256 votes = votingPower.getVotes(
            msg.sender,
            proposal.voteSnapshotTimestamp,
            proposal.voteSnapshotBlock
        );

        if (votes == 0) {
            revert NoVotingPower();
        }

        if (voteValue == Constants.VOTE_VALUE_YES) {
            proposal.forVotes += votes;
        } else if (voteValue == Constants.VOTE_VALUE_NO) {
            proposal.againstVotes += votes;
        } else if (voteValue == Constants.VOTE_VALUE_ABSTAIN) {
            proposal.abstainVotes += votes;
        }

        // Increase total votes
        proposal.totalVotes += votes;

        receipt.hasVoted = true;
        receipt.voteValue = voteValue;
        receipt.votes = votes;

        emit VoteCast(msg.sender, proposalId, voteValue, votes);
    }

    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////
    /// ---------- governance only functions ---------- ////
    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////

    /// @notice updates the approval for calldata to be used by break glass guardian
    /// @param data the calldata to update approval for
    /// @param approved whether or not the calldata is approved
    function updateApprovedCalldata(
        bytes calldata data,
        bool approved
    ) external onlyGovernor {
        _updateApprovedCalldata(data, approved);
    }

    /// @notice remove trusted senders from external chains
    /// can only remove trusted senders from a chain that is already stored
    /// if the chain doesn't already exist in storage, revert
    /// @param _trustedSenders array of trusted senders to remove
    function removeExternalChainConfigs(
        WormholeTrustedSender.TrustedSender[] memory _trustedSenders
    ) external onlyGovernor {
        _removeTargetAddresses(_trustedSenders);
    }

    /// @notice add trusted senders from external chains
    /// can only add one trusted sender per chain,
    /// if more than one trusted sender per chain is added, revert
    /// @param _trustedSenders array of trusted senders to add
    function addExternalChainConfigs(
        WormholeTrustedSender.TrustedSender[] memory _trustedSenders
    ) external onlyGovernor {
        _addTargetAddresses(_trustedSenders);
    }

    /// @notice updates the proposal threshold
    /// @param newProposalThreshold the new proposal threshold
    function updateProposalThreshold(
        uint256 newProposalThreshold
    ) external override onlyGovernor {
        _setProposalThreshold(newProposalThreshold);
    }

    /// @notice updates the quorum, callable only by this contract
    /// @param newQuorum the new quorum
    function updateQuorum(uint256 newQuorum) external override onlyGovernor {
        _setQuorum(newQuorum);
    }

    /// @notice change to accept both block and timestamp and then validate that they are within a certain range
    /// i.e. the block number * block time is equals the timestamp
    /// updates the voting period
    /// @param newVotingPeriod the new voting period
    function updateVotingPeriod(
        uint256 newVotingPeriod
    ) external override onlyGovernor {
        _setVotingPeriod(newVotingPeriod);
    }

    /// updates the cross chain voting collection period
    /// @param newCrossChainVoteCollectionPeriod the new cross chain voting collection period
    function updateCrossChainVoteCollectionPeriod(
        uint256 newCrossChainVoteCollectionPeriod
    ) external override onlyGovernor {
        _setCrossChainVoteCollectionPeriod(newCrossChainVoteCollectionPeriod);
    }

    /// @notice sets the break glass guardian address
    /// @param newGuardian the new break glass guardian address
    function setBreakGlassGuardian(
        address newGuardian
    ) external override onlyGovernor {
        _setBreakGlassGuardian(newGuardian);
    }

    /// @notice set a gas limit for the relayer on the external chain
    /// should only be called if there is a change in gas prices on the external chain
    /// @param newGasLimit new gas limit to set
    function setGasLimit(uint96 newGasLimit) external onlyGovernor {
        if (newGasLimit < Constants.MIN_GAS_LIMIT) {
            revert GasLimitTooLow();
        }

        _setGasLimit(newGasLimit);
    }

    /// @notice grant new pause guardian
    /// @dev can only be called when unpaused, otherwise the
    /// contract can be paused again
    /// @param newPauseGuardian the new pause guardian
    function grantPauseGuardian(
        address newPauseGuardian
    ) external onlyGovernor whenNotPaused {
        _grantGuardian(newPauseGuardian);
    }

    //// @notice array lengths must add up
    /// calldata must be whitelisted
    /// only break glass guardian can call, once, and when they do, their role is revoked
    /// before any external functions are called. This prevents reentrancy/multiple uses
    /// by a single guardian.
    /// can be called in any pause state (paused or unpaused)
    /// potential attack vector:
    ///    - gov proposal passes that whitelists calldata to change some parameter on Governor
    ///    or governance owned contracts that it shouldn't. Now, break glass guardian can call
    ///    functions that it was not originally intended to call, once.
    ///    - if one of the calldatas is to change the break glass guardian, then it could
    ///    theoretically grant itself the role again. This is mitigated by the check at post effects
    ///    that the break glass guardian is address(0).
    ///    - reentrancy is allowed, but no advantage could be gained from it by a malicious break
    ///    glass guardian because at the end of the function, the break glass guardian must be
    ///    address(0), so you're only constrained by whitelisted calldata and the gas limit for
    ///    transactions which is 13m currently on Moonbeam.
    ///    - assumption that any executeBreakGlassGuardian calls will not require any msg.value
    /// @param targets the targets to call
    /// @param calldatas the calldatas to call
    function executeBreakGlass(
        address[] calldata targets,
        bytes[] calldata calldatas
    ) external override onlyBreakGlassGuardian {
        if (targets.length != calldatas.length) {
            revert ArityMismatch();
        }

        if (targets.length == 0) {
            revert EmptyArray();
        }

        unchecked {
            for (uint256 i = 0; i < calldatas.length; i++) {
                if (!_whitelistedCalldatas[calldatas[i]]) {
                    revert CalldataNotWhitelisted();
                }

                _functionCallWithValue(targets[i], calldatas[i], 0);
            }
        }

        if (breakGlassGuardian != address(0)) {
            revert BreakGlassGuardianNotNull();
        }

        emit BreakGlassExecuted(msg.sender, targets, calldatas);
    }

    /// @notice only callable by the pause guardian when not paused
    /// automatically cancels all in flight proposals
    /// any proposal that is in an active, vote collection, succeeded or defeated state will be canceled
    function pause() public override {
        super.pause();

        uint256[] memory allProposals = _liveProposals.values();

        for (uint256 i = 0; i < allProposals.length; ) {
            ProposalState proposalState = state(allProposals[i]);
            ///
            ///         Cancellation
            ///
            /// if proposal is in the active state, it could be Succeeded once xchain vote collection period ends
            /// if proposal is in the active state it will be cancelled
            /// if proposal is in the CrossChainVoteCollection state it will be cancelled
            /// if proposal is in the Succeeded state it will be cancelled
            ///
            ///         Non Cancellation
            ///
            /// if proposal is in the Defeated state, it cannot be executed, so it can not be cancelled
            /// if proposal is in the Canceled state, it cannot be executed or cancelled again
            /// if proposal is in the Executed state, it cannot be cancelled because it was already executed
            ///
            if (
                proposalState != ProposalState.Executed &&
                proposalState != ProposalState.Defeated &&
                proposalState != ProposalState.Canceled
            ) {
                proposals[allProposals[i]].canceled = true;

                emit ProposalCanceled(allProposals[i]);
            }

            unchecked {
                i++;
            }
        }

        /// remove all canceled and now inactive proposals from all proposals,
        /// and remove from inactive proposals from user list
        _syncTotalLiveProposals();
    }

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// ------------------- HELPER FUNCTIONS -------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice checks if an address meets the proposal threshold
    /// @param account the address to check
    function _checkProposalThreshold(address account) private view {
        if (
            votingPower.getVotes(
                account,
                block.timestamp - 1,
                block.number - 1
            ) < proposalThreshold
        ) {
            revert VotesBelowProposalThreshold();
        }
    }

    /// @notice helper function to whitelist calldata
    /// if the calldata is already whitelisted, then it can only be removed
    /// if the calldata is not already whitelisted, then it can only be approved
    /// @param data the calldata to update approval for
    /// @param approved whether or not the calldata is approved
    function _updateApprovedCalldata(
        bytes calldata data,
        bool approved
    ) private {
        /// revert if current state matches desired state
        if (_whitelistedCalldatas[data] == approved) {
            if (approved) {
                revert CalldataAlreadyApproved();
            }

            revert CalldataNotApproved();
        }

        _whitelistedCalldatas[data] = approved;

        emit CalldataApprovalUpdated(data, approved);
    }

    /// @notice helper function to set the cross chain vote collection period
    /// upper and lower bounds are enforced to ensure that the period is within
    /// reasonable bounds.
    function _setCrossChainVoteCollectionPeriod(
        uint256 _crossChainVoteCollectionPeriod
    ) private {
        if (
            _crossChainVoteCollectionPeriod <
            Constants.MIN_CROSS_CHAIN_VOTE_COLLECTION_PERIOD ||
            _crossChainVoteCollectionPeriod >
            Constants.MAX_CROSS_CHAIN_VOTE_COLLECTION_PERIOD
        ) {
            revert InvalidVoteCollectionPeriod();
        }

        uint256 oldVal = crossChainVoteCollectionPeriod;
        crossChainVoteCollectionPeriod = _crossChainVoteCollectionPeriod;

        emit CrossChainVoteCollectionPeriodChanged(
            oldVal,
            _crossChainVoteCollectionPeriod
        );
    }

    /// @dev minimum quorum is 0, maximum quorum value is enforced
    /// @param _quorum the new quorum
    function _setQuorum(uint256 _quorum) private {
        if (_quorum > Constants.MAX_QUORUM) {
            revert InvalidQuorum();
        }

        uint256 _oldValue = quorum;
        quorum = _quorum;

        emit QuroumVotesChanged(_oldValue, _quorum);
    }

    /// @dev lower and upper bounds are enforced to prevent a proposal from
    /// continuing indefinitely and breaking governance
    /// @param _votingPeriod the new voting period
    function _setVotingPeriod(uint256 _votingPeriod) private {
        if (
            _votingPeriod < Constants.MIN_VOTING_PERIOD ||
            _votingPeriod > Constants.MAX_VOTING_PERIOD
        ) {
            revert VotingPeriodOutOfBounds();
        }

        uint256 _oldValue = votingPeriod;

        votingPeriod = _votingPeriod;

        emit VotingPeriodChanged(_oldValue, _votingPeriod);
    }

    /// @dev upper and lower bounds enforced to prevent a scenario
    /// where users cannot propose to the governor
    /// @param _proposalThreshold the new proposal threshold
    function _setProposalThreshold(uint256 _proposalThreshold) private {
        if (
            _proposalThreshold < Constants.MIN_PROPOSAL_THRESHOLD ||
            _proposalThreshold > Constants.MAX_PROPOSAL_THRESHOLD
        ) {
            revert ProposalThresholdOutOfBounds();
        }

        uint256 oldValue = proposalThreshold;
        proposalThreshold = _proposalThreshold;

        emit ProposalThresholdChanged(oldValue, _proposalThreshold);
    }

    /// @dev valid state for break glass guardian to be address(0)
    /// @param newGuardian the new guardian address
    function _setBreakGlassGuardian(address newGuardian) private {
        address oldGuardian = breakGlassGuardian;
        breakGlassGuardian = newGuardian;

        emit BreakGlassGuardianChanged(oldGuardian, newGuardian);
    }

    /// Helper function to sync all values in both sets.
    /// if the proposal is Defeated, Canceled, or Executed state,
    /// remove it from the _liveProposals and _userLiveProposals
    /// sets to remove unused values from storage and decrease
    /// loop length in getter functions.
    function _syncTotalLiveProposals() private {
        uint256[] memory allProposals = _liveProposals.values();

        unchecked {
            for (uint256 i = 0; i < allProposals.length; i++) {
                ProposalState proposalsState = state(allProposals[i]);
                if (
                    proposalsState == ProposalState.Defeated ||
                    proposalsState == ProposalState.Canceled ||
                    proposalsState == ProposalState.Executed
                ) {
                    /// remove proposal from user before removing from the global set
                    /// this ensures that the user can sync their live proposals and propose
                    /// new proposals
                    if (
                        !_userLiveProposals[proposals[allProposals[i]].proposer]
                            .remove(allProposals[i])
                    ) {
                        revert ProposalRemovalFailed(false);
                    }

                    if (!_liveProposals.remove(allProposals[i])) {
                        revert ProposalRemovalFailed(true);
                    }
                }
            }
        }
    }

    /// @notice allows votes from external chains to be counted
    /// ensures validity of sender, and only allows one vote tally to be received
    /// per wormhole chainid per proposal.
    /// this means that votes cannot be updated from a given chain and proposal
    /// once they are received.
    /// @param sourceChain the chain id of the source chain
    /// @param payload contains proposalId, forVotes, againstVotes, abstainVotes
    function _bridgeIn(
        uint16 sourceChain,
        bytes memory payload
    ) internal override {
        /// payload should be 4 uint256s
        if (payload.length != 128) {
            revert InvalidPayloadLength();
        }

        (
            uint256 proposalId,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 abstainVotes
        ) = abi.decode(payload, (uint256, uint256, uint256, uint256));

        /// only allow relayer creation of vote counts once on vote collector
        /// contract and only if there is at least 1 value that is non zero
        /// if there have been no votes cast for a particular proposal, do not allow
        /// the relaying of any information cross chain
        VoteCounts storage voteCounts = chainVoteCollectorVotes[sourceChain][
            proposalId
        ];

        /// logic to ensure cross chain vote collection contract can only relay vote counts once for a given proposal
        /// if all of these values are zero, then the values have not been set yet
        if (
            voteCounts.forVotes != 0 ||
            voteCounts.againstVotes != 0 ||
            voteCounts.abstainVotes != 0
        ) {
            revert VoteAlreadyCollected();
        }

        ProposalState proposalState = state(proposalId);
        if (proposalState != ProposalState.CrossChainVoteCollection) {
            revert InvalidProposalState(
                proposalState,
                ProposalState.CrossChainVoteCollection
            );
        }

        voteCounts.forVotes = forVotes;
        voteCounts.againstVotes = againstVotes;
        voteCounts.abstainVotes = abstainVotes;

        /// update the proposal state to contain these votes by modifying the proposal struct
        Proposal storage proposal = proposals[proposalId];

        proposal.forVotes += forVotes;
        proposal.againstVotes += againstVotes;
        proposal.abstainVotes += abstainVotes;

        /// increment totalVotes to maintain invariant TotalVotes = ForVotes + AgainstVotes + AbstainVotes
        proposal.totalVotes += forVotes + againstVotes + abstainVotes;

        emit CrossChainVoteCollected(
            proposalId,
            sourceChain,
            forVotes,
            againstVotes,
            abstainVotes
        );
    }

    /// @notice Validates that proposal arrays have correct arity and optionally checks for non-empty
    /// @param targets the list of target addresses
    /// @param values the list of values
    /// @param calldatas the list of calldatas
    /// @param requireNonEmpty whether to require non-empty arrays
    function _validateProposalArrays(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bool requireNonEmpty
    ) internal pure {
        if (
            targets.length != values.length ||
            targets.length != calldatas.length
        ) {
            revert ArityMismatch();
        }
        if (requireNonEmpty && targets.length == 0) {
            revert EmptyArray();
        }
    }

    /// @notice Checks that the sum of values does not overflow
    /// @param values the list of values to check
    function _checkValueOverflow(uint256[] memory values) internal pure {
        uint256 totalValue = 0;
        for (uint256 i = 0; i < values.length; ) {
            totalValue += values[i];
            unchecked {
                i++;
            }
        }
    }

    /// @notice Initializes a new proposal with the given parameters
    /// @param proposal the proposal storage reference
    /// @param targets the list of target addresses
    /// @param values the list of values
    /// @param calldatas the list of calldatas
    /// @param descriptionUri the URI of the proposal description
    function _initializeProposal(
        Proposal storage proposal,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory descriptionUri
    ) internal {
        proposal.proposer = msg.sender;
        proposal.targets = targets;
        proposal.values = values;
        proposal.calldatas = calldatas;
        proposal.descriptionUri = descriptionUri;
    }

    /// @notice Appends targets, values, and calldatas to an existing proposal
    /// @param proposal the proposal storage reference
    /// @param targets the list of target addresses to append
    /// @param values the list of values to append
    /// @param calldatas the list of calldatas to append
    function _appendToProposal(
        Proposal storage proposal,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) internal {
        for (uint256 i = 0; i < targets.length; ) {
            proposal.targets.push(targets[i]);
            proposal.values.push(values[i]);
            proposal.calldatas.push(calldatas[i]);
            unchecked {
                i++;
            }
        }
    }

    /// @notice Finalizes a proposal by setting timestamps, encoding payload, emitting event, and bridging out
    /// @param proposalId the id of the proposal
    /// @param proposal the proposal storage reference
    function _finalizeProposal(
        uint256 proposalId,
        Proposal storage proposal
    ) internal {
        uint256 startTimestamp = block.timestamp;
        uint256 voteSnapshotTimestamp = startTimestamp - 1;
        uint256 endTimestamp = startTimestamp + votingPeriod;
        uint256 crossChainVoteCollectionEndTimestamp = endTimestamp +
            crossChainVoteCollectionPeriod;

        proposal.voteSnapshotTimestamp = voteSnapshotTimestamp;
        proposal.votingStartTime = startTimestamp;
        proposal.voteSnapshotBlock = block.number - 1;
        proposal.votingEndTime = endTimestamp;
        proposal
            .crossChainVoteCollectionEndTimestamp = crossChainVoteCollectionEndTimestamp;
        proposal.finalized = true;

        bytes memory payload = abi.encode(
            proposalId,
            proposal.voteSnapshotTimestamp,
            proposal.votingStartTime,
            proposal.votingEndTime,
            proposal.crossChainVoteCollectionEndTimestamp
        );

        emit ProposalCreated(
            proposalId,
            msg.sender,
            proposal.targets,
            proposal.values,
            proposal.calldatas,
            proposal.votingStartTime,
            proposal.votingEndTime,
            proposal.descriptionUri
        );

        /// for each temporal governor, relay a payload with proposal information
        _bridgeOutAll(payload);
    }

    /// @notice Make an external call with value, bubbling up revert reasons
    /// @param target The address to call
    /// @param data The calldata to send
    /// @param value The value to send with the call
    function _functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) private {
        (bool success, bytes memory returndata) = target.call{value: value}(
            data
        );
        if (success) {
            if (returndata.length == 0 && target.code.length == 0) {
                revert CallToNonContract();
            }
        } else {
            _revertWithData(returndata, ExecuteCallFailed.selector);
        }
    }

    /// @notice Bubbles up revert data if present, otherwise reverts with custom error
    /// @param returndata The return data from the failed call
    /// @param errorSelector The selector of the custom error to use if no revert data
    function _revertWithData(
        bytes memory returndata,
        bytes4 errorSelector
    ) private pure {
        if (returndata.length > 0) {
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            /// @solidity memory-safe-assembly
            assembly {
                mstore(0, errorSelector)
                revert(0, 4)
            }
        }
    }

    /// @notice payable fallback function to receive funds specifically
    /// included for the xWELLRouter to allow tokens to be bridged to other
    /// chains
    receive() external payable {
        emit FallbackReceived(msg.sender, msg.value);
    }
}
