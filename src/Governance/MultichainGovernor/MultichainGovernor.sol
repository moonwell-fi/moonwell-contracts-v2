pragma solidity 0.8.19;

import {GovernorCompatibilityBravoUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/governance/compatibility/GovernorCompatibilityBravoUpgradeable.sol";
import {GovernorSettingsUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/governance/extensions/GovernorSettingsUpgradeable.sol";
import {ERC20VotesCompUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20VotesCompUpgradeable.sol";
import {GovernorUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/governance/GovernorUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
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

/// TODO, remove all OZ governor stuff, we're going to roll our own from scratch
abstract contract MultichainGovernor is
    WormholeTrustedSender,
    IMultichainGovernor,
    ConfigurablePauseGuardian
{
    using EnumerableSet for EnumerableSet.UintSet;

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// -------------------- STATE VARIABLES -------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice all live proposals, executed and cancelled proposals are removed
    /// when a new proposal is created, it is added to this set and any stale
    /// items are removed
    EnumerableSet.UintSet private liveProposals;

    /// @notice active proposals user has proposed
    /// will automatically clear executed or cancelled
    /// proposals from set when called by user
    mapping(address user => EnumerableSet.UintSet userProposals)
        private userLiveProposals;

    /// @notice the number of votes for a given proposal on a given chain
    mapping(uint16 chainId => mapping(address => VoteCounts))
        public chainVoteCollectorVotes;

    /// @notice the total number of votes for a given proposal
    mapping(uint256 proposalId => VoteCounts) public proposals;

    /// @notice reference to the xWELL token
    xWELL public xWell;

    /// @notice reference to the WELL token
    SnapshotInterface public well;

    /// @notice reference to the stkWELL token
    SnapshotInterface public stkWell;

    /// @notice reference to the WELL token distributor contract
    SnapshotInterface public distributor;

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
    uint256 public override votingDelay;

    /// @notice the voting period
    uint256 public override votingPeriod;

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
    function initialize(
        address _xWell,
        address _well,
        address _stkWell,
        address _distributor,
        uint256 _proposalThreshold,
        uint256 _votingPeriod,
        uint256 _votingDelay,
        uint256 _crossChainVoteCollectionPeriod,
        uint256 _quorum,
        uint256 _maxUserLiveProposals,
        uint128 _pauseDuration,
        address _pauseGuardian,
        WormholeTrustedSender.TrustedSender[] memory _trustedSenders
    ) public initializer {
        xWell = xWELL(_xWell);
        well = SnapshotInterface(_well);
        stkWell = SnapshotInterface(_stkWell);
        distributor = SnapshotInterface(_distributor);

        _setProposalThreshold(_proposalThreshold);
        _setVotingPeriod(_votingPeriod);
        _setVotingDelay(_votingDelay);
        _setCrossChainVoteCollectionPeriod(_crossChainVoteCollectionPeriod); /// TODO define
        _setQuorum(_quorum);
        _setMaxUserLiveProposals(_maxUserLiveProposals); /// TODO define

        __Pausable_init(); /// not really needed, but seems like good form
        _updatePauseDuration(_pauseDuration);
        _grantGuardian(_pauseGuardian); /// set the pause guardian
        _addTrustedSenders(_trustedSenders);
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
        crossChainVoteCollectionPeriod = _crossChainVoteCollectionPeriod;
    }

    function _setMaxUserLiveProposals(uint256 _maxUserLiveProposals) private {
        maxUserLiveProposals = _maxUserLiveProposals;
    }

    function _setQuorum(uint256 _quorum) private {
        quorum = _quorum;
    }

    function _setVotingDelay(uint256 _votingDelay) private {
        votingDelay = _votingDelay;
    }

    function _setVotingPeriod(uint256 _votingPeriod) private {
        votingPeriod = _votingPeriod;
    }

    function _setProposalThreshold(uint256 _proposalThreshold) private {
        proposalThreshold = _proposalThreshold;
    }

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// -------------------- VIEW FUNCTIONS --------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// returns the total voting power for an address at a given block number and timestamp
    /// @param account The address of the account to check
    /// @param timestamp The unix timestamp in seconds to check the balance at
    /// @param blockNumber The block number to check the balance at
    function getVotes(
        address account,
        uint256 timestamp,
        uint256 blockNumber
    ) public view returns (uint256) {
        uint256 wellVotes = well.getPriorVotes(account, timestamp);
        uint256 stkWellVotes = stkWell.getPriorVotes(account, blockNumber);
        uint256 distributorVotes = distributor.getPriorVotes(
            account,
            blockNumber
        );
        uint256 xWellVotes = xWell.getPastVotes(account, blockNumber);

        return xWellVotes + stkWellVotes + distributorVotes + wellVotes;
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
    /// TODO triple check that non of the aforementioned functions have hash collisions with something that would make them dangerous
    function whitelistedCalldatas(
        bytes calldata
    ) external view returns (bool) {}

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
    function state(
        uint256 proposalId
    ) external view virtual returns (ProposalState);

    /// @dev Returns the number of live proposals for a given user
    function currentUserLiveProposals(
        address user
    ) external view virtual returns (uint256);

    /// @dev Returns the number of votes for a given user
    /// queries WELL, xWELL, distributor, and safety module
    function getVotingPower(
        address voter,
        uint256 blockNumber
    ) external view virtual returns (uint256);

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
    ) external override returns (uint256) {}

    function execute(uint256 proposalId) external override {}

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
    function collectCrosschainVote(bytes memory VAA) external override {}

    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////
    /// ---------- governance only functions ---------- ////
    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////

    /// updates the proposal threshold
    function updateProposalThreshold(
        uint256 newProposalThreshold
    ) external override {}

    /// updates the maximum user live proposals
    function updateMaxUserLiveProposals(
        uint256 newMaxLiveProposals
    ) external override {}

    /// updates the quorum
    function updateQuorum(uint256 newQuorum) external override {}

    /// updates the voting period
    function updateVotingPeriod(uint256 newVotingPeriod) external override {}

    /// updates the voting delay
    function updateVotingDelay(uint256 newVotingDelay) external override {}

    /// updates the cross chain voting collection period
    function updateCrossChainVoteCollectionPeriod(
        uint256 newCrossChainVoteCollectionPeriod
    ) external override {}

    function setBreakGlassGuardian(address newGuardian) external override {}

    function setGovernanceReturnAddress(address newAddress) external override {}

    //// @notice array lengths must add up
    /// values must sum to msg.value to ensure guardian cannot steal funds
    /// calldata must be whitelisted
    /// only break glass guardian can call, once, and when they do, their role is revoked
    function executeBreakGlass(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) external payable override onlyBreakGlassGuardian {}
}
