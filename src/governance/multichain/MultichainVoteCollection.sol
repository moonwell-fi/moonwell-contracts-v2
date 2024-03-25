pragma solidity 0.8.19;

import {IMultichainVoteCollection} from "@protocol/governance/multichain/IMultichainVoteCollection.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Constants} from "@protocol/governance/multichain/Constants.sol";
import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {SnapshotInterface} from "@protocol/governance/multichain/SnapshotInterface.sol";
import {WormholeBridgeBase} from "@protocol/wormhole/WormholeBridgeBase.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";

/// @notice Upgradeable contract, constructor disables the implementation contract
/// This contract is intentionally as minimal as possible. It is only responsible for
/// collecting votes on chains external to Moonbeam and broadcasting them back to
/// Moonbeam. It does not have any logic for executing proposals or storing calldata.
/// While a proposal is in the Cross Chain Vote Collection phase, the vote counts can
/// be emitted as many times as any user wants. This is to allow users to have their
/// votes counted on the Moonbeam contract. The Multichain Governor contract on
/// Moonbeam will only allow receiving of votes for each chaind id and proposal id
/// once per proposal. This is to prevent votes from external chains being double
/// counted.
contract MultichainVoteCollection is
    IMultichainVoteCollection,
    WormholeBridgeBase,
    Ownable2StepUpgradeable
{
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// -------------------- STATE VARIABLES -------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice reference to the xWELL token
    xWELL public xWell;

    /// @notice reference to the stkWELL token
    /// this stkWELL version uses timestamps instead of block number
    SnapshotInterface public stkWell;

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ----------------------- MAPPINGS ------------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @notice mapping from proposalId to MultichainProposal
    mapping(uint256 proposalId => MultichainProposal) public proposals;

    /// @notice disable the initializer to stop governance hijacking
    /// and avoid selfdestruct attacks.
    constructor() {
        _disableInitializers();
    }

    /// @notice initialize the governor contract
    /// @param _xWell address of the xWELL token
    /// @param _stkWell address of the stkWell token
    /// @param _moonbeamGovernor address of the moonbeam governor contract
    /// @param _wormholeRelayer address of the wormhole relayer
    /// @param _moonbeamWormholeChainId chain id of the moonbeam chain
    /// @param _owner address of the contract
    function initialize(
        address _xWell,
        address _stkWell,
        address _moonbeamGovernor,
        address _wormholeRelayer,
        uint16 _moonbeamWormholeChainId,
        address _owner
    ) external initializer {
        xWell = xWELL(_xWell);
        stkWell = SnapshotInterface(_stkWell);

        _addTargetAddress(_moonbeamWormholeChainId, _moonbeamGovernor);

        _setWormholeRelayer(_wormholeRelayer);

        _setGasLimit(Constants.MIN_GAS_LIMIT); /// set the gas limit to 400k

        __Ownable_init();
        _transferOwnership(_owner); /// directly set the new owner without waiting for pending owner to accept
    }

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------- VIEW FUNCTIONS -------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice returns a user's vote receipt on a given proposal
    /// @param proposalId the id of the proposal to check
    /// @param voter the address of the voter to check
    function getReceipt(
        uint256 proposalId,
        address voter
    ) external view returns (bool hasVoted, uint8 voteValue, uint256 votes) {
        MultichainProposal storage proposal = proposals[proposalId];
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
            uint256 voteSnapshotTimestamp,
            uint256 votingStartTime,
            uint256 votingEndTime,
            uint256 crossChainVoteCollectionEndTimestamp,
            uint256 totalVotes,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 abstainVotes
        )
    {
        MultichainProposal storage proposal = proposals[proposalId];

        /// timestamps
        voteSnapshotTimestamp = proposal.voteSnapshotTimestamp;
        votingStartTime = proposal.votingStartTime;
        votingEndTime = proposal.votingEndTime;
        crossChainVoteCollectionEndTimestamp = proposal
            .crossChainVoteCollectionEndTimestamp;

        /// votes
        totalVotes = proposal.votes.totalVotes;
        forVotes = proposal.votes.forVotes;
        againstVotes = proposal.votes.againstVotes;
        abstainVotes = proposal.votes.abstainVotes;
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
        MultichainProposal storage proposal = proposals[proposalId];

        totalVotes = proposal.votes.totalVotes;
        forVotes = proposal.votes.forVotes;
        againstVotes = proposal.votes.againstVotes;
        abstainVotes = proposal.votes.abstainVotes;
    }

    /// @notice returns the total voting power for an address at a given block number and timestamp
    /// returns the sum of votes across both xWELL and stkWELL at the given timestamp
    /// @param account The address of the account to check
    /// @param timestamp The unix timestamp in seconds to check the balance at
    function getVotes(
        address account,
        uint256 timestamp
    ) public view returns (uint256) {
        return
            xWell.getPastVotes(account, timestamp) +
            stkWell.getPriorVotes(account, timestamp);
    }

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------- PERMISSIONLESS -------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice allows user to cast vote for a proposal
    /// @param proposalId the id of the proposal to vote on
    /// @param voteValue the value of the vote
    function castVote(uint256 proposalId, uint8 voteValue) external {
        /// Checks

        MultichainProposal storage proposal = proposals[proposalId];

        /// Maintain require statments below pairing with the artemis governor behavior
        /// Check if proposal start time has passed
        require(
            proposal.votingStartTime <= block.timestamp,
            "MultichainVoteCollection: Voting has not started yet"
        );

        /// Check if proposal end time has not passed
        require(
            proposal.votingEndTime >= block.timestamp,
            "MultichainVoteCollection: Voting has ended"
        );

        /// Vote value must be 0, 1 or 2
        require(
            voteValue <= Constants.VOTE_VALUE_ABSTAIN,
            "MultichainVoteCollection: invalid vote value"
        );

        /// Check if user has already voted
        Receipt storage receipt = proposal.receipts[msg.sender];
        require(
            receipt.hasVoted == false,
            "MultichainVoteCollection: voter already voted"
        );

        /// Get voting power
        uint256 userVotes = getVotes(
            msg.sender,
            proposal.voteSnapshotTimestamp
        );

        require(userVotes != 0, "MultichainVoteCollection: voter has no votes");

        /// Effects

        MultichainVotes storage votes = proposal.votes;

        if (voteValue == Constants.VOTE_VALUE_YES) {
            votes.forVotes += userVotes;
        } else if (voteValue == Constants.VOTE_VALUE_NO) {
            votes.againstVotes += userVotes;
        } else if (voteValue == Constants.VOTE_VALUE_ABSTAIN) {
            votes.abstainVotes += userVotes;
        }

        /// Add user votes to total votes
        votes.totalVotes += userVotes;

        /// Create receipt
        receipt.hasVoted = true;
        receipt.voteValue = voteValue;
        receipt.votes = userVotes;

        emit VoteCast(msg.sender, proposalId, voteValue, userVotes);
    }

    /// @notice Emits votes to be contabilized on Moonbeam Governor contract
    /// @param proposalId the proposal id
    function emitVotes(uint256 proposalId) external payable override {
        /// Get the proposal
        MultichainProposal storage proposal = proposals[proposalId];

        /// Get votes
        MultichainVotes storage votes = proposal.votes;

        /// Check if proposal has votes
        require(
            votes.totalVotes > 0,
            "MultichainVoteCollection: proposal has no votes"
        );

        /// Check if proposal end time has passed
        require(
            proposal.votingEndTime < block.timestamp,
            "MultichainVoteCollection: Voting has not ended"
        );

        /// Check if proposal collection end time has not passed
        require(
            proposal.crossChainVoteCollectionEndTimestamp >= block.timestamp,
            "MultichainVoteCollection: Voting collection phase has ended"
        );

        _bridgeOutAll(
            abi.encode(
                proposalId,
                votes.forVotes,
                votes.againstVotes,
                votes.abstainVotes
            )
        );

        emit VotesEmitted(
            proposalId,
            votes.forVotes,
            votes.againstVotes,
            votes.abstainVotes
        );
    }

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// -------------------- INTERNAL RECEIVE ------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice bridge proposals from moonbeam
    /// @param payload the payload of the message, contains proposalId, votingStartTime, votingEndTime and voteCollectionEndTime
    function _bridgeIn(uint16, bytes memory payload) internal override {
        /// payload should be 5 uint256s
        require(
            payload.length == 160,
            "MultichainVoteCollection: invalid payload length"
        );

        /// Parse the payload and do the corresponding actions!
        (
            uint256 proposalId,
            uint256 voteSnapshotTimestamp,
            uint256 votingStartTime,
            uint256 votingEndTime,
            uint256 crossChainVoteCollectionEndTimestamp
        ) = abi.decode(payload, (uint256, uint256, uint256, uint256, uint256));

        /// Ensure proposalId is unique
        require(
            proposals[proposalId].votingStartTime == 0,
            "MultichainVoteCollection: proposal already exists"
        );

        /// Ensure votingEndTime is in the future so there is time for users to vote
        require(
            votingEndTime > block.timestamp,
            "MultichainVoteCollection: end time must be in the future"
        );

        /// Ensure voteSnapshotTimestamp is less than votingStartTime
        require(
            voteSnapshotTimestamp < votingStartTime,
            "MultichainVoteCollection: snapshot time must be before start time"
        );

        /// Ensure votingStartTime is less than votingEndTime
        require(
            votingStartTime < votingEndTime,
            "MultichainVoteCollection: start time must be before end time"
        );

        /// Ensure votingStartTime is less than votingEndTime
        require(
            votingEndTime < crossChainVoteCollectionEndTimestamp,
            "MultichainVoteCollection: end time must be before vote collection end"
        );

        /// Create the proposal
        MultichainProposal storage proposal = proposals[proposalId];
        proposal.votingStartTime = votingStartTime;
        proposal.votingEndTime = votingEndTime;
        proposal
            .crossChainVoteCollectionEndTimestamp = crossChainVoteCollectionEndTimestamp;
        proposal.voteSnapshotTimestamp = voteSnapshotTimestamp;

        /// Emit the ProposalCreated event
        emit ProposalCreated(
            proposalId,
            votingStartTime,
            votingEndTime,
            crossChainVoteCollectionEndTimestamp
        );
    }

    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////
    //// ----------------- ADMIN ONLY ----------------- ////
    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////

    /// @notice set a gas limit for the relayer on the external chain
    /// should only be called if there is a change in gas prices on the external chain
    /// @param newGasLimit new gas limit to set
    function setGasLimit(uint96 newGasLimit) external onlyOwner {
        require(
            newGasLimit >= Constants.MIN_GAS_LIMIT,
            "MultichainVoteCollection: gas limit too low"
        );

        _setGasLimit(newGasLimit);
    }

    /// @notice update the stkWell token address
    /// @param newStakedWell the new stkWell token address
    function setNewStakedWell(address newStakedWell) external onlyOwner {
        stkWell = SnapshotInterface(newStakedWell);

        emit NewStakedWellSet(newStakedWell);
    }
}
