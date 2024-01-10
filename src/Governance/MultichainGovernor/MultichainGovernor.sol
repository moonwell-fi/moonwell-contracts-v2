pragma solidity 0.8.19;

import {GovernorCompatibilityBravoUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/governance/compatibility/GovernorCompatibilityBravoUpgradeable.sol";
import {GovernorSettingsUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/governance/extensions/GovernorSettingsUpgradeable.sol";
import {ERC20VotesCompUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20VotesCompUpgradeable.sol";
import {GovernorUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/governance/GovernorUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {SnapshotInterface} from "@protocol/Governance/MultichainGovernor/SnapshotInterface.sol";
import {IMultichainGovernor} from "@protocol/Governance/MultichainGovernor/IMultichainGovernor.sol";
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
contract MultichainGovernor is
    GovernorCompatibilityBravoUpgradeable,
    GovernorSettingsUpgradeable,
    GovernorUpgradeable
{
    using EnumerableSet for EnumerableSet.UintSet;

    /// @notice active proposals user has proposed
    /// will automatically clear executed or cancelled
    /// proposals from set when called by user
    mapping(address user => EnumerableSet.UintSet userProposals)
        private userLiveProposals;

    /// @notice reference to the xWELL token
    xWELL public xWell;

    /// @notice reference to the WELL token
    WELL public well;

    /// @notice reference to the stkWELL token
    SnapshotInterface public stkWell;

    /// @notice reference to the WELL token distributor contract
    SnapshotInterface public distributor;

    /// @notice the period of time in which a proposal can have
    /// additional cross chain votes collected
    uint256 public crossChainVoteCollectionPeriod;

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
        address _pauseGuardian
    ) public initializer {
        __GovernorVotes_init(ERC20VotesCompUpgradeable(_xWell));
        __GovernorCompatibilityBravo_init();
        __Governor_init("Moonwell Multichain Governor");

        xWell = xWELL(_xWell);
        well = WELL(_well);
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
    }

    function _setCrossChainVoteCollectionPeriod(
        uint256 _crossChainVoteCollectionPeriod
    ) private {
        crossChainVoteCollectionPeriod = _crossChainVoteCollectionPeriod;
    }

    function _setMaxUserLiveProposals(uint256 _maxUserLiveProposals) private {
        maxUserLiveProposals = _maxUserLiveProposals;
    }

    /// TODO override this function from GovernorCompatibilityBravoUpgradeable
    function _getVotes(
        address account,
        uint256 timepoint,
        bytes memory /*params*/
    ) internal view virtual override returns (uint256) {}

    /// TODO override this function from GovernorUpgradeable
    /// @param account The address of the account to check
    /// @param timestamp The unix timestamp in seconds to check the balance at
    function getVotes(
        address account,
        uint256 timestamp
    ) public view virtual override returns (uint256) {}

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
    function whitelistedCalldatas(bytes calldata) external view returns (bool);

    function pauseDuration() external view returns (uint256);

    /// @notice override with a mapping
    function chainAddressVotes(
        uint256 proposalId,
        uint256 chainId,
        address voteGatheringAddress
    ) external view returns (VoteCounts memory);

    /// address the contract can be rolled back to by break glass guardian
    function governanceRollbackAddress() external view returns (address);

    /// break glass guardian
    function breakGlassGuardian() external view returns (address);

    /// returns whether or not the user is a vote collector contract
    /// and can vote on a given chain
    function isCrossChainVoteCollector(
        uint256 chainId,
        address voteCollector
    ) external view returns (bool);

    /// pause guardian address
    function pauseGuardian() external view returns (address);

    /// @notice The total number of proposals
    function state(uint256 proposalId) external view returns (ProposalState);

    /// @notice The total amount of live proposals
    /// proposals that failed will not be included in this list
    /// HMMMM, is a proposal that is succeeded, and past the cross chain vote collection stage but not executed live?
    function liveProposals() external view returns (uint256[] memory);

    /// @dev Returns the proposal threshold (minimum number of votes to propose)
    /// changeable through governance proposals
    function proposalThreshold() external view returns (uint256);

    /// @dev Returns the voting period for a proposal to pass
    function votingPeriod() external view returns (uint256);

    /// @dev Returns the voting delay before voting begins
    function votingDelay() external view returns (uint256);

    /// @dev Returns the cross chain voting period for a given proposal
    function crossChainVoteCollectionPeriod() external view returns (uint256);

    /// @dev Returns the quorum for a proposal to pass
    function quorum() external view returns (uint256);

    /// @notice for backwards compatability with OZ governor
    function quorum(uint256) external view returns (uint256);

    /// @dev Returns the maximum number of live proposals per user
    /// changeable through governance proposals
    function maxUserLiveProposals() external view returns (uint256);

    /// @dev Returns the number of live proposals for a given user
    function currentUserLiveProposals(
        address user
    ) external view returns (uint256);

    /// @dev Returns the number of votes for a given user
    /// queries WELL, xWELL, distributor, and safety module
    function getVotingPower(
        address voter,
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
    ) external returns (uint256);

    function execute(uint256 proposalId) external;

    /// @dev callable only by the proposer, cancels proposal if it has not been executed
    function proposerCancel(uint256 proposalId) external;

    /// @dev callable by anyone, succeeds in cancellation if user has less votes than proposal threshold
    /// at the current point in time.
    /// reverts otherwise.
    function permissionlessCancel(uint256 proposalId) external;

    /// @dev allows user to cast vote for a proposal
    function castVote(uint256 proposalId, uint8 voteValue) external;

    /// @dev allows votes from external chains to be counted
    /// calls wormhole core to decode VAA, ensures validity of sender
    function collectCrosschainVote(bytes memory VAA) external;

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

    /// updates the voting delay
    function updateVotingDelay(uint256 newVotingDelay) external;

    /// updates the cross chain voting collection period
    function updateCrossChainVoteCollectionPeriod(
        uint256 newCrossChainVoteCollectionPeriod
    ) external;

    function setBreakGlassGuardian(address newGuardian) external;

    function setGovernanceReturnAddress(address newAddress) external;

    //// @notice array lengths must add up
    /// values must sum to msg.value to ensure guardian cannot steal funds
    /// calldata must be whitelisted
    /// only break glass guardian can call, once, and when they do, their role is revoked
    function executeBreakGlass(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) external payable;
}
