pragma solidity 0.8.19;

import {IWormhole} from "@protocol/Governance/IWormhole.sol";
import { IMultichainVoteCollection } from "@protocol/Governance/IMultichainVoteCollection.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// Upgradeable, constructor disables implementation
 contract MultichainVoteCollection is TransparentUpgradeableProxy, IMultichainVoteCollection {
     
     // Moonbeam Governor Contract Address 
     // TODO get correct address
     address public moombeamGovernorAddress;

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

     constructor(address owner, bytes memory initdata) {
         TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
                                                                             address(this),
                                                                             owner,
                                                                             initdata
        );
 
     }

     function initializer(address _moonbeamGovernorAddress) public {
         moombeamGovernorAddress  = _moonbeamGovernorAddress;
     }
     
     /// @dev allows user to cast vote for a proposal
     function castVote(uint256 proposalId, uint8 voteValue) external {
         // Check if proposal start time has passed
         require(proposals[proposalId].votingStartTime < block.timestamp, "Voting has not started yet");

         // Check if proposal end time has not passed
         require(proposals[proposalId].votingEndTime > block.timestamp, "Voting has ended");
         
         // 0: yes, 1: o, 2: abstain
     }

     /// @dev Returns the number of votes for a given user
     /// queries xWELL only
     function getVotingPower(
                             address voter,
                             uint256 blockNumber
     ) external view returns (uint256) {

        
     }

     /// @dev emits the vote VAA for a given proposal
     function emitVoteVAA(uint256 proposalId) external {
        
     }

     function createProposalId(bytes memory VAA) public {
         // This call accepts single VAAs and headless VAAs
         (
          IWormhole.VM memory vm,
          bool valid,
          string memory reason
         ) = wormholeBridge.parseAndVerifyVM(VAA);

         // Ensure VAA parsing verification succeeded.
         require(valid, reason);

         // Decode the payload
         (uint256 proposalId, uint256 votingStartTime, uint256 votingEndTime) =
             abi.decode(vm.payload, (uint256, uint256, uint256));

         // Get the emitter address
         address emitter = vm.emitterAddress;

         // Call the internal createProposalId function
         _createProposalId(proposalId, votingStartTime, votingEndTime, emitter);
     }

     /// @dev allows MultichainGovernor to create a proposal ID
     /// @todo check if min time sanity checks are necessary
     function _createProposalId(uint256 proposalId, uint256 votingStartTime, uint256 votingEndTime, address emitter) internal {
         // Ensure the message is from the MultichainGovernor
         require(emitter == MOONBEAM_GOVERNOR_ADDRESS, "Emitter is not MultichainGovernor");

         // Ensure proposalId is unique
         require(proposals[proposalId].votingStartTime == 0, "Proposal already exists");

         // Ensure votingStartTime is less than votingEndTime
         require(votingStartTime < votingEndTime, "Start time must be before end time");

         // Ensure votingEndTime is in the future
         require(votingEndTime > block.timestamp, "End time must be in the future");

         MultichainProposal storage proposal = proposals[_proposal.proposalId];
         proposal.votingStartTime = votingStartTime;
         proposal.votingEndTime = votingEndTime;
     }
 }
