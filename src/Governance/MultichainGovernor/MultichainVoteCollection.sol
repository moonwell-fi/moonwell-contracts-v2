pragma solidity 0.8.19;

import {IWormhole} from "@protocol/Governance/IWormhole.sol";
import {IMultichainVoteCollection} from "@protocol/Governance/MultichainGovernor/IMultichainVoteCollection.sol";
import {Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// Upgradeable, constructor disables implementation
contract MultichainVoteCollection is IMultichainVoteCollection, Initializable {
    // Moonbeam Governor Contract Address
    // TODO get correct address
    address public moombeamGovernorAddress;
    IWormhole public immutable wormholeBridge;

    struct MultichainProposal {
        // unix timestamp when voting will start
        uint256 votingStartTime;
        // unix timestamp when voting will end
        uint256 votingEndTime;
        MultichainVotes votes;
    }

    struct MultichainVotes {
        // votes for the proposal
        uint256 forVotes;
        // votes against the proposal
        uint256 againstVotes;
        // votes that abstain
        uint256 abstainVotes;
    }

    /// @notice Values for votes
    uint8 public constant voteValueYes = 0;
    uint8 public constant voteValueNo = 1;
    uint8 public constant voteValueAbstain = 2;

    mapping(uint256 proposalId => MultichainProposal) public proposals;

    /// @notice logic contract cannot be initialized
    constructor() {
        _disableInitializers();
    }

    function initialize(address _moonbeamGovernorAddress, address wormholeCore) external initializer {
        moombeamGovernorAddress = _moonbeamGovernorAddress;
        wormholeBridge = IWormhole(wormholeCore);
    }

    /// @dev allows user to cast vote for a proposal
    function castVote(uint256 proposalId, uint8 voteValue) external {
        MultichainProposal storage proposal = proposals[proposalId];
        // Check if proposal start time has passed
        require(proposal.votingStartTime < block.timestamp, "Voting has not started yet");

        // Check if proposal end time has not passed
        require(proposal.votingEndTime > block.timestamp, "Voting has ended");

        uint256 votes = _getVotingPower(msg.sender, block.number);

        // 0: yes, 1: o, 2: abstain
        if (voteValue == voteValueYes) {
            proposal.votes.forVotes +=  votes;
        } else if (voteValue == voteValueNo) {
            proposal.votes.againstVotes +=  votes;
        } else if (voteValue == voteValueAbstain) {
            proposal.votes.abstainVotes += votes;
        } else {
            // Catch all. If an above case isn't matched then the value is not valid.
            revert("MultichainVoteCollection::castVote: invalid vote value");
        }
    }

    /// @dev Returns the number of votes for a given user
    /// queries xWELL only
    function _getVotingPower(address voter, uint256 blockNumber) internal view returns (uint256) {}

    /// @dev emits the vote VAA for a given proposal
    function emitVoteVAA(uint256 proposalId) external {}

    function createProposalId(bytes memory VAA) public {
        // This call accepts single VAAs and headless VAAs
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormholeBridge.parseAndVerifyVM(VAA);

        // Ensure VAA parsing verification succeeded.
        require(valid, reason);

        // Decode the payload
        (uint256 proposalId, uint256 votingStartTime, uint256 votingEndTime) =
            abi.decode(vm.payload, (uint256, uint256, uint256));

        // Get the emitter address
        // TODO check this casting
        address emitter = address(uint160(uint256(vm.emitterAddress)));

        // Call the internal createProposalId function
        _createProposalId(proposalId, votingStartTime, votingEndTime, emitter);
    }

    /// @dev allows MultichainGovernor to create a proposal ID
    /// TODO check if min time sanity checks are necessary
    function _createProposalId(uint256 proposalId, uint256 votingStartTime, uint256 votingEndTime, address emitter)
        internal
    {
        // Ensure the message is from the MultichainGovernor
        require(emitter == moombeamGovernorAddress, "Emitter is not MultichainGovernor");

        // Ensure proposalId is unique
        require(proposals[proposalId].votingStartTime == 0, "Proposal already exists");

        // Ensure votingStartTime is less than votingEndTime
        require(votingStartTime < votingEndTime, "Start time must be before end time");

        // Ensure votingEndTime is in the future
        require(votingEndTime > block.timestamp, "End time must be in the future");

        MultichainProposal storage proposal = proposals[proposalId];
        proposal.votingStartTime = votingStartTime;
        proposal.votingEndTime = votingEndTime;
    }
}
