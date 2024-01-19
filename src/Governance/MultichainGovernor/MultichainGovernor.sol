pragma solidity 0.8.19;

import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {Address} from "@openzeppelin-contracts/contracts/utils/Address.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Constants} from "@protocol/Governance/MultichainGovernor/Constants.sol";
import {SnapshotInterface} from "@protocol/Governance/MultichainGovernor/SnapshotInterface.sol";
import {IMultichainGovernor} from "@protocol/Governance/MultichainGovernor/IMultichainGovernor.sol";
import {ConfigurablePauseGuardian} from "@protocol/xWELL/ConfigurablePauseGuardian.sol";
import {WormholeBridgeBase} from "@protocol/wormhole/WormholeBridgeBase.sol";

/// WARNING: this contract is at high risk of running over bytecode size limit
///   we may need to split things out into multiple contracts, so keep things as
///   concise as possible.

/// @notice pauseable by the guardian
/// @notice upgradeable, constructor disables implementation

/// Note:
/// - moonbeam block times are consistently 12 seconds with few exceptions https://moonscan.io/chart/blocktime
/// this means that a timestamp can be converted to a block number with a high degree of accuracy
contract MultichainGovernor is IMultichainGovernor, ConfigurablePauseGuardian, WormholeBridgeBase {
    using EnumerableSet for EnumerableSet.UintSet;
    using Address for address;

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// -------------------- STATE VARIABLES -------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice The total number of proposals
    uint256 public proposalCount;

    /// TODO possible to remove this as there is no max live proposals?
    /// @notice all live proposals, executed and cancelled proposals are removed
    /// when a new proposal is created, it is added to this set and any stale
    /// items are removed
    EnumerableSet.UintSet private _liveProposals;

    /// @notice active proposals user has proposed
    /// will automatically clear executed or cancelled
    /// proposals from set when called by user
    mapping(address user => EnumerableSet.UintSet userProposals) private _userLiveProposals;

    /// @notice the number of votes for a given proposal on a given chainid
    mapping(uint16 wormholeChainId => VoteCounts) public chainVoteCollectorVotes;

    /// @notice the proposal information for a given proposal
    mapping(uint256 proposalId => Proposal) public proposals;

    /// @notice whether or not a calldata bytes is allowed for break glass guardian
    /// whether or not the calldata is whitelisted for break glass guardian
    /// functions to whitelist are:
    /// - transferOwnership to rollback address
    /// - setPendingAdmin to rollback address
    /// - setAdmin to rollback address
    /// - publishMessage that adds rollback address as trusted sender in TemporalGovernor, with calldata for each chain
    /// TODO triple check that none of the aforementioned functions have hash collisions with something that would make them dangerous
    mapping(bytes whitelistedCalldata => bool) public override whitelistedCalldatas;

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
    /// cross chain votes collected.
    /// if this period is changed in a governance proposal, it will not impact
    /// current or in flight proposal state, only the proposals that are created
    /// after this parameter is updated.
    uint256 public override crossChainVoteCollectionPeriod;

    /// @notice the maximum number of user live proposals
    /// if governance votes to decrease this number, and user is already at the maximum
    /// proposal count, they will not be able to propose again until they have less
    /// than the new maximum.
    uint256 public override maxUserLiveProposals;

    /// @notice quorum needed for a proposal to pass
    /// if multiple governance proposals are in flight, and the first one to execute
    /// changes quorum, then this new quorum will go into effect on the next proposal.
    uint256 public override quorum;

    /// @notice the minimum number of votes needed to propose
    uint256 public override proposalThreshold;

    /// @notice the minimum number of votes needed to propose
    /// changing this variable only affects the proposals created after the change
    uint256 public override votingDelay;

    /// @notice the voting period
    /// changing this variable only affects the proposals created after the change
    uint256 public override votingPeriod;

    /// --------------------------------------------------------- ///
    /// ------------------------- SAFETY ------------------------ ///
    /// --------------------------------------------------------- ///

    /// @notice the governance rollback address
    address public override governanceRollbackAddress;

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
        /// well token address
        address well;
        /// xWell token address
        address xWell;
        /// stkWell token address
        address stkWell;
        /// crowdsale token distributor address
        address distributor;
        /// proposal threshold
        uint256 proposalThreshold;
        /// voting period in seconds
        uint256 votingPeriodSeconds;
        /// voting period delay in seconds
        uint256 votingDelaySeconds;
        /// cross chain voting collection period in seconds
        uint256 crossChainVoteCollectionPeriod;
        /// number of total votes required to meet quorum
        uint256 quorum;
        /// maximum number of live proposals a user can have at a single point in time
        uint256 maxUserLiveProposals;
        /// pause duration in seconds
        uint128 pauseDuration;
        /// pause guardian address
        address pauseGuardian;
        /// break glass guardian address
        address breakGlassGuardian;
        /// wormhole relayer
        address wormholeRelayer;
        /// trusted senders that can relay messages to this contract
        TrustedSender[] trustedSenders;
    }

    /// @notice initialize the governor contract
    /// @param initData initialization data
    function initialize(InitializeData memory initData) public initializer {
        xWell = xWELL(initData.xWell);
        well = SnapshotInterface(initData.well);
        stkWell = SnapshotInterface(initData.stkWell);
        distributor = SnapshotInterface(initData.distributor);

        _setProposalThreshold(initData.proposalThreshold);
        _setVotingPeriod(initData.votingPeriodSeconds);
        _setVotingDelay(initData.votingDelaySeconds);
        _setCrossChainVoteCollectionPeriod(initData.crossChainVoteCollectionPeriod);
        _setQuorum(initData.quorum);
        _setMaxUserLiveProposals(initData.maxUserLiveProposals);
        _setBreakGlassGuardian(initData.breakGlassGuardian);

        __Pausable_init();

        /// not really needed, but seems like good form
        _updatePauseDuration(initData.pauseDuration);

        /// set the pause guardian
        _grantGuardian(initData.pauseGuardian);

        _addWormholeRelayer(address(initData.wormholeRelayer));
    }

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// ----------------------- MODIFIERS ----------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice modifier to restrict function access to only governor address
    modifier onlyGovernor() {
        require(msg.sender == address(this), "MultichainGovernor: only governor");
        _;
    }

    /// @notice modifier to restrict function access to only break glass guardian
    /// immediately sets break glass guardian to address 0 on use, and emits the
    /// BreakGlassGuardianChanged event
    modifier onlyBreakGlassGuardian() {
        require(msg.sender == breakGlassGuardian, "MultichainGovernor: only break glass guardian");

        emit BreakGlassGuardianChanged(breakGlassGuardian, address(0));

        breakGlassGuardian = address(0);

        _;
    }

    /// @notice modifier to restrict function access to only trusted senders
    modifier onlyTrustedSender(uint16 chainId, address sender) {
        require(isTrustedSender(chainId, sender), "MultichainGovernor: only trusted sender");
        _;
    }

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// ------------------- HELPER FUNCTIONS -------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    function _setCrossChainVoteCollectionPeriod(uint256 _crossChainVoteCollectionPeriod) private {
        /// TODO maybe add constants around this so governance can't make settings too strange
        require(_crossChainVoteCollectionPeriod != 0, "MultichainGovernor: invalid vote collection period");
        uint256 oldVal = crossChainVoteCollectionPeriod;
        crossChainVoteCollectionPeriod = _crossChainVoteCollectionPeriod;

        emit CrossChainVoteCollectionPeriodChanged(oldVal, _crossChainVoteCollectionPeriod);
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
        require(_votingDelay != 0, "MultichainGovernor: invalid vote delay period");
        uint256 _oldValue = votingDelay;
        votingDelay = _votingDelay;

        emit VotingDelayChanged(_oldValue, _votingDelay);
    }

    function _setVotingPeriod(uint256 _votingPeriod) private {
        /// TODO maybe add constants around this so governance can't make settings too strange
        require(_votingPeriod != 0, "MultichainGovernor: invalid voting period");
        uint256 _oldValue = votingPeriod;
        votingPeriod = _votingPeriod;

        emit VotingPeriodChanged(_oldValue, _votingPeriod);
    }

    function _setProposalThreshold(uint256 _proposalThreshold) private {
        uint256 oldValue = proposalThreshold;
        proposalThreshold = _proposalThreshold;

        emit ProposalThresholdChanged(oldValue, _proposalThreshold);
    }

    function _setBreakGlassGuardian(address newGuardian) private {
        address oldGuardian = breakGlassGuardian;
        breakGlassGuardian = newGuardian;

        emit BreakGlassGuardianChanged(oldGuardian, newGuardian);
    }

    function _castVote(address voter, uint256 proposalId, uint8 voteValue) internal {
        require(state(proposalId) == ProposalState.Active, "MultichainGovernor: voting is closed");
        require(voteValue <= Constants.VOTE_VALUE_ABSTAIN, "MultichainGovernor: invalid vote value");

        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = proposal.receipts[voter];

        require(receipt.hasVoted == false, "MultichainGovernor: voter already voted");

        uint256 votes = getVotes(voter, proposal.startTimestamp, proposal.startBlock);

        if (voteValue == Constants.VOTE_VALUE_YES) {
            proposal.forVotes += proposal.forVotes;
        } else if (voteValue == Constants.VOTE_VALUE_NO) {
            proposal.againstVotes += proposal.againstVotes;
        } else if (voteValue == Constants.VOTE_VALUE_ABSTAIN) {
            proposal.abstainVotes += proposal.abstainVotes;
        } else {
            /// TODO question for SMT solver or Certora, should never be reachable
            assert(false);
        }

        // Increase total votes
        proposal.totalVotes = proposal.totalVotes + votes;

        receipt.hasVoted = true;
        receipt.voteValue = voteValue;
        receipt.votes = votes;

        emit VoteCast(voter, proposalId, voteValue, votes);
    }

    /// build out a FSM or CFG of this function and see if its functionality
    /// can be combined into the _syncTotalLiveProposals function
    /// @notice sync up user current total live proposals count
    /// @param user the user to sync
    function _syncUserLiveProposals(address user) private {
        uint256[] memory userProposals = _userLiveProposals[user].values();

        unchecked {
            for (uint256 i = 0; i < userProposals.length; i++) {
                ProposalState proposalsState = state(userProposals[i]);
                if (
                    proposalsState == ProposalState.Defeated || proposalsState == ProposalState.Canceled
                        || proposalsState == ProposalState.Executed || proposalsState == ProposalState.Invalid
                ) {
                    _removeFromSet(
                        _userLiveProposals[user],
                        userProposals[i],
                        "MultichainGovernor: could not remove proposal from user live proposals"
                    );
                }
            }
        }
    }

    /// we must sync the user live proposals before we sync the total live
    /// proposals, otherwise when the user calls in to sync it could revert
    function _syncTotalLiveProposals() private {
        uint256[] memory allProposals = _liveProposals.values();

        unchecked {
            for (uint256 i = 0; i < allProposals.length; i++) {
                ProposalState proposalsState = state(allProposals[i]);
                if (
                    proposalsState == ProposalState.Defeated || proposalsState == ProposalState.Canceled
                        || proposalsState == ProposalState.Executed || proposalsState == ProposalState.Invalid
                ) {
                    /// remove proposal from user before removing from the global set
                    /// this ensures that the user can sync their live proposals and propose
                    /// new proposals
                    _syncUserLiveProposals(proposals[allProposals[i]].proposer);
                    _removeFromSet(
                        _liveProposals,
                        allProposals[i],
                        "MultichainGovernor: could not remove proposal from live proposals"
                    );
                }
            }
        }
    }

    /// @notice removes a proposal item from a set
    /// could be either a user proposal or total live proposal pointer
    /// @param set the set to remove from
    /// @param proposalId the proposal id to remove
    /// @param errorMessage the error message to revert with if the removal fails
    function _removeFromSet(EnumerableSet.UintSet storage set, uint256 proposalId, string memory errorMessage)
        private
    {
        require(set.remove(proposalId), errorMessage);
    }

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// -------------------- VIEW FUNCTIONS --------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    function liveProposals() external view override returns (uint256[] memory) {
        uint256 liveProposalCount = getNumLiveProposals();
        uint256[] memory liveProposalIds = new uint256[](liveProposalCount);

        uint256[] memory allProposals = _liveProposals.values();
        uint256 liveProposalIndex = 0;
        for (uint256 i = 0; i < allProposals.length; i++) {
            ProposalState proposalsState = state(allProposals[i]);
            if (
                proposalsState == ProposalState.Active || proposalsState == ProposalState.Pending
                    || proposalsState == ProposalState.CrossChainVoteCollection
            ) {
                liveProposalIds[liveProposalIndex] = allProposals[i];
                liveProposalIndex++;
            }
        }

        return liveProposalIds;
    }

    function getNumLiveProposals() public view returns (uint256 count) {
        uint256[] memory allProposals = _liveProposals.values();

        for (uint256 i = 0; i < allProposals.length;) {
            ProposalState proposalsState = state(allProposals[i]);
            if (
                proposalsState == ProposalState.Active || proposalsState == ProposalState.Pending
                    || proposalsState == ProposalState.CrossChainVoteCollection
            ) {
                count++;
            }
        }
    }

    /// @notice returns the number of live proposals a user has
    /// a proposal is considered live if it is active or pending
    /// @param user The address of the user to check
    function currentUserLiveProposals(address user) public view returns (uint256) {
        uint256[] memory userProposals = _userLiveProposals[user].values();

        uint256 totalLiveProposals = 0;
        for (uint256 i = 0; i < userProposals.length; i++) {
            ProposalState proposalsState = state(userProposals[i]);
            if (
                proposalsState == ProposalState.Active || proposalsState == ProposalState.Pending
                    || proposalsState == ProposalState.CrossChainVoteCollection
            ) {
                totalLiveProposals++;
            }
        }

        return totalLiveProposals;
    }

    /// @notice returns all proposals a user has that are live
    /// a proposal is considered live if it is active or pending
    /// @param user The address of the user to check
    function getUserLiveProposals(address user) public view returns (uint256[] memory) {
        uint256[] memory userProposals = new uint256[](
            currentUserLiveProposals(user)
        );
        uint256[] memory allUserProposals = _userLiveProposals[user].values();
        uint256 userLiveProposalIndex = 0;

        unchecked {
            for (uint256 i = 0; i < allUserProposals.length; i++) {
                ProposalState proposalsState = state(userProposals[i]);

                if (
                    proposalsState == ProposalState.Active || proposalsState == ProposalState.Pending
                        || proposalsState == ProposalState.CrossChainVoteCollection
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
    function getVotes(address account, uint256 timestamp, uint256 blockNumber) public view returns (uint256) {
        uint256 wellVotes = well.getPriorVotes(account, blockNumber);
        uint256 stkWellVotes = stkWell.getPriorVotes(account, blockNumber);
        uint256 distributorVotes = distributor.getPriorVotes(account, blockNumber);

        uint256 xWellVotes = xWell.getPastVotes(account, timestamp);

        return xWellVotes + stkWellVotes + distributorVotes + wellVotes;
    }

    /// @notice override with a mapping
    function chainAddressVotes(uint256 proposalId, uint256 chainId, address voteGatheringAddress)
        external
        view
        returns (VoteCounts memory)
    {}

    /// returns whether or not the user is a vote collector contract
    /// and can vote on a given chain
    function isCrossChainVoteCollector(uint16 chainId, address voteCollector) external view override returns (bool) {
        return isTrustedSender(chainId, voteCollector);
    }

    function isCrossChainVoteCollector(uint16 chainId, bytes32 voteCollector) external view returns (bool) {
        return isTrustedSender(chainId, voteCollector);
    }

    /// @notice The total number of proposals
    function state(uint256 proposalId) public view returns (ProposalState) {
        require(proposalCount >= proposalId && proposalId > 0, "MultichainGovernor: invalid proposal id");

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
            block
                // TODO test this logic
                .timestamp <= proposal.crossChainVoteCollectionEndTimestamp
        ) {
            return ProposalState.CrossChainVoteCollection;
            /// any from here on out means the proposal is no longer active, and no change in votes can be registered.
            // Then, check if the proposal is defeated. To hit this case, either (1) majority of yay/nay votes were nay or
            // (2) total votes was less than the quorum amount.
        } else if (proposal.forVotes <= proposal.againstVotes || proposal.totalVotes < quorum) {
            return ProposalState.Defeated;
        } else if (proposal.eta == 0) {
            return ProposalState.Succeeded;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        } else {
            /// TODO this should never be reachable, ask SMT solver or certora if it is
            assert(false);
            return ProposalState.Invalid;
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
    ) external payable override returns (uint256) {
        require(bridgeCostAll() == msg.value, "MultichainGovernor: invalid proposal cost");
        /// get user voting power from all voting sources
        require(
            getVotes(msg.sender, block.timestamp - 1, block.number - 1) >= proposalThreshold,
            "MultichainGovernor: proposer votes below proposal threshold"
        );
        require(
            targets.length == values.length && targets.length == calldatas.length,
            "MultichainGovernor: proposal function information arity mismatch"
        );
        require(targets.length != 0, "MultichainGovernor: must provide actions");
        require(bytes(description).length > 0, "MultichainGovernor: description can not be empty");
        _syncUserLiveProposals(msg.sender);
        /// remove inactive proposal from user list
        _syncTotalLiveProposals();
        /// remove inactive proposals
        {
            uint256 userProposalCount = currentUserLiveProposals(msg.sender);
            require(
                userProposalCount < maxUserLiveProposals, "MultichainGovernor: too many live proposals for this user"
            );
        }
        proposalCount++;
        Proposal storage newProposal = proposals[proposalCount];
        uint256 startTimestamp = block.timestamp + votingDelay;
        uint256 endTimestamp = block.timestamp + votingPeriod + votingDelay;
        {
            uint256 crossChainVoteCollectionEndTimestamp = endTimestamp + crossChainVoteCollectionPeriod;
            {
                uint256 blockVotingPeriod = votingPeriod / Constants.MOONBEAM_BLOCK_TIME;
                uint256 blockVotingDelay = votingDelay / Constants.MOONBEAM_BLOCK_TIME;
                /// pop off the stack
                uint256 startBlock = block.number + blockVotingDelay;
                uint256 endBlock = block.number + blockVotingPeriod + blockVotingDelay;
                /// TODO add cross chain vote collection period assignment here
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
            }
            newProposal.crossChainVoteCollectionEndTimestamp = crossChainVoteCollectionEndTimestamp;
            newProposal.forVotes = 0;
            newProposal.againstVotes = 0;
            newProposal.abstainVotes = 0;
            newProposal.totalVotes = 0;
            newProposal.canceled = false;
            newProposal.executed = false;
            /// post proposal checks, should never be possible to revert
            /// essentially assertions with revert messages
            require(
                _userLiveProposals[msg.sender].add(proposalCount),
                "MultichainGovernor: user cannot add the same proposal twice"
            );
            require(
                _liveProposals.add(proposalCount),
                "MultichainGovernor: cannot add the same proposal twice to global set"
            );
            bytes memory payload =
                abi.encode(proposalCount, startTimestamp, endTimestamp, crossChainVoteCollectionEndTimestamp);

            uint256 chainsLength = _targetChains.length();
            /// call relayer with information about proposal
            /// iterate over chainConfigs and send messages to each of them
            for (uint256 i = 0; i < chainsLength;) {
                _bridgeOut(uint16(_targetChains.at(i)), payload);
                unchecked {
                    i++;
                }
            }
        }

        emit ProposalCreated(
            newProposal.id, msg.sender, targets, values, calldatas, startTimestamp, endTimestamp, description
        );

        return newProposal.id;
    }

    function execute(uint256 proposalId) external override {
        require(
            state(proposalId) == ProposalState.Succeeded,
            "MultichainGovernor: proposal can only be executed if it is Succeeded"
        );

        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;

        /// TODO sync total proposals by removing this proposal ID from the live proposals set
        /// TODO sync user proposals by removing this proposal ID from the user's live proposals

        unchecked {
            /// TODO change to functionCallWithValue, ignore returned bytes memory
            for (uint256 i = 0; i < proposal.targets.length; i++) {
                proposal.targets[i].functionCallWithValue(
                    proposal.calldatas[i], proposal.values[i], "MultichainGovernor: execute call failed"
                );
            }
        }

        emit ProposalExecuted(proposalId);
    }

    /// TODO consolidate cancellation functions to allow cancellation in these flows:
    ///  - proposer cancels
    ///  - permissionless cancel, user voting power currently drops below threshold
    ///  - permissionless cancel, contract is paused

    /// @dev callable only by the proposer, cancels proposal if it has not been executed
    function proposerCancel(uint256 proposalId) external override {}

    /// @dev callable by anyone, succeeds in cancellation if user has less votes than proposal threshold
    /// at the current point in time, or the contract is paused.
    /// Otherwise reverts.
    function permissionlessCancel(uint256 proposalId) external override {}

    /// @dev allows user to cast vote for a proposal
    function castVote(uint256 proposalId, uint8 voteValue) external override {}

    /// @dev allows votes from external chains to be counted
    /// calls wormhole core to decode VAA, ensures validity of sender
    // @param sourceChain the chain id of the source chain
    // @param payload contains proposalId, forVotes, againstVotes, abstainVotes
    function _bridgeIn(uint16 sourceChain, bytes memory payload) internal override {
        /// payload should be 4 uint256s
        require(payload.length == 128, "MultichainGovernor: invalid payload length");

        /// TODO only allow relayer creation of vote counts once on vote collector
        /// contract and only if there is at least 1 value that is non zero
        /// if there have been no votes cast for a particular proposal, do not allow
        /// the relaying of any information cross chain
        VoteCounts storage voteCounts = chainVoteCollectorVotes[sourceChain];

        /// logic to ensure cross chain vote collection contract can only relay vote counts once for a given proposal
        /// if all of these values are zero, then the values have not been set yet
        require(
            voteCounts.forVotes == 0 && voteCounts.againstVotes == 0 && voteCounts.abstainVotes == 0,
            "MultichainGovernor: vote already collected"
        );

        (uint256 proposalId, uint256 forVotes, uint256 againstVotes, uint256 abstainVotes) =
            abi.decode(payload, (uint256, uint256, uint256, uint256));

        require(
            state(proposalId) == ProposalState.CrossChainVoteCollection,
            "MultichainGovernor: proposal not in cross chain vote collection period"
        );

        voteCounts.forVotes = forVotes;
        voteCounts.againstVotes = againstVotes;
        voteCounts.abstainVotes = abstainVotes;

        /// update the proposal state to contain these votes by modifying the proposal struct
        Proposal storage proposal = proposals[proposalId];

        proposal.forVotes += forVotes;
        proposal.againstVotes += againstVotes;
        proposal.abstainVotes += abstainVotes;

        emit CrossChainVoteCollected(proposalId, sourceChain, forVotes, againstVotes, abstainVotes);
    }

    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////
    /// ---------- governance only functions ---------- ////
    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////

    function updateApprovedCalldata(bytes calldata data, bool approved) external onlyGovernor {
        if (approved == true) {
            require(!whitelistedCalldatas[data], "MultichainGovernor: calldata already approved");
        } else {
            require(whitelistedCalldatas[data], "MultichainGovernor: calldata already not approved");
        }

        whitelistedCalldatas[data] = approved;

        emit CalldataApprovalUpdated(data, approved);
    }

    /// @notice remove trusted senders from external chains
    /// @param _trustedSenders array of trusted senders to remove
    function removeTrustedSenders(TrustedSender[] memory _trustedSenders) external onlyGovernor {
        _removeTrustedSenders(_trustedSenders);
    }

    /// @notice add trusted senders from external chains
    /// @param _trustedSenders array of trusted senders to add
    function addTrustedSenders(TrustedSender[] memory _trustedSenders) external onlyGovernor {
        _addTrustedSenders(_trustedSenders);
    }

    /// @notice add map of target addresses for external chains
    /// @dev there is no check here to ensure there isn't an existing configuration
    /// ensure the proper add or remove is being called when using this function
    /// @param _chainConfig array of chainids to addresses to add
    function addTargetAddresses(TrustedSender[] memory _chainConfig) external onlyGovernor {
        _addTargetAddresses(_chainConfig);
    }

    /// @notice updates the proposal threshold
    /// @param newProposalThreshold the new proposal threshold
    function updateProposalThreshold(uint256 newProposalThreshold) external override onlyGovernor {
        _setProposalThreshold(newProposalThreshold);
    }

    /// @notice updates the maximum user live proposals
    /// @param newMaxLiveProposals the new maximum live proposals
    function updateMaxUserLiveProposals(uint256 newMaxLiveProposals) external override onlyGovernor {
        _setMaxUserLiveProposals(newMaxLiveProposals);
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
    function updateVotingPeriod(uint256 newVotingPeriod) external override onlyGovernor {
        _setVotingPeriod(newVotingPeriod);
    }

    /// updates the voting delay
    /// @param newVotingDelay the new voting delay
    function updateVotingDelay(uint256 newVotingDelay) external override onlyGovernor {
        _setVotingDelay(newVotingDelay);
    }

    /// updates the cross chain voting collection period
    /// @param newCrossChainVoteCollectionPeriod the new cross chain voting collection period
    function updateCrossChainVoteCollectionPeriod(uint256 newCrossChainVoteCollectionPeriod)
        external
        override
        onlyGovernor
    {
        _setCrossChainVoteCollectionPeriod(newCrossChainVoteCollectionPeriod);
    }

    /// @notice sets the break glass guardian address
    /// @param newGuardian the new break glass guardian address
    function setBreakGlassGuardian(address newGuardian) external override onlyGovernor {
        _setBreakGlassGuardian(newGuardian);
    }

    //// @notice array lengths must add up
    /// values must sum to msg.value to ensure guardian cannot steal funds
    /// calldata must be whitelisted
    /// only break glass guardian can call, once, and when they do, their role is revoked
    /// before any external functions are called. This prevents reentrancy/multiple uses
    /// by a single guardian.
    function executeBreakGlass(address[] calldata targets, uint256[] calldata values, bytes[] calldata calldatas)
        external
        payable
        override
        onlyBreakGlassGuardian
    {
        require(
            targets.length == values.length && targets.length == calldatas.length, "MultichainGovernor: arity mismatch"
        );

        uint256 totalValue = 0;
        for (uint256 i = 0; i < values.length;) {
            totalValue += values[i];

            unchecked {
                i++;
            }
        }

        require(totalValue == msg.value, "MultichainGovernor: values must sum to msg.value");

        unchecked {
            for (uint256 i = 0; i < calldatas.length; i++) {
                require(whitelistedCalldatas[calldatas[i]], "MultichainGovernor: calldata not whitelisted");
            }
        }

        unchecked {
            for (uint256 i = 0; i < calldatas.length; i++) {
                require(whitelistedCalldatas[calldatas[i]], "MultichainGovernor: calldata not whitelisted");

                targets[i].functionCallWithValue(
                    calldatas[i], values[i], "MultichainGovernor: break glass guardian call failed"
                );
            }
        }

        emit ProposalExecuted(uint256(uint160(msg.sender)));
    }

    /// @notice set a gas limit for the relayer on the external chain
    /// should only be called if there is a change in gas prices on the external chain
    /// @param newGasLimit new gas limit to set
    function setGasLimit(uint96 newGasLimit) external onlyGovernor {
        _setGasLimit(newGasLimit);
    }
}
