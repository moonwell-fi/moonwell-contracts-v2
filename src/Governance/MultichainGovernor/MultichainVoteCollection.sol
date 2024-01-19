pragma solidity 0.8.19;

import {IMultichainVoteCollection} from "@protocol/Governance/MultichainGovernor/IMultichainVoteCollection.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {IWormholeReceiver} from "@protocol/wormhole/IWormholeReceiver.sol";
import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {WormholeBridgeBase} from "@protocol/wormhole/WormholeBridgeBase.sol";
import {Constants} from "@protocol/Governance/MultichainGovernor/Constants.sol";

/// Upgradeable, constructor disables implementation
contract MultichainVoteCollection is IMultichainVoteCollection, WormholeBridgeBase, Ownable2StepUpgradeable {
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// -------------------- STATE VARIABLES -------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice reference to the xWELL token
    xWELL public xWell;

    // @notice MoonBeam Wormhole Chain Id
    uint16 internal moombeanWormholeChainId;

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ----------------------- MAPPINGS ------------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// @notice mapping from proposalId to MultichainProposal
    mapping(uint256 proposalId => MultichainProposal) public proposals;

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// ------------------------- EVENTS ------------------------ ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    // @notice An event emitted when a proposal is created
    event ProposalCreated(
        uint256 proposalId, uint256 votingStartTime, uint256 votingEndTime, uint256 votingCollectionEndTime
    );

    /// @notice emitted when votes are emitted to the MoomBeam chain
    /// @param proposalId the proposal id
    /// @param forVotes number of votes for the proposal
    /// @param againstVotes number of votes against the proposal
    /// @param abstainVotes number of votes abstaining the proposal
    event VotesEmitted(uint256 proposalId, uint256 forVotes, uint256 againstVotes, uint256 abstainVotes);

    /// @notice disable the initializer to stop governance hijacking
    /// and avoid selfdestruct attacks.
    constructor() {
        _disableInitializers();
    }

    /// @notice initialize the governor contract
    /// @param _xWell address of the xWELL token
    /// @param _moonBeamGovernor address of the moonbeam governor contract
    /// @param _wormholeRelayer address of the wormhole relayer
    function initialize(
        address _xWell,
        address _moonBeamGovernor,
        address _wormholeRelayer,
        uint16 _moombeanWormholeChainId
    ) external initializer {
        xWell = xWELL(_xWell);

        moombeanWormholeChainId = _moombeanWormholeChainId;

        _addTrustedSender(_moonBeamGovernor, _moombeanWormholeChainId);

        _addWormholeRelayer(_wormholeRelayer);
    }

    /// @dev allows user to cast vote for a proposal
    function castVote(uint256 proposalId, uint8 voteValue) external {
        MultichainProposal storage proposal = proposals[proposalId];

        // Maintain require statments below pairing with the artemis governor behavior
        // Check if proposal start time has passed
        require(proposal.votingStartTime < block.timestamp, "MultichainVoteCollection: Voting has not started yet");

        // Check if proposal end time has not passed
        require(proposal.votingEndTime >= block.timestamp, "MultichainVoteCollection: Voting has ended");

        // Vote value must be 0, 1 or 2
        require(voteValue <= Constants.VOTE_VALUE_ABSTAIN, "MultichainVoteCollection: invalid vote value");

        // Check if user has already voted
        Receipt storage receipt = proposal.receipts[msg.sender];
        require(
            receipt.hasVoted == false,
            "MultichainVoteCollection: voter already voted"
        );

        // Get voting power
        uint256 userVotes = getVotes(msg.sender, proposal.votingStartTime);

        MultichainVotes storage votes = proposal.votes;

        if (voteValue == Constants.VOTE_VALUE_YES) {
            votes.forVotes += votes.forVotes;
        } else if (voteValue == Constants.VOTE_VALUE_NO) {
            votes.againstVotes += votes.againstVotes;
        } else if (voteValue == Constants.VOTE_VALUE_ABSTAIN) {
            votes.abstainVotes += votes.abstainVotes;
        }

        // Add user votes to total votes
        votes.totalVotes += userVotes;

        // Create receipt
        receipt.hasVoted = true;
        receipt.voteValue = voteValue;
        receipt.votes = userVotes;
    }

    /// @notice returns the total voting power for an address at a given block number and timestamp
    /// @param account The address of the account to check
    /// @param timestamp The unix timestamp in seconds to check the balance at
    function getVotes(address account, uint256 timestamp) public view returns (uint256) {
        return xWell.getPastVotes(account, timestamp);
    }

    /// @notice Emits votes to be contabilized on MoomBeam Governor contract
    /// @param proposalId the proposal id
    function emitVotes(uint256 proposalId) external payable override {
        // Get the proposal
        MultichainProposal storage proposal = proposals[proposalId];


        // Check if proposal have not been emitted yet
        require(!proposal.emitted, "MultichainVoteCollection: votes already emitted");

        // Check if proposal end time has passed
        require(proposal.votingEndTime < block.timestamp, "MultichainVoteCollection: Voting has not ended yet");

        // Check if proposal collection end time has not passed
        require(
            proposal.votingCollectionEndTime >= block.timestamp,
            "MultichainVoteCollection: Voting collection phase has ended"
        );

        // Get votes
        MultichainVotes storage votes = proposal.votes;

        // Check if proposal has votes
        require(votes.totalVotes > 0, "MultichainVoteCollection: proposal has no votes");

        proposal.emitted = true;

        _bridgeOut(
            moombeanWormholeChainId, abi.encode(proposalId, votes.forVotes, votes.againstVotes, votes.abstainVotes)
        );

        emit VotesEmitted(proposalId, votes.forVotes, votes.againstVotes, votes.abstainVotes);
    }

    /// @notice bridge proposals from moonbeam
    /// @param sourceChain the chain id of the source chain
    /// @param payload the payload of the message, contains proposalId, votingStartTime, votingEndTime and voteCollectionEndTime
    function _bridgeIn(uint16 sourceChain, bytes memory payload) internal override {
        // Parse the payload and do the corresponding actions!
        (uint256 proposalId, uint256 votingStartTime, uint256 votingEndTime, uint256 votingCollectionEndTime) =
            abi.decode(payload, (uint256, uint256, uint256, uint256));

        require(
            sourceChain == moombeanWormholeChainId, "MultichainVoteCollection: accepts only proposals from moonbeam"
        );

        // Ensure proposalId is unique
        require(proposals[proposalId].votingStartTime == 0, "Proposal already exists");

        // Ensure votingStartTime is less than votingEndTime
        require(votingStartTime < votingEndTime, "Start time must be before end time");

        // Ensure votingEndTime is in the future
        require(votingEndTime > block.timestamp, "End time must be in the future");

        // Create the proposal
        MultichainProposal storage proposal = proposals[proposalId];
        proposal.votingStartTime = votingStartTime;
        proposal.votingEndTime = votingEndTime;
        proposal.votingCollectionEndTime = votingCollectionEndTime;

        // Emit the ProposalCreated event
        emit ProposalCreated(proposalId, votingStartTime, votingEndTime, votingCollectionEndTime);
    }

    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////
    //// ----------------- ADMIN ONLY ----------------- ////
    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////

    /// @notice remove trusted senders from external chains
    /// @param _trustedSenders array of trusted senders to remove
    function removeTrustedSenders(TrustedSender[] memory _trustedSenders) external onlyOwner {
        _removeTrustedSenders(_trustedSenders);
    }

    /// @notice add trusted senders from external chains
    /// @param _trustedSenders array of trusted senders to add
    function addTrustedSenders(TrustedSender[] memory _trustedSenders) external onlyOwner {
        _addTrustedSenders(_trustedSenders);
    }

    /// @notice set a gas limit for the relayer on the external chain
    /// should only be called if there is a change in gas prices on the external chain
    /// @param newGasLimit new gas limit to set
    function setGasLimit(uint96 newGasLimit) external onlyOwner {
        _setGasLimit(newGasLimit);
    }
}
