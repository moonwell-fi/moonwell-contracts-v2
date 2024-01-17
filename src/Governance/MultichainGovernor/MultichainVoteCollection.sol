pragma solidity 0.8.19;

import {IMultichainVoteCollection} from "@protocol/Governance/MultichainGovernor/IMultichainVoteCollection.sol";
import {Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {IWormholeReceiver} from "@protocol/wormhole/IWormholeReceiver.sol";
import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";

/// Upgradeable, constructor disables implementation
contract MultichainVoteCollection is IMultichainVoteCollection, Ownable2StepUpgradeable, IWormholeReceiver {
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

    /// @notice Moombeam constants

    // @notice MoonBeam Governor Contract Address
    address public moomBeamGovernor;

    // @notice Moonbeam Chain Id
    uint256 public constant moonBeamChainId = 1284;

    /// @notice Wormhole constants

    // @notice Moonbeam Wormhole Chain Id
    uint16 public constant moonBeamWormholeChainId = 16;

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ------------------ SINGLE STORAGE SLOT ------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @dev packing these variables into a single slot saves a
    /// COLD SLOAD on bridge out operations.

    /// @notice gas limit for wormhole relayer, changeable incase gas prices change on MoomBeam network
    uint96 public gasLimit = 300_000;

    /// @notice address of the wormhole relayer cannot be changed by owner
    /// because the relayer contract is a proxy and should never change its address
    IWormholeRelayer public wormholeRelayer;

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// -------------------- STATE VARIABLES -------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice reference to the xWELL token
    xWELL public xWell;

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ----------------------- MAPPINGS ------------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @notice nonces that have already been processed
    mapping(bytes32 => bool) public processedNonces;

    /// @notice mapping from proposalId to MultichainProposal
    mapping(uint256 proposalId => MultichainProposal) public proposals;

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// ------------------------- EVENTS ------------------------ ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    // @notice An event emitted when a proposal is created
    event ProposalCreated(
        uint256 proposalId,
        uint256 votingStartTime,
        uint256 votingEndTime,
        uint256 votingCollectionEndTime
    );

    /// @notice emitted when the gas limit changes on the MoomBeam chain
    /// @param oldGasLimit old gas limit
    /// @param newGasLimit new gas limit
    event GasLimitUpdated(uint96 oldGasLimit, uint96 newGasLimit);

    /// @notice emitted when votes are emitted to the MoomBeam chain
    /// @param proposalId the proposal id
    /// @param forVotes number of votes for the proposal
    /// @param againstVotes number of votes against the proposal
    /// @param abstainVotes number of votes abstaining the proposal
    event VotesEmitted(
        uint256 proposalId,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 abstainVotes
    );

    /// @notice disable the initializer to stop governance hijacking
    /// and avoid selfdestruct attacks.
    constructor() {
        _disableInitializers();
    }

    /// @notice initialize the governor contract
    /// @param _xWell address of the xWELL token
    /// @param _moonBeamGovernor address of the moonbeam governor contract
    /// @param _wormholeRelayer address of the wormhole relayer
    function initialize(address _xWell, address _moonBeamGovernor, address _wormholeRelayer) external initializer {
        xWell = xWELL(_xWell);
        moomBeamGovernor = _moonBeamGovernor;
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);

        gasLimit = 300_000; /// @dev default starting gas limit for relayer 
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// ---------------- View Only Functions -------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice Estimate bridge cost to bridge out to a destination chain
    function bridgeCost() public view returns (uint256 gasCost) {
        (gasCost, ) = wormholeRelayer.quoteEVMDeliveryPrice(
                                                            moonBeamWormholeChainId,
                                                            0,
                                                            gasLimit
        );
    }

    /// @dev allows user to cast vote for a proposal
    function castVote(uint256 proposalId, uint8 voteValue) external {
        MultichainProposal storage proposal = proposals[proposalId];
        // Check if proposal start time has passed
        require(proposal.votingStartTime < block.timestamp, "Voting has not started yet");

        // Check if proposal end time has not passed
        require(proposal.votingEndTime > block.timestamp, "Voting has ended");

        uint256 votes = getVotes(msg.sender, block.timestamp);

        // 0: yes, 1: o, 2: abstain
        if (voteValue == VOTE_VALUE_YES) {
            proposal.votes.forVotes +=  votes;
        } else if (voteValue == VOTE_VALUE_NO) {
            proposal.votes.againstVotes +=  votes;
        } else if (voteValue == VOTE_VALUE_ABSTAIN) {
            proposal.votes.abstainVotes += votes;
        } else {
            // Catch all. If an above case isn't matched then the value is not valid.
            revert("MultichainVoteCollection::castVote: invalid vote value");
        }
    }

    /// @notice returns the total voting power for an address at a given block number and timestamp
    /// @param account The address of the account to check
    /// @param timestamp The unix timestamp in seconds to check the balance at
    function getVotes(
        address account,
        uint256 timestamp
    ) public view returns (uint256) {
        return xWell.getPastVotes(account, timestamp);
    }

    /// @notice Emits votes to be contabilized on MoomBeam Governor contract
    /// @param proposalId the proposal id
    function emitVotes(uint256 proposalId) external override payable {
        // Cost to bridge out to MoomBeam chain
        uint256 cost = bridgeCost();
        require(msg.value == cost, "WormholeBridge: cost not equal to quote");

        // Get the proposal
        MultichainProposal storage proposal = proposals[proposalId];

        // Check if proposal end time has passed
        require(proposal.votingCollectionEndTime < block.timestamp, "MultichainVoteCollection: Voting has not ended yet");

        // Check if proposal collection end time has not passed
        require(proposal.votingCollectionEndTime > block.timestamp, "MultichainVoteCollection: Voting collection phase has ended");

        // Get votes
        MultichainVotes storage votes = proposal.votes;

        // Send votes to MoomBeam chain
        wormholeRelayer.sendPayloadToEvm{value: cost}(
            moonBeamWormholeChainId,
            moomBeamGovernor,
            abi.encode(proposalId, votes.forVotes, votes.againstVotes, votes.abstainVotes),
            0, /// no receiver value allowed, only message passing
            gasLimit
        );

        emit VotesEmitted(proposalId, votes.forVotes, votes.againstVotes, votes.abstainVotes);
    }

    /// @notice callable only by the wormhole relayer
    /// @param payload the payload of the message, contains proposalId, votingStartTime, votingEndTime and voteCollectionEndTime
    /// additional vaas, unused parameter
    /// @param senderAddress the address of the sender on the source chain, bytes32 encoded
    /// @param sourceChain the chain id of the source chain
    /// @param nonce the unique message ID
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory, // additionalVaas
        bytes32 senderAddress,
        uint16 sourceChain,
        bytes32 nonce
    ) external payable override {
        require(msg.value == 0, "MultichainVoteCollection: no value allowed");
        require(
            msg.sender == address(wormholeRelayer),
            "MultichainVoteCollection: only relayer allowed"
        );
        address senderAddressDecoded = address(uint160(uint256(senderAddress)));
         require(moomBeamGovernor == senderAddressDecoded, "MultichainVoteCollection: sender address is not moonbeam governor");
        require(
            !processedNonces[nonce],
            "MultichainVoteCollection: message already processed"
        );

        processedNonces[nonce] = true;

        // Parse the payload and do the corresponding actions!
        (uint256 proposalId, uint256 votingStartTime, uint256 votingEndTime, uint256 votingCollectionEndTime) =
            abi.decode(payload, (uint256, uint256, uint256, uint256));

        /// mint tokens and emit events
        _createProposal(proposalId, votingStartTime, votingEndTime, votingCollectionEndTime);
    }

    /// @dev allows MultichainGovernor to create a proposal ID
    function _createProposal(uint256 proposalId, uint256 votingStartTime, uint256 votingEndTime, uint256 votingCollectionEndTime) internal {
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

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// ---------------- Admin Only Functions ------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice set a gas limit for the relayer on the MoomBeam chain
    /// should only be called if there is a change in gas prices on the MoomBeam chain
    /// @param newGasLimit new gas limit to set
    function setGasLimit(uint96 newGasLimit) external onlyOwner {
        uint96 oldGasLimit = gasLimit;
        gasLimit = newGasLimit;

        emit GasLimitUpdated(oldGasLimit, newGasLimit);
    }

}
