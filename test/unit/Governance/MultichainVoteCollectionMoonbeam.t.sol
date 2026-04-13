pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@protocol/utils/ChainIds.sol";

import {BASE_WORMHOLE_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID} from "@utils/ChainIds.sol";
import {IMultichainGovernorV2} from "@protocol/governance/multichain/IMultichainGovernorV2.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {MultichainVoteCollectionMoonbeam} from "@protocol/governance/multichain/MultichainVoteCollectionMoonbeam.sol";
import {WormholeBridgeBase} from "@protocol/wormhole/WormholeBridgeBase.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Constants} from "@protocol/governance/multichain/Constants.sol";

import {MultichainBaseTestV2} from "@test/helper/MultichainBaseTestV2.t.sol";

/// @notice Unit tests for MultichainVoteCollectionMoonbeam
/// This is the Moonbeam-specific version that uses MultichainVoteCollectionMoonbeam
/// Inherits from MultichainBaseTestV2 which deploys both V2 and Moonbeam versions
contract MultichainVoteCollectionMoonbeamUnitTest is MultichainBaseTestV2 {
    bool private _receivingFunds;

    event CrossChainVoteCollected(
        uint256 proposalId,
        uint16 sourceChain,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 abstainVotes
    );

    function setUp() public override {
        super.setUp();
        _receivingFunds = false;

        // Switch the governor to use voteCollectionMoonbeam instead of voteCollection
        WormholeTrustedSender.TrustedSender[]
            memory trustedSenders = new WormholeTrustedSender.TrustedSender[](
                1
            );
        trustedSenders[0].chainId = BASE_WORMHOLE_CHAIN_ID;
        trustedSenders[0].addr = address(voteCollection);

        // Remove the V2 vote collection
        vm.prank(address(governor));
        governor.removeExternalChainConfigs(trustedSenders);

        // Add the Moonbeam vote collection
        trustedSenders[0].addr = address(voteCollectionMoonbeam);
        vm.prank(address(governor));
        governor.addExternalChainConfigs(trustedSenders);
    }

    function testSetup() public view {
        assertEq(
            votingPowerAggregator.getVotes(address(this), block.timestamp - 1),
            4_000_000_000 * 1e18,
            "incorrect vote amount"
        );
        assertEq(
            voteCollectionMoonbeam.getVotes(address(this), block.timestamp - 1),
            4_000_000_000 * 1e18,
            "incorrect vote amount"
        );

        // Vote collection has its own VotingPowerAggregator, different from governor's
        assertFalse(
            address(voteCollectionMoonbeam.votingPower()) ==
                address(votingPowerAggregator),
            "vote collection should have its own voting power aggregator"
        );
        assertTrue(
            address(voteCollectionMoonbeam.votingPower()) != address(0),
            "vote collection voting power aggregator should be set"
        );

        assertEq(
            address(governor.wormhole()),
            address(wormholeRelayerAdapter),
            "incorrect wormhole"
        );
        assertTrue(
            voteCollectionMoonbeam.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                address(governor)
            ),
            "governor not whitelisted to send messages in"
        );

        assertTrue(governor.getAllTargetChainsLength() > 0, "no targets");

        assertEq(
            governor.getAllTargetChains().length,
            1,
            "incorrect target chains length"
        );

        assertEq(
            voteCollectionMoonbeam.owner(),
            address(this),
            "incorrect owner"
        );
    }

    /// Proposing on MultichainGovernor

    function testProposeUpdateProposalThresholdSucceeds()
        public
        returns (uint256)
    {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory descriptionUri = "ipfs://proposal123";

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "updateProposalThreshold(uint256)",
            100_000_000 * 1e18
        );

        uint256 startProposalCount = governor.proposalCount();
        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        vm.recordLogs();
        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            descriptionUri,
            true // finalize
        );

        uint256 endProposalCount = governor.proposalCount();

        assertEq(
            startProposalCount + 1,
            endProposalCount,
            "proposal count incorrect"
        );
        assertEq(proposalId, endProposalCount, "proposal id incorrect");
        assertTrue(governor.proposalActive(proposalId), "proposal not active");

        _deliverBridgeOutEvents(address(governor));

        {
            IMultichainGovernorV2.ProposalInformation
                memory voteCollectionInfo = _getVoteCollectionProposalInformation(
                    proposalId
                );

            IMultichainGovernorV2.ProposalInformation
                memory governorInfo = governor.proposalInformationStruct(
                    proposalId
                );

            assertEq(
                voteCollectionInfo.voteSnapshotTimestamp,
                governorInfo.voteSnapshotTimestamp,
                "vote snapshot timestamp incorrect"
            );
            assertEq(
                voteCollectionInfo.votingStartTime,
                governorInfo.votingStartTime,
                "voting start time incorrect"
            );
            assertEq(
                voteCollectionInfo.votingEndTime,
                governorInfo.votingEndTime,
                "voting end time incorrect"
            );
            assertEq(
                voteCollectionInfo.crossChainVoteCollectionEndTimestamp,
                governorInfo.crossChainVoteCollectionEndTimestamp,
                "cross chain vote collection end timestamp incorrect"
            );
        }

        return proposalId;
    }

    function testCastVoteSucceeds() public {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        voteCollectionMoonbeam.castVote(proposalId, Constants.VOTE_VALUE_YES);

        (bool hasVoted, uint8 voteValue, uint256 votes) = voteCollectionMoonbeam
            .getReceipt(proposalId, address(this));

        assertTrue(hasVoted, "user has not voted");
        assertEq(voteValue, Constants.VOTE_VALUE_YES, "vote value incorrect");
        assertEq(votes, 4_000_000_000 * 1e18, "votes incorrect, should be 4b");

        (
            ,
            ,
            ,
            ,
            uint256 totalVotes,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 abstainVotes
        ) = voteCollectionMoonbeam.proposalInformation(proposalId);

        assertEq(totalVotes, 4_000_000_000 * 1e18, "total votes incorrect");
        assertEq(forVotes, 4_000_000_000 * 1e18, "for votes incorrect");
        assertEq(againstVotes, 0, "against votes incorrect");
        assertEq(abstainVotes, 0, "abstain votes incorrect");
    }

    function testEmitVotesSucceeds() public {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        voteCollectionMoonbeam.castVote(proposalId, Constants.VOTE_VALUE_YES);

        // Warp past voting end time
        vm.warp(block.timestamp + votingPeriodSeconds + 1);

        uint256 bridgeCost = voteCollectionMoonbeam.bridgeCostAll();

        // Enable receiving funds for refund
        _receivingFunds = true;
        vm.deal(address(this), bridgeCost);

        voteCollectionMoonbeam.emitVotes{value: bridgeCost}(proposalId);

        _receivingFunds = false;

        // Verify votes were emitted (would be received by governor in real scenario)
    }

    function testCastVoteFailsBeforeVotingStarts() public {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        // Get voting start time and explicitly warp to BEFORE it
        (, uint256 votingStartTime, , , , , , ) = voteCollectionMoonbeam
            .proposalInformation(proposalId);

        // Ensure we're before voting starts
        if (block.timestamp >= votingStartTime) {
            vm.warp(votingStartTime - 1);
        }

        // Try to vote before voting starts
        vm.expectRevert(
            "MultichainVoteCollectionV2: Voting has not started yet"
        );
        voteCollectionMoonbeam.castVote(proposalId, Constants.VOTE_VALUE_YES);
    }

    function testCastVoteFailsAfterVotingEnds() public {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        // Warp past voting end time
        vm.warp(block.timestamp + votingPeriodSeconds + 2);

        vm.expectRevert("MultichainVoteCollectionV2: Voting has ended");
        voteCollectionMoonbeam.castVote(proposalId, Constants.VOTE_VALUE_YES);
    }

    function testCastVoteFailsIfAlreadyVoted() public {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        voteCollectionMoonbeam.castVote(proposalId, Constants.VOTE_VALUE_YES);

        // Try to vote again
        vm.expectRevert("MultichainVoteCollectionV2: voter already voted");
        voteCollectionMoonbeam.castVote(proposalId, Constants.VOTE_VALUE_NO);
    }

    function testEmitVotesFailsBeforeVotingEnds() public {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        voteCollectionMoonbeam.castVote(proposalId, Constants.VOTE_VALUE_YES);

        uint256 bridgeCost = voteCollectionMoonbeam.bridgeCostAll();

        // Enable receiving funds for refund
        _receivingFunds = true;
        vm.deal(address(this), bridgeCost);

        vm.expectRevert("MultichainVoteCollectionV2: Voting has not ended");
        voteCollectionMoonbeam.emitVotes{value: bridgeCost}(proposalId);

        _receivingFunds = false;
    }

    function testSetGasLimitDeprecated() public {
        uint96 newGasLimit = Constants.MIN_GAS_LIMIT;
        vm.expectRevert("deprecated");
        voteCollectionMoonbeam.setGasLimit(newGasLimit);
    }

    /// Helper functions

    function _getVoteCollectionProposalInformation(
        uint256 proposalId
    )
        internal
        view
        override
        returns (IMultichainGovernorV2.ProposalInformation memory info)
    {
        (
            info.voteSnapshotTimestamp,
            info.votingStartTime,
            info.votingEndTime,
            info.crossChainVoteCollectionEndTimestamp,
            info.totalVotes,
            info.forVotes,
            info.againstVotes,
            info.abstainVotes
        ) = voteCollectionMoonbeam.proposalInformation(proposalId);
    }

    receive() external payable {
        if (!_receivingFunds) {
            revert("not accepting funds");
        }
    }
}
