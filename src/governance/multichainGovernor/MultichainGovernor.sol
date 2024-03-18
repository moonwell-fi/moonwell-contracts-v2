pragma solidity 0.8.19;

import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {Address} from "@openzeppelin-contracts/contracts/utils/Address.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Constants} from "@protocol/governance/multichainGovernor/Constants.sol";
import {SnapshotInterface} from "@protocol/governance/multichainGovernor/SnapshotInterface.sol";
import {WormholeBridgeBase} from "@protocol/wormhole/WormholeBridgeBase.sol";
import {IMultichainGovernor} from "@protocol/governance/multichainGovernor/IMultichainGovernor.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {ConfigurablePauseGuardian} from "@protocol/xWELL/ConfigurablePauseGuardian.sol";

/// @notice Contract is pauseable by the guardian
/// Break glass guardian can roll back governance to the previous ArtemisTimelock and Governor
/// @notice upgradeable, constructor disables implementation contract from working
/// to prevent governance hijacking.
/// Write out liveliness assumptions of wormhole here, showing why wormhole can go down, and
/// the system continue working.
/// Explain why we allow proposals to pass even if wormhole is down or votes from a vote
/// collection contract on another chain are not relayed.
contract MultichainGovernor is
    IMultichainGovernor,
    ConfigurablePauseGuardian,
    WormholeBridgeBase
{
    using EnumerableSet for EnumerableSet.UintSet;
    using Address for address;

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
    mapping(bytes whitelistedCalldata => bool)
        public
        override whitelistedCalldatas;

    /// --------------------------------------------------------- ///
    /// --------------------- VOTING TOKENS --------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice reference to the xWELL token, uses block.timestamp for voting checkpoints
    xWELL public xWell;

    /// @notice reference to the WELL token, uses block number for voting checkpoints
    SnapshotInterface public well;

    /// @notice reference to the stkWELL token, uses block number for voting checkpoints
    SnapshotInterface public stkWell;

    /// @notice reference to the WELL token distributor contract, uses block number for voting checkpoints
    SnapshotInterface public distributor;

    /// @notice whether or not the stkWell contract uses timestamps or block numbers
    bool public useTimestamps;

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
        xWell = xWELL(initData.xWell);
        well = SnapshotInterface(initData.well);
        stkWell = SnapshotInterface(initData.stkWell);
        distributor = SnapshotInterface(initData.distributor);

        _setProposalThreshold(initData.proposalThreshold);
        _setVotingPeriod(initData.votingPeriodSeconds);
        _setCrossChainVoteCollectionPeriod(
            initData.crossChainVoteCollectionPeriod
        );
        _setQuorum(initData.quorum);
        _setMaxUserLiveProposals(initData.maxUserLiveProposals);
        _setBreakGlassGuardian(initData.breakGlassGuardian);

        __Pausable_init();

        _updatePauseDuration(initData.pauseDuration);

        /// set the pause guardian
        _grantGuardian(initData.pauseGuardian);

        _setWormholeRelayer(address(initData.wormholeRelayer));

        /// sets vote collection contracts
        _addTargetAddresses(trustedSenders);

        _setGasLimit(Constants.MIN_GAS_LIMIT); /// set the gas limit to 400k

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
        require(
            msg.sender == address(this),
            "MultichainGovernor: only governor"
        );
        _;
    }

    /// @notice modifier to restrict function access to only break glass guardian
    /// immediately sets break glass guardian to address 0 on use, and emits the
    /// BreakGlassGuardianChanged event
    modifier onlyBreakGlassGuardian() {
        require(
            msg.sender == breakGlassGuardian,
            "MultichainGovernor: only break glass guardian"
        );

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

    /// @notice returns information on a proposal
    /// @param proposalId the id of the proposal to check
    function proposalInformation(
        uint256 proposalId
    )
        external
        view
        returns (
            address proposer,
            uint256 voteSnapshotTimestamp,
            uint256 votingStartTime,
            uint256 endTimestamp,
            uint256 crossChainVoteCollectionEndTimestamp,
            uint256 totalVotes,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 abstainVotes
        )
    {
        Proposal storage proposal = proposals[proposalId];

        proposer = proposal.proposer;
        voteSnapshotTimestamp = proposal.voteSnapshotTimestamp;
        votingStartTime = proposal.votingStartTime;
        endTimestamp = proposal.votingEndTime;
        crossChainVoteCollectionEndTimestamp = proposal
            .crossChainVoteCollectionEndTimestamp;
        totalVotes = proposal.totalVotes;
        forVotes = proposal.forVotes;
        againstVotes = proposal.againstVotes;
        abstainVotes = proposal.abstainVotes;
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

    /// @notice returns all proposals a user has that are live
    /// a proposal is considered live if it is active or pending
    /// @param user The address of the user to check
    function getUserLiveProposals(
        address user
    ) external view returns (uint256[] memory) {
        uint256[] memory userProposals = new uint256[](
            currentUserLiveProposals(user)
        );
        uint256[] memory allUserProposals = _userLiveProposals[user].values();
        uint256 userLiveProposalIndex = 0;

        unchecked {
            for (uint256 i = 0; i < allUserProposals.length; i++) {
                if (proposalActive(allUserProposals[i])) {
                    userProposals[userLiveProposalIndex] = allUserProposals[i];
                    userLiveProposalIndex++;
                }
            }
        }

        return userProposals;
    }

    /// @notice returns the total voting power for an address at a given block number and timestamp
    /// @param account The address of the account to check
    /// @param timestamp The unix timestamp in seconds to check the balance at
    /// @param blockNumber The block number to check the balance at
    function getVotes(
        address account,
        uint256 timestamp,
        uint256 blockNumber
    ) public view returns (uint256) {
        uint256 wellVotes = well.getPriorVotes(account, blockNumber);
        uint256 distributorVotes = distributor.getPriorVotes(
            account,
            blockNumber
        );
        uint256 xWellVotes = xWell.getPastVotes(account, timestamp);
        uint256 stkWellVotes = stkWell.getPriorVotes(
            account,
            useTimestamps ? timestamp : blockNumber
        );

        return xWellVotes + stkWellVotes + distributorVotes + wellVotes;
    }

    /// @notice returns the current voting power for an address across well, xWell, stkWell and distributor
    /// @param account The address of the account to check
    function getCurrentVotes(address account) public view returns (uint256) {
        uint256 wellVotes = well.getCurrentVotes(account);
        uint256 stkWellVotes = stkWell.getCurrentVotes(account);
        uint256 distributorVotes = distributor.getCurrentVotes(account);

        uint256 xWellVotes = xWell.getVotes(account);

        return xWellVotes + stkWellVotes + distributorVotes + wellVotes;
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
    ///
    /// valid proposal states:
    ///
    ///      canceled                              -> means proposer canceled during active period, proposer votes fell below threshold and was canceled during active period,
    ///                                               or contract was paused while proposal was in state Active, CrossChainVoteCollection or Succeeded
    ///
    ///      active                                -> means block timestamp is greater than or equal to the start timestamp and less than or equal to the end timestamp. Users
    ///                                               can cast votes during this period.
    ///
    ///      cross chain vote collection period    -> block timestamp is greater than the end timestamp and less than or equal to the cross chain vote collection end timestamp.
    ///                                               Votes from other chains can be registered during this period.
    ///
    ///      succeeded                             -> block timestamp is greater the cross chain vote collection period and yay votes are greater than nay votes, total votes meet
    ///                                               or exceed quorum.
    ///
    ///      defeated                              -> block timestamp is past the cross chain vote collection period and nay votes are greater than or equal to yay votes or
    ///                                               total votes are less than quorum
    ///
    ///      executed                              -> reached succeeded state, and proposal was successfully executed
    ///
    /// @param proposalId The id of the proposal to check
    function state(uint256 proposalId) public view returns (ProposalState) {
        require(
            proposalCount >= proposalId && proposalId > 0,
            "MultichainGovernor: invalid proposal id"
        );

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
        require(
            proposalState == ProposalState.Active,
            "MultichainGovernor: invalid state"
        );

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

    /// @dev Returns the proposal ID for the proposed proposal
    /// only callable if user has proposal threshold or more votes
    /// @param targets the list of target addresses for calls to be made
    /// @param values the list of values to be used for the calls
    /// @param calldatas the list of calldatas to be used for the calls
    /// @param description the description of the proposal
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external payable override whenNotPaused returns (uint256) {
        /// Checks

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

        /// Effects in Checks phase
        _syncTotalLiveProposals(); /// remove inactive proposals from all proposals, and remove from inactive proposals from user list

        {
            uint256 userProposalCount = currentUserLiveProposals(msg.sender);
            require(
                userProposalCount < maxUserLiveProposals,
                "MultichainGovernor: too many live proposals for this user"
            );
        }

        {
            /// check to ensure the sum of values does not overflow
            /// this is an implicit check that sum is lte UINT_256 max,
            /// this way a user cannot create a proposal that can never be executed
            uint256 totalValue = 0;
            for (uint256 i = 0; i < values.length; ) {
                totalValue += values[i];
                unchecked {
                    i++;
                }
            }
        }

        /// Effects

        proposalCount++;

        Proposal storage newProposal = proposals[proposalCount];
        bytes memory payload;

        {
            uint256 startTimestamp = block.timestamp;
            uint256 voteSnapshotTimestamp = startTimestamp - 1;
            uint256 endTimestamp = startTimestamp + votingPeriod;
            uint256 crossChainVoteCollectionEndTimestamp = endTimestamp +
                crossChainVoteCollectionPeriod;

            newProposal.proposer = msg.sender;
            newProposal.targets = targets;
            newProposal.values = values;
            newProposal.calldatas = calldatas;
            newProposal.voteSnapshotTimestamp = voteSnapshotTimestamp;
            newProposal.votingStartTime = startTimestamp;
            newProposal.voteSnapshotBlock = block.number - 1;
            newProposal.votingEndTime = endTimestamp;
            newProposal
                .crossChainVoteCollectionEndTimestamp = crossChainVoteCollectionEndTimestamp;

            payload = abi.encode(
                proposalCount,
                voteSnapshotTimestamp,
                startTimestamp,
                endTimestamp,
                crossChainVoteCollectionEndTimestamp
            );

            emit ProposalCreated(
                proposalCount,
                msg.sender,
                targets,
                values,
                calldatas,
                startTimestamp,
                endTimestamp,
                description
            );
        }

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

        /// Interactions

        /// call relayer with information about proposal
        /// iterate over chainConfigs and send messages to each of them
        _bridgeOutAll(payload);

        return proposalCount;
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
        /// Checks
        require(
            state(proposalId) == ProposalState.Succeeded,
            "MultichainGovernor: proposal can only be executed if it is Succeeded"
        );

        uint256 totalValue = 0;

        Proposal storage proposal = proposals[proposalId];

        for (uint256 i = 0; i < proposal.targets.length; ) {
            totalValue += proposal.values[i];
            unchecked {
                i++;
            }
        }

        require(totalValue == msg.value, "MultichainGovernor: invalid value");

        /// Effects

        proposal.executed = true;

        /// remove the proposal that is about to be executed from all proposals,
        /// and remove from inactive proposals from user list
        _syncTotalLiveProposals();

        /// Interactions

        unchecked {
            for (uint256 i = 0; i < proposal.targets.length; i++) {
                proposal.targets[i].functionCallWithValue(
                    proposal.calldatas[i],
                    proposal.values[i],
                    "MultichainGovernor: execute call failed"
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
        require(
            msg.sender == proposals[proposalId].proposer ||
                getCurrentVotes(proposals[proposalId].proposer) <
                proposalThreshold,
            "MultichainGovernor: unauthorized cancel"
        );

        ProposalState proposalState = state(proposalId);

        require(
            proposalState == ProposalState.Active,
            "MultichainGovernor: cannot cancel non active proposal"
        );

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
        require(
            state(proposalId) == ProposalState.Active,
            "MultichainGovernor: proposal not active"
        );
        require(
            voteValue <= Constants.VOTE_VALUE_ABSTAIN,
            "MultichainGovernor: invalid vote value"
        );

        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = proposal.receipts[msg.sender];

        require(
            receipt.hasVoted == false,
            "MultichainGovernor: voter already voted"
        );

        /// if a user tries to vote at the start timestamp or the start block, then it will fail,
        /// but that is not possible because both of those are in the past as set in the propose
        /// function.
        uint256 votes = getVotes(
            msg.sender,
            proposal.voteSnapshotTimestamp,
            proposal.voteSnapshotBlock
        );

        require(votes != 0, "MultichainGovernor: voter has no votes");

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

    /// @notice set the new stkWell token address
    /// if the new staked well token does not conform to the new interface, then
    /// this governor contract is bricked and will need to be rolled back via
    /// the break glass guardian.
    /// use this function with extreme caution and thoroughly integration test
    /// making proposals and voting on them after calling this function.
    /// @param newStakedWell the new stkWell token address
    /// @param toUseTimestamps whether or not to use timestamps for voting
    function setNewStakedWell(
        address newStakedWell,
        bool toUseTimestamps
    ) external onlyGovernor {
        stkWell = SnapshotInterface(newStakedWell);
        useTimestamps = toUseTimestamps;

        emit NewStakedWellSet(newStakedWell, toUseTimestamps);
    }

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

    /// @notice updates the maximum user live proposals
    /// @param newMaxLiveProposals the new maximum live proposals
    function updateMaxUserLiveProposals(
        uint256 newMaxLiveProposals
    ) external override onlyGovernor {
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
        require(
            newGasLimit >= Constants.MIN_GAS_LIMIT,
            "MultichainGovernor: gas limit too low"
        );

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
        require(
            targets.length == calldatas.length,
            "MultichainGovernor: arity mismatch"
        );

        require(targets.length > 0, "MultichainGovernor: empty array");

        unchecked {
            for (uint256 i = 0; i < calldatas.length; i++) {
                require(
                    whitelistedCalldatas[calldatas[i]],
                    "MultichainGovernor: calldata not whitelisted"
                );

                targets[i].functionCall(
                    calldatas[i],
                    "MultichainGovernor: break glass guardian call failed"
                );
            }
        }

        require(
            breakGlassGuardian == address(0),
            "MultichainGovernor: break glass guardian not null"
        );

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

    /// @notice helper function to whitelist calldata
    /// if the calldata is already whitelisted, then it can only be removed
    /// if the calldata is not already whitelisted, then it can only be approved
    /// @param data the calldata to update approval for
    /// @param approved whether or not the calldata is approved
    function _updateApprovedCalldata(
        bytes calldata data,
        bool approved
    ) private {
        /// can only approve if it is not already approved
        if (approved == true) {
            require(
                !whitelistedCalldatas[data],
                "MultichainGovernor: calldata already approved"
            );
        } else {
            /// can only remove approval if already approved
            require(
                whitelistedCalldatas[data],
                "MultichainGovernor: calldata not approved"
            );
        }

        whitelistedCalldatas[data] = approved;

        emit CalldataApprovalUpdated(data, approved);
    }

    /// @notice helper function to set the cross chain vote collection period
    /// upper and lower bounds are enforced to ensure that the period is within
    /// reasonable bounds.
    function _setCrossChainVoteCollectionPeriod(
        uint256 _crossChainVoteCollectionPeriod
    ) private {
        require(
            _crossChainVoteCollectionPeriod >=
                Constants.MIN_CROSS_CHAIN_VOTE_COLLECTION_PERIOD &&
                _crossChainVoteCollectionPeriod <=
                Constants.MAX_CROSS_CHAIN_VOTE_COLLECTION_PERIOD,
            "MultichainGovernor: invalid vote collection period"
        );

        uint256 oldVal = crossChainVoteCollectionPeriod;
        crossChainVoteCollectionPeriod = _crossChainVoteCollectionPeriod;

        emit CrossChainVoteCollectionPeriodChanged(
            oldVal,
            _crossChainVoteCollectionPeriod
        );
    }

    /// @notice user max live proposals cannot be zero, as that would brick governance permanently
    /// 0 < max live proposals <= max user proposal count
    /// @param _maxUserLiveProposals the new max user live proposals
    function _setMaxUserLiveProposals(uint256 _maxUserLiveProposals) private {
        require(
            _maxUserLiveProposals != 0 &&
                _maxUserLiveProposals <= Constants.MAX_USER_PROPOSAL_COUNT,
            "MultichainGovernor: invalid max user live proposals"
        );

        uint256 _oldValue = maxUserLiveProposals;
        maxUserLiveProposals = _maxUserLiveProposals;

        emit UserMaxProposalsChanged(_oldValue, _maxUserLiveProposals);
    }

    /// @dev minimum quorum is 0, maximum quorum value is enforced
    /// @param _quorum the new quorum
    function _setQuorum(uint256 _quorum) private {
        require(
            _quorum <= Constants.MAX_QUORUM,
            "MultichainGovernor: invalid quorum"
        );

        uint256 _oldValue = quorum;
        quorum = _quorum;

        emit QuroumVotesChanged(_oldValue, _quorum);
    }

    /// @dev lower and upper bounds are enforced to prevent a proposal from
    /// continuing indefinitely and breaking governance
    /// @param _votingPeriod the new voting period
    function _setVotingPeriod(uint256 _votingPeriod) private {
        require(
            _votingPeriod >= Constants.MIN_VOTING_PERIOD &&
                _votingPeriod <= Constants.MAX_VOTING_PERIOD,
            "MultichainGovernor: voting period out of bounds"
        );

        uint256 _oldValue = votingPeriod;

        votingPeriod = _votingPeriod;

        emit VotingPeriodChanged(_oldValue, _votingPeriod);
    }

    /// @dev upper and lower bounds enforced to prevent a scenario
    /// where users cannot propose to the governor
    /// @param _proposalThreshold the new proposal threshold
    function _setProposalThreshold(uint256 _proposalThreshold) private {
        require(
            _proposalThreshold >= Constants.MIN_PROPOSAL_THRESHOLD &&
                _proposalThreshold <= Constants.MAX_PROPOSAL_THRESHOLD,
            "MultichainGovernor: proposal threshold out of bounds"
        );

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
                    _removeFromSet(
                        _userLiveProposals[proposals[allProposals[i]].proposer],
                        allProposals[i],
                        "MultichainGovernor: could not remove proposal from user live proposals"
                    );

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
    function _removeFromSet(
        EnumerableSet.UintSet storage set,
        uint256 proposalId,
        string memory errorMessage
    ) private {
        require(set.remove(proposalId), errorMessage);
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
        require(
            payload.length == 128,
            "MultichainGovernor: invalid payload length"
        );

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
        require(
            voteCounts.forVotes == 0 &&
                voteCounts.againstVotes == 0 &&
                voteCounts.abstainVotes == 0,
            "MultichainGovernor: vote already collected"
        );

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
}
