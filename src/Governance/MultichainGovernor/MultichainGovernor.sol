pragma solidity 0.8.19;

import {GovernorCompatibilityBravoUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/governance/compatibility/GovernorCompatibilityBravoUpgradeable.sol";
import {GovernorSettingsUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/governance/extensions/GovernorSettingsUpgradeable.sol";
import {ERC20VotesCompUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20VotesCompUpgradeable.sol";
import {GovernorUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/governance/GovernorUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {SnapshotInterface} from "@protocol/Governance/MultichainGovernor/SnapshotInterface.sol";
import {IMultichainGovernor} from "@protocol/Governance/MultichainGovernor/IMultichainGovernor.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {ConfigurablePauseGuardian} from "@protocol/xWELL/ConfigurablePauseGuardian.sol";

/// WARNING: this contract is at very high risk of running over bytecode size limit
///   we may need to split things out into multiple contracts, so keep things as
///   concise as possible.

/// @notice pauseable by the guardian
/// @notice upgradeable, constructor disables implementation

/// Note:
/// - moonbeam block times are consistently 12 seconds with few exceptions https://moonscan.io/chart/blocktime
/// this means that a timestamp can be converted to a block number with a high degree of accuracy

/// there can only be one
/// TODO, remove all OZ governor stuff, we're going to roll our own from scratch
abstract contract MultichainGovernor is
    WormholeTrustedSender,
    IMultichainGovernor,
    ConfigurablePauseGuardian
{
    using EnumerableSet for EnumerableSet.UintSet;

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// ----------------------- CONSTANTS ----------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice Values for votes

    /// @notice value for a yes vote
    uint8 public constant VOTE_VALUE_YES = 0;

    /// @notice value for a no vote
    uint8 public constant VOTE_VALUE_NO = 1;

    /// @notice value for an abstain vote
    uint8 public constant VOTE_VALUE_ABSTAIN = 2;

    /// @notice the number of average seconds per block
    uint256 public constant MOONBEAM_BLOCK_TIME = 12;

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// -------------------- STATE VARIABLES -------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// @dev packing these variables into a single slot saves a
    /// COLD SLOAD on propose operations.

    /// @notice gas limit for wormhole relayer, changeable incase gas
    /// prices change on external network starts at 300k gas.
    uint96 public gasLimit;

    /// @notice address of the wormhole relayer cannot be changed by owner
    /// because the relayer contract is a proxy and should never change its address
    IWormholeRelayer public wormholeRelayer;

    /// @notice The total number of proposals
    uint256 public proposalCount;

    /// @notice all live proposals, executed and cancelled proposals are removed
    /// when a new proposal is created, it is added to this set and any stale
    /// items are removed
    EnumerableSet.UintSet private _liveProposals;

    /// @notice active proposals user has proposed
    /// will automatically clear executed or cancelled
    /// proposals from set when called by user
    mapping(address user => EnumerableSet.UintSet userProposals)
        private _userLiveProposals;

    /// @notice the number of votes for a given proposal on a given chainid
    mapping(uint16 wormholeChainId => VoteCounts)
        public chainVoteCollectorVotes;

    /// @notice the total number of votes for a given proposal
    mapping(uint256 proposalId => VoteCounts) public proposals;

    /// @notice whether or not a calldata bytes is allowed for break glass guardian
    /// whether or not the calldata is whitelisted for break glass guardian
    /// functions to whitelist are:
    /// - transferOwnership to rollback address
    /// - setPendingAdmin to rollback address
    /// - setAdmin to rollback address
    /// - publishMessage that adds rollback address as trusted sender in TemporalGovernor, with calldata for each chain
    /// TODO triple check that none of the aforementioned functions have hash collisions with something that would make them dangerous
    mapping(bytes whitelistedCalldata => bool)
        public
        override whitelistedCalldatas;

    /// @notice nonces that have already been processed
    mapping(bytes32 => bool) public processedNonces;

    /// --------------------------------------------------------- ///
    /// --------------------- VOTING TOKENS --------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice reference to the xWELL token
    xWELL public xWell;

    /// @notice reference to the WELL token
    SnapshotInterface public well;

    /// @notice reference to the stkWELL token
    SnapshotInterface public stkWell;

    /// @notice reference to the WELL token distributor contract
    SnapshotInterface public distributor;

    /// --------------------------------------------------------- ///
    /// --------------------- VOTING PARAMS --------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice the period of time in which a proposal can have
    /// additional cross chain votes collected
    uint256 public override crossChainVoteCollectionPeriod;

    /// @notice the maximum number of user live proposals
    uint256 public override maxUserLiveProposals;

    /// @notice quorum needed for a proposal to pass
    uint256 public override quorum;

    /// @notice the minimum number of votes needed to propose
    uint256 public override proposalThreshold;

    /// @notice the minimum number of votes needed to propose
    uint256 public override unixTimestampVotingDelay;

    /// @notice the voting period
    uint256 public override unixTimestampVotingPeriod;

    uint256 public override blockVotingDelay;

    uint256 public override blockVotingPeriod;

    /// --------------------------------------------------------- ///
    /// ------------------------- SAFETY ------------------------ ///
    /// --------------------------------------------------------- ///

    /// @notice the governance rollback address
    address public override governanceRollbackAddress;

    /// @notice the break glass guardian address
    /// can only break glass one time, and then role is revoked
    /// and needs to be reinstated by governance
    address public override breakGlassGuardian;

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
        uint256 startTimestamp,
        uint256 endTimestamp,
        string description
    );

    /// @notice An event emitted when a proposal has been canceled
    event ProposalCanceled(uint256 id);

    /// @notice An event emitted when a proposal has been queued in the Timelock
    event ProposalQueued(uint256 id, uint256 eta);

    /// @notice An event emitted when a proposal has been executed in the Timelock
    event ProposalExecuted(uint256 id);

    /// @notice An event emitted when thee quorum votes is changed.
    event QuroumVotesChanged(uint256 oldValue, uint256 newValue);

    /// @notice An event emitted when the proposal threshold is changed.
    event ProposalThresholdChanged(uint256 oldValue, uint256 newValue);

    /// @notice An event emitted when the voting delay is changed.
    event VotingDelayChanged(uint256 oldValue, uint256 newValue);

    /// @notice An event emitted when the voting period is changed.
    event VotingPeriodChanged(uint256 oldValue, uint256 newValue);

    /// @notice An event emitted when the break glass guardian is changed.
    event BreakGlassGuardianChanged(address oldValue, address newValue);

    /// @notice An event emitted when the governance return address is changed.
    event GovernanceReturnAddressChanged(address oldValue, address newValue);

    /// @notice An event emitted when the proposal threshold has changed.
    event ProposalThresholdChanged(uint256 oldValue, uint256 newValue);

    /// @notice An event emitted when the cross chain vote collection period has changed.
    event CrossChainVoteCollectionPeriodChanged(
        uint256 oldValue,
        uint256 newValue
    );

    /// @notice An event emitted when the max user live proposals has changed.
    event UserMaxProposalsChanged(uint256 oldValue, uint256 newValue);

    /// @notice emitted when the gas limit changes on external chains
    /// @param oldGasLimit old gas limit
    /// @param newGasLimit new gas limit
    event GasLimitUpdated(uint96 oldGasLimit, uint96 newGasLimit);

    /// @notice disable the initializer to stop governance hijacking
    /// and avoid selfdestruct attacks.
    constructor() {
        _disableInitializers();
    }

    /// @notice initialize the governor contract
    /// @param _xWell address of the xWELL token
    /// @param _well address of the WELL token
    /// @param _stkWell address of the stkWELL token
    /// @param _distributor address of the WELL distributor contract
    /// @param _proposalThreshold minimum number of votes to propose
    /// @param _votingPeriod duration of voting period in blocks
    /// @param _votingDelay duration of voting delay in blocks
    /// @param _crossChainVoteCollectionPeriod duration of cross chain vote collection period in blocks
    /// @param _quorum minimum number of votes for a proposal to pass
    /// @param _maxUserLiveProposals maximum number of live proposals per user
    /// @param _pauseDuration duration of pause in blocks
    /// @param _pauseGuardian address of the pause guardian
    /// @param _trustedSenders list of trusted senders
    /// TODO add the wormhole relayer address as a parameter here
    function initialize(
        address _xWell,
        address _well,
        address _stkWell,
        address _distributor,
        uint256 _proposalThreshold,
        uint256 _votingPeriodSeconds,
        uint256 _votingDelaySeconds,
        uint256 _crossChainVoteCollectionPeriod,
        uint256 _quorum,
        uint256 _maxUserLiveProposals,
        uint128 _pauseDuration,
        address _pauseGuardian,
        address _breakGlassGuradian,
        WormholeTrustedSender.TrustedSender[] memory _trustedSenders
    ) public initializer {
        xWell = xWELL(_xWell);
        well = SnapshotInterface(_well);
        stkWell = SnapshotInterface(_stkWell);
        distributor = SnapshotInterface(_distributor);

        _setProposalThreshold(_proposalThreshold);
        _setVotingPeriod(_votingPeriodSeconds);
        _setVotingDelay(_votingDelaySeconds);
        _setCrossChainVoteCollectionPeriod(_crossChainVoteCollectionPeriod);
        _setQuorum(_quorum);
        _setMaxUserLiveProposals(_maxUserLiveProposals);
        _setBreakGlassGuardian(_breakGlassGuradian);

        __Pausable_init(); /// not really needed, but seems like good form
        _updatePauseDuration(_pauseDuration);
        _grantGuardian(_pauseGuardian); /// set the pause guardian
        _addTrustedSenders(_trustedSenders);

        _setGasLimit(300_000); /// @dev default starting gas limit for relayer
    }

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// ----------------------- MODIFIERS ----------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice modifier to restrict function access to only governor address
    modifier onlyGovernor() {
        require(
            msg.sender == address(this),
            "MultichainGovernor: only governor"
        );
        _;
    }

    /// @notice modifier to restrict function access to only break glass guardian
    /// immediately sets break glass guardian to address 0 on use
    modifier onlyBreakGlassGuardian() {
        require(
            msg.sender == breakGlassGuardian,
            "MultichainGovernor: only break glass guardian"
        );

        breakGlassGuardian = address(0);

        _;
    }

    /// @notice modifier to restrict function access to only trusted senders
    modifier onlyTrustedSender(uint16 chainId, address sender) {
        require(
            isTrustedSender(chainId, sender),
            "MultichainGovernor: only trusted sender"
        );
        _;
    }

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// ------------------- HELPER FUNCTIONS -------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    function _setCrossChainVoteCollectionPeriod(
        uint256 _crossChainVoteCollectionPeriod
    ) private {
        /// TODO maybe add constants around this so governance can't make settings too strange
        require(
            _crossChainVoteCollectionPeriod != 0,
            "MultichainGovernor: invalid vote collection period"
        );
        uint256 oldVal = crossChainVoteCollectionPeriod;
        crossChainVoteCollectionPeriod = _crossChainVoteCollectionPeriod;

        emit CrossChainVoteCollectionPeriodChanged(
            oldVal,
            _crossChainVoteCollectionPeriod
        );
    }

    function _setMaxUserLiveProposals(uint256 _maxUserLiveProposals) private {
        uint256 _oldValue = maxUserLiveProposals;
        maxUserLiveProposals = _maxUserLiveProposals;

        emit UserMaxProposalsChanged(_oldValue, _maxUserLiveProposals);
    }

    function _setQuorum(uint256 _quorum) private {
        uint256 _oldValue = quorum;
        quorum = _quorum;

        emit QuroumVotesChanged(_oldValue, _quorum);
    }

    function _setVotingDelay(uint256 _votingDelay) private {
        /// TODO maybe add constants around this so governance can't make settings too strange
        require(
            _votingDelay != 0,
            "MultichainGovernor: invalid vote delay period"
        );
        uint256 _oldValue = unixTimestampVotingDelay;
        unixTimestampVotingDelay = _votingDelay;

        emit VotingDelayChanged(_oldValue, _votingDelay);
    }

    function _setVotingPeriod(uint256 _votingPeriod) private {
        /// TODO maybe add constants around this so governance can't make settings too strange
        require(
            _votingPeriod != 0,
            "MultichainGovernor: invalid voting period"
        );
        uint256 _oldValue = unixTimestampVotingPeriod;
        unixTimestampVotingPeriod = _votingPeriod;

        emit VotingPeriodChanged(_oldValue, _votingPeriod);
    }

    function _setProposalThreshold(uint256 _proposalThreshold) private {
        uint256 oldValue = proposalThreshold;
        proposalThreshold = _proposalThreshold;

        emit ProposalThresholdChanged(oldValue, _proposalThreshold);
    }

    function _setGasLimit(uint96 newGasLimit) private {
        uint96 oldGasLimit = gasLimit;
        gasLimit = newGasLimit;

        emit GasLimitUpdated(oldGasLimit, newGasLimit);
    }

    function _setBreakGlassGuardian(address newGuardian) private {
        address oldGuardian = breakGlassGuardian;
        breakGlassGuardian = newGuardian;

        emit BreakGlassGuardianChanged(oldGuardian, newGuardian);
    }

    function _castVote(
        address voter,
        uint256 proposalId,
        uint8 voteValue
    ) internal {
        require(
            state(proposalId) == ProposalState.Active,
            "GovernorArtemis::_castVote: voting is closed"
        );

        Proposal storage proposal = proposals[proposalId];

        if (proposal.startBlock == 0) {
            proposal.startBlock = block.number - 1;
            emit StartBlockSet(proposalId, block.number);
        }

        Receipt storage receipt = proposal.receipts[voter];

        require(
            receipt.hasVoted == false,
            "GovernorArtemis::_castVote: voter already voted"
        );

        uint256 votes = getVotes(
            voter,
            proposal.startTimestamp,
            proposal.startBlock
        );

        if (voteValue == VOTE_VALUE_YES) {
            proposal.forVotes = proposal.forVotes + votes;
        } else if (voteValue == VOTE_VALUE_NO) {
            proposal.againstVotes = proposal.againstVotes + votes;
        } else if (voteValue == VOTE_VALUE_ABSTAIN) {
            proposal.abstainVotes = proposal.abstainVotes + votes;
        } else {
            // Catch all. If an above case isn't matched then the value is not valid.
            revert("GovernorArtemis::_castVote: invalid vote value");
        }

        // Increase total votes
        proposal.totalVotes = proposal.totalVotes + votes;

        receipt.hasVoted = true;
        receipt.voteValue = voteValue;
        receipt.votes = votes;

        emit VoteCast(voter, proposalId, voteValue, votes);
    }

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// -------------------- VIEW FUNCTIONS --------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice returns the number of live proposals a user has
    /// a proposal is considered live if it is active or pending
    /// @param user The address of the user to check
    function currentUserLiveProposals(
        address user
    ) public view returns (uint256) {
        uint256[] memory userProposals = _userLiveProposals[user].values();

        uint256 totalLiveProposals = 0;
        for (uint256 i = 0; i < userProposals.length; i++) {
            ProposalState proposalsState = state(userProposals[i]);
            if (
                proposalsState == ProposalState.Active ||
                proposalsState == ProposalState.Pending ||
                proposalsState == ProposalState.CrossChainVoteCollection
            ) {
                totalLiveProposals++;
            }
        }

        return totalLiveProposals;
    }

    /// @notice returns all proposals a user has that are live
    /// a proposal is considered live if it is active or pending
    /// @param user The address of the user to check
    function getUserLiveProposals(
        address user
    ) public view returns (uint256[] memory) {
        uint256[] memory userProposals = new uint256[](
            currentUserLiveProposals(user)
        );
        uint256[] memory allUserProposals = _userLiveProposals[user].values();
        uint256 userLiveProposalIndex = 0;

        unchecked {
            for (uint256 i = 0; i < allUserProposals.length; i++) {
                ProposalState proposalsState = state(userProposals[i]);

                if (
                    proposalsState == ProposalState.Active ||
                    proposalsState == ProposalState.Pending ||
                    proposalsState == ProposalState.CrossChainVoteCollection
                ) {
                    userProposals[userLiveProposalIndex] = allUserProposals[i];
                    userLiveProposalIndex++;
                }
            }
        }

        return userProposals;
    }

    /// returns the total voting power for an address at a given block number and timestamp
    /// @param account The address of the account to check
    /// @param timestamp The unix timestamp in seconds to check the balance at
    /// @param blockNumber The block number to check the balance at
    function getVotes(
        address account,
        uint256 timestamp,
        uint256 blockNumber
    ) public view returns (uint256) {
        uint256 wellVotes = well.getPriorVotes(account, blockNumber);
        uint256 stkWellVotes = stkWell.getPriorVotes(account, blockNumber);
        uint256 distributorVotes = distributor.getPriorVotes(
            account,
            blockNumber
        );

        uint256 xWellVotes = xWell.getPastVotes(account, timestamp);

        return xWellVotes + stkWellVotes + distributorVotes + wellVotes;
    }

    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////
    //// ------------- View Functions ----------------- ////
    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////

    /// @notice override with a mapping
    function chainAddressVotes(
        uint256 proposalId,
        uint256 chainId,
        address voteGatheringAddress
    ) external view returns (VoteCounts memory) {}

    /// returns whether or not the user is a vote collector contract
    /// and can vote on a given chain
    function isCrossChainVoteCollector(
        uint16 chainId,
        address voteCollector
    ) external view returns (bool) {
        return isTrustedSender(chainId, voteCollector);
    }

    function isCrossChainVoteCollector(
        uint16 chainId,
        bytes32 voteCollector
    ) external view returns (bool) {
        return isTrustedSender(chainId, voteCollector);
    }

    /// @notice The total number of proposals
    function state(uint256 proposalId) public view returns (ProposalState) {
        require(
            proposalCount >= proposalId && proposalId > 0,
            "MultichainGovernor::state: invalid proposal id"
        );

        Proposal storage proposal = proposals[proposalId];

        // First check if the proposal cancelled.
        if (proposal.canceled) {
            return ProposalState.Canceled;
            // Then check if the proposal is pending or active, in which case nothing else can be determined at this time.
        } else if (block.timestamp <= proposal.startTimestamp) {
            return ProposalState.Pending;
        } else if (block.timestamp <= proposal.endTimestamp) {
            return ProposalState.Active;
            // Then, check if the proposal is in cross chain vote collection period
        } else if (
            // TODO test this logic
            block.timestamp <= proposal.crossChainVoteCollectionEndTimestamp
        ) {
            return ProposalState.CrossChainVoteCollection;
            /// any from here on out means the proposal is no longer active, and no change in votes can be registered.
            // Then, check if the proposal is defeated. To hit this case, either (1) majority of yay/nay votes were nay or
            // (2) total votes was less than the quorum amount.
        } else if (
            proposal.forVotes <= proposal.againstVotes ||
            proposal.totalVotes < quorumVotes
        ) {
            return ProposalState.Defeated;
        } else if (proposal.eta == 0) {
            return ProposalState.Succeeded;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        }
    }

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
    ) external override returns (uint256) {
        /// get user voting power from all voting sources
        require(
            getVotes(msg.sender, block.timestamp - 1, block.number - 1) >=
                proposalThreshold,
            "MultichainGovernor: proposer votes below proposal threshold"
        );
        require(
            targets.length == values.length &&
                targets.length == calldatas.length,
            "MultichainGovernor: proposal function information arity mismatch"
        );
        require(
            targets.length != 0,
            "MultichainGovernor: must provide actions"
        );
        require(
            bytes(description).length > 0,
            "MultichainGovernor: description can not be empty"
        );

        /// TODO add call to _syncUserLiveProposals(msg.sender) here
        /// TODO add call to _syncTotalLiveProposals(msg.sender) here

        uint256 userProposalCount = currentUserLiveProposals(msg.sender);

        require(
            userProposalCount < maxUserLiveProposals,
            "MultichainGovernor: too many live proposals for this user"
        );

        /// TODO define these block state variables
        uint256 startTimestamp = block.timestamp + unixTimestampVotingDelay;
        uint256 startBlock = block.number + blockVotingDelay;

        uint256 endTimestamp = block.timestamp +
            unixTimestampVotingPeriod +
            unixTimestampVotingDelay;
        uint256 endBlock = block.number + blockVotingPeriod + blockVotingDelay;

        /// TODO add cross chain vote collection period assignment here

        proposalCount++;

        Proposal storage newProposal = proposals[proposalCount];
        newProposal.id = proposalCount;
        newProposal.proposer = msg.sender;
        newProposal.eta = 0;
        newProposal.targets = targets;
        newProposal.values = values;
        newProposal.calldatas = calldatas;

        newProposal.startBlock = startBlock;
        newProposal.startTimestamp = startTimestamp;

        newProposal.endBlock = endBlock;
        newProposal.endTimestamp = endTimestamp;

        newProposal.forVotes = 0;
        newProposal.againstVotes = 0;
        newProposal.abstainVotes = 0;
        newProposal.totalVotes = 0;
        newProposal.canceled = false;
        newProposal.executed = false;

        latestProposalIds[newProposal.proposer] = proposalCount;

        /// post proposal checks, should never be possible
        /// essentially assertions with revert messages
        require(
            _userLiveProposals[msg.sender].add(proposalCount),
            "MultichainGovernor: user cannot add the same proposal twice"
        );

        require(
            _liveProposals.add(proposalCount),
            "MultichainGovernor: cannot add the same proposal twice to global set"
        );

        emit ProposalCreated(
            newProposal.id,
            msg.sender,
            targets,
            values,
            calldatas,
            startTimestamp,
            endTimestamp,
            description
        );

        return newProposal.id;
    }

    function execute(uint256 proposalId) external override {
        require(
            state(proposalId) == ProposalState.Succeeded,
            "GovernorArtemis::execute: proposal can only be executed if it is Succeeded"
        );

        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;

        /// TODO sync total proposals by removing this proposal ID from the live proposals set
        /// TODO sync user proposals by removing this proposal ID from the user's live proposals

        unchecked {
            /// TODO change to functionCallWithValue, ignore returned bytes memory
            for (uint256 i = 0; i < proposal.targets.length; i++) {
                (bool success, string memory error) = proposal.targets[i].call{
                    value: proposal.values[i]
                }(proposal.calldatas[i]);

                if (!success) {
                    revert(error);
                }
            }
        }

        emit ProposalExecuted(proposalId);
    }

    /// @dev callable only by the proposer, cancels proposal if it has not been executed
    function proposerCancel(uint256 proposalId) external override {}

    /// @dev callable by anyone, succeeds in cancellation if user has less votes than proposal threshold
    /// at the current point in time.
    /// reverts otherwise.
    function permissionlessCancel(uint256 proposalId) external override {}

    /// @dev allows user to cast vote for a proposal
    function castVote(uint256 proposalId, uint8 voteValue) external override {}

    /// @dev allows votes from external chains to be counted
    /// calls wormhole core to decode VAA, ensures validity of sender
    function collectCrosschainVote(
        bytes memory payload,
        bytes[] memory, // additionalVaas
        bytes32 senderAddress,
        uint16 sourceChain,
        bytes32 nonce
    ) external override {
        require(
            msg.sender == address(wormholeRelayer),
            "WormholeBridge: only relayer allowed"
        );

        require(
            !processedNonces[nonce],
            "MultichainGovernor: nonce already processed"
        );

        processedNonces[nonce] = true;

        require(
            isTrustedSender(sourceChain, senderAddress),
            "MultichainGovernor: invalid sender"
        );

        /// payload should be 4 uint256s
        require(
            payload.length == 128,
            "MultichainGovernor: invalid payload length"
        );

        /// TODO integrate logic to ensure cross chain vote collection contract can only relay vote counts once for a given proposal

        (
            uint256 proposalId,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 abstainVotes
        ) = abi.decode(payload, (uint256, uint256, uint256, uint256));

        require(
            state(proposalId) == ProposalState.CrossChainVoteCollection,
            "MultichainGovernor: proposal not in cross chain vote collection period"
        );

        VoteCounts storage voteCounts = chainVoteCollectorVotes[sourceChain];

        voteCounts.forVotes = forVotes;
        voteCounts.againstVotes = againstVotes;
        voteCounts.abstainVotes = abstainVotes;

        /// TODO update the proposal state to contain these votes by modifying the proposal struct
        Proposal storage proposal = proposals[proposalId];

        proposal.forVotes += forVotes;
        proposal.againstVotes += againstVotes;
        proposal.abstainVotes += abstainVotes;

        emit CrossChainVoteCollected(
            proposalId,
            sourceChain,
            forVotes,
            againstVotes,
            abstainVotes
        );
    }

    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////
    /// ---------- governance only functions ---------- ////
    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////

    /// updates the proposal threshold
    function updateProposalThreshold(
        uint256 newProposalThreshold
    ) external override onlyGovernor {
        _setProposalThreshold(newProposalThreshold);
    }

    /// updates the maximum user live proposals
    function updateMaxUserLiveProposals(
        uint256 newMaxLiveProposals
    ) external override onlyGovernor {
        _setMaxUserLiveProposals(newMaxLiveProposals);
    }

    /// updates the quorum
    function updateQuorum(uint256 newQuorum) external override onlyGovernor {
        _setQuorum(newQuorum);
    }

    /// TODO change to accept both block and timestamp and then validate that they are within a certain range
    /// i.e. the block number * block time is equals the timestamp
    /// updates the voting period
    function updateVotingPeriodTimestamp(
        uint256 newVotingPeriod
    ) external override onlyGovernor {
        _setVotingPeriod(newVotingPeriod);
    }

    /// updates the voting delay
    function updateVotingDelayTimestamp(
        uint256 newVotingDelay
    ) external override onlyGovernor {
        _setVotingDelay(newVotingDelay);
    }

    /// updates the cross chain voting collection period
    function updateCrossChainVoteCollectionPeriod(
        uint256 newCrossChainVoteCollectionPeriod
    ) external override onlyGovernor {
        _setCrossChainVoteCollectionPeriod(newCrossChainVoteCollectionPeriod);
    }

    function setBreakGlassGuardian(
        address newGuardian
    ) external override onlyGovernor {
        _setBreakGlassGuardian(newGuardian);
    }

    /// TODO should this be updateable?
    function setGovernanceReturnAddress(
        address newAddress
    ) external override onlyGovernor {}

    //// @notice array lengths must add up
    /// values must sum to msg.value to ensure guardian cannot steal funds
    /// calldata must be whitelisted
    /// only break glass guardian can call, once, and when they do, their role is revoked
    /// before any external functions are called. This prevents reentrancy/multiple uses
    /// by a single guardian.
    function executeBreakGlass(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) external payable override onlyBreakGlassGuardian {
        require(
            targets.length == values.length &&
                targets.length == calldatas.length,
            "MultichainGovernor: arity mismatch"
        );

        uint256 totalValue = 0;
        for (uint256 i = 0; i < values.length; ) {
            totalValue += values[i];

            unchecked {
                i++;
            }
        }

        require(
            totalValue == msg.value,
            "MultichainGovernor: values must sum to msg.value"
        );

        unchecked {
            for (uint256 i = 0; i < calldatas.length; i++) {
                require(
                    whitelistedCalldatas[calldatas[i]],
                    "MultichainGovernor: calldata not whitelisted"
                );
            }
        }

        /// TODO make the actual calls, emit the event
    }
}
