pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {IMultichainGovernor, MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {MultichainVoteCollection} from "@protocol/Governance/MultichainGovernor/MultichainVoteCollection.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Constants} from "@protocol/Governance/MultichainGovernor/Constants.sol";

import {MultichainBaseTest} from "@test/helper/MultichainBaseTest.t.sol";

contract MultichainVoteCollectionUnitTest is MultichainBaseTest {
    function setUp() public override {
        super.setUp();

        xwell.delegate(address(this));
        well.delegate(address(this));
        distributor.delegate(address(this));
        stkWell.delegate(address(this));

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }

    function testSetup() public {
        assertEq(
            governor.getVotes(
                address(this),
                block.timestamp - 1,
                block.number - 1
            ),
            20_000_000_000 * 1e18,
            "incorrect vote amount"
        );

        assertEq(address(voteCollection.xWell()), address(xwell));
        assertEq(address(voteCollection.stkWell()), address(xwell)); /// TODO change this once PR merges

        assertEq(
            address(governor.wormholeRelayer()),
            address(wormholeRelayerAdapter),
            "incorrect wormhole relayer"
        );
        assertTrue(
            governor.isTrustedSender(moonbeamChainId, address(voteCollection)),
            "voteCollection not whitelisted to send messages in"
        );
        assertTrue(
            governor.isCrossChainVoteCollector(
                moonbeamChainId,
                address(voteCollection)
            ),
            "voteCollection not whitelisted to send messages in"
        );

        assertTrue(governor.bridgeCostAll() != 0, "no targets");

        assertEq(
            governor.getAllTargetChains().length,
            1,
            "incorrect target chains length"
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
        string
            memory description = "Proposal MIP-M00 - Update Proposal Threshold";

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "updateProposalThreshold(uint256)",
            100_000_000 * 1e18
        );

        uint256 startProposalCount = governor.proposalCount();
        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        uint256 endProposalCount = governor.proposalCount();

        assertEq(
            startProposalCount + 1,
            endProposalCount,
            "proposal count incorrect"
        );
        assertEq(proposalId, endProposalCount, "proposal id incorrect");
        assertTrue(governor.proposalActive(proposalId), "proposal not active");

        {
            (
                uint256 snapshotStartTimestamp,
                uint256 votingStartTime,
                uint256 endTimestamp,
                uint256 crossChainVoteCollectionEndTimestamp,
                ,
                ,
                ,

            ) = voteCollection.proposalInformation(proposalId);
            (
                ,
                uint256 snapshotStartTimestampGov,
                uint256 votingStartTimeGov,
                uint256 endTimestampGov,
                uint256 crossChainVoteCollectionEndTimestampGov,
                ,
                ,
                ,

            ) = governor.proposalInformation(proposalId);

            assertEq(
                snapshotStartTimestamp,
                snapshotStartTimestampGov,
                "incorrect snapshot start timestamp"
            );
            assertEq(
                votingStartTime,
                votingStartTimeGov,
                "incorrect voting start time"
            );
            assertEq(endTimestamp, endTimestampGov, "incorrect end timestamp");
            assertEq(
                crossChainVoteCollectionEndTimestamp,
                crossChainVoteCollectionEndTimestampGov,
                "incorrect cross chain vote collection end timestamp"
            );
        }

        uint256[] memory proposals = governor.liveProposals();

        bool proposalFound;

        for (uint256 i = 0; i < proposals.length; i++) {
            if (proposals[i] == proposalId) {
                proposalFound = true;
                break;
            }
        }

        assertTrue(proposalFound, "proposal not found in live proposals");

        return proposalId;
    }

    /// Voting on MultichainGovernor

    function testVotingValidProposalIdSucceeds()
        public
        returns (uint256 proposalId)
    {
        proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.warp(block.timestamp + governor.votingDelay() + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            1,
            "incorrect state, not active"
        );

        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_YES);

        (bool hasVoted, , ) = voteCollection.getReceipt(
            proposalId,
            address(this)
        );
        assertTrue(hasVoted, "user did not vote");

        (
            uint256 totalVotes,
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 votesAbstain
        ) = voteCollection.proposalVotes(proposalId);

        assertEq(votesFor, 5_000_000_000 * 1e18, "votes for incorrect");
        assertEq(votesAgainst, 0, "votes against incorrect");
        assertEq(votesAbstain, 0, "abstain votes incorrect");
        assertEq(votesFor, totalVotes, "total votes incorrect");
    }

    /// cannot vote twice on the same proposal

    function testVotingTwiceSameProposalFails() public {
        uint256 proposalId = testVotingValidProposalIdSucceeds();

        vm.expectRevert("MultichainVoteCollection: voter already voted");
        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_YES);
    }

    function testVotingValidProposalIdInvalidVoteValueFails()
        public
        returns (uint256 proposalId)
    {
        proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.warp(block.timestamp + governor.votingDelay() + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            1,
            "incorrect state, not active"
        );

        vm.expectRevert("MultichainVoteCollection: invalid vote value");
        voteCollection.castVote(proposalId, 3);
    }

    function testVotingPendingProposalIdFails()
        public
        returns (uint256 proposalId)
    {
        proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.warp(block.timestamp + governor.votingDelay());

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not pending"
        );

        vm.expectRevert("MultichainVoteCollection: Voting has not started yet");
        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_NO);
    }

    function testVotingPastVoteEndTimeProposalFails()
        public
        returns (uint256 proposalId)
    {
        proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.warp(
            block.timestamp +
                governor.votingDelay() +
                governor.votingPeriod() +
                1
        );

        assertEq(
            uint256(governor.state(proposalId)),
            2,
            "incorrect state, not in crosschain vote collection period"
        );

        vm.expectRevert("MultichainVoteCollection: Voting has ended");
        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_NO);
    }

    function testVotingInvalidVoteValueFails()
        public
        returns (uint256 proposalId)
    {
        proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.warp(block.timestamp + governor.votingDelay() + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            1,
            "incorrect state, not active"
        );

        vm.expectRevert("MultichainVoteCollection: invalid vote value");
        voteCollection.castVote(proposalId, 3);
    }

    function testVotingNoVotesFails() public returns (uint256 proposalId) {
        proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.warp(block.timestamp + governor.votingDelay() + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            1,
            "incorrect state, not active"
        );

        vm.expectRevert("MultichainVoteCollection: voter has no votes");
        vm.prank(address(1));
        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_YES);
    }

    /// Multiple users all voting on the same proposal

    /// WELL
    function testMultipleUserVoteWellSucceeds() public {
        address user1 = address(1);
        address user2 = address(2);
        address user3 = address(3);
        uint256 voteAmount = 1_000_000 * 1e18;

        xwell.transfer(user1, voteAmount);
        xwell.transfer(user2, voteAmount);
        xwell.transfer(user3, voteAmount);

        vm.prank(user1);
        xwell.delegate(user1);

        vm.prank(user2);
        xwell.delegate(user2);

        vm.prank(user3);
        xwell.delegate(user3);

        /// include users before snapshot block
        vm.warp(block.timestamp + 1);

        uint256 snapshotTimestamp = block.timestamp - 1;
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.warp(block.timestamp + governor.votingDelay() + 1);

        vm.prank(user1);
        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_YES);

        vm.prank(user2);
        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_NO);

        vm.prank(user3);
        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_ABSTAIN);

        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = voteCollection
                .getReceipt(proposalId, user1);

            assertTrue(hasVoted, "user1 has not voted");
            assertEq(votes, voteAmount, "user1 has incorrect vote amount");
            assertEq(
                voteValue,
                Constants.VOTE_VALUE_YES,
                "user1 did not vote yes"
            );
        }

        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = voteCollection
                .getReceipt(proposalId, user2);

            assertTrue(hasVoted, "user2 has not voted");
            assertEq(votes, voteAmount, "user2 has incorrect vote amount");
            assertEq(
                voteValue,
                Constants.VOTE_VALUE_NO,
                "user2 did not vote no"
            );
        }

        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = voteCollection
                .getReceipt(proposalId, user3);

            assertTrue(hasVoted, "user3 has not voted");
            assertEq(votes, voteAmount, "user3 has incorrect vote amount");
            assertEq(
                voteValue,
                Constants.VOTE_VALUE_ABSTAIN,
                "user3 did not vote yes"
            );
        }

        {
            (
                uint256 snapshotStartTimestamp,
                uint256 votingStartTime,
                ,
                ,
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = voteCollection.proposalInformation(proposalId);

            assertEq(
                snapshotTimestamp,
                snapshotStartTimestamp,
                "snapshot timestamp incorrect"
            );
            assertEq(
                snapshotStartTimestamp + 1 + governor.votingDelay(),
                votingStartTime,
                "voting start time incorrect"
            );

            assertEq(
                totalVotes,
                forVotes + againstVotes + abstainVotes,
                "incorrect total votes"
            );

            assertEq(totalVotes, 3 * voteAmount, "incorrect total votes");
            assertEq(forVotes, voteAmount, "incorrect for votes");
            assertEq(againstVotes, voteAmount, "incorrect against votes");
            assertEq(abstainVotes, voteAmount, "incorrect abstain votes");
        }
    }

    function testMultipleUserVoteWithWellDelegationSucceeds() public {
        uint256 voteAmount = 1_000_000 * 1e18;

        address user1 = address(1);
        address user2 = address(2);
        address user3 = address(3);
        address user4 = address(4);

        xwell.transfer(address(user1), 1_000_000 * 1e18);
        xwell.transfer(address(user3), 1_000_000 * 1e18);

        vm.prank(user1);
        xwell.delegate(user2);

        vm.prank(user3);
        xwell.delegate(user4);

        vm.warp(block.timestamp + 1);

        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not pending"
        );

        vm.warp(block.timestamp + governor.votingDelay() + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            1,
            "incorrect state, not active"
        );

        vm.prank(user2);
        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_NO);

        vm.prank(user4);
        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_ABSTAIN);

        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = voteCollection
                .getReceipt(proposalId, user2);

            assertTrue(hasVoted, "user2 has not voted");
            assertEq(votes, voteAmount, "user2 has incorrect vote amount");
            assertEq(
                voteValue,
                Constants.VOTE_VALUE_NO,
                "user2 did not vote no"
            );
        }
        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = voteCollection
                .getReceipt(proposalId, user4);

            assertTrue(hasVoted, "user4 has not voted");
            assertEq(votes, voteAmount, "user4 has incorrect vote amount");
            assertEq(
                voteValue,
                Constants.VOTE_VALUE_ABSTAIN,
                "user4 did not vote no"
            );
        }

        (
            ,
            ,
            ,
            ,
            uint256 totalVotes,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 abstainVotes
        ) = voteCollection.proposalInformation(proposalId);

        assertEq(
            totalVotes,
            forVotes + againstVotes + abstainVotes,
            "incorrect total votes"
        );

        assertEq(totalVotes, 2 * voteAmount, "incorrect total votes");
        assertEq(forVotes, 0, "incorrect for votes");
        assertEq(againstVotes, voteAmount, "incorrect against votes");
        assertEq(abstainVotes, voteAmount, "incorrect abstain votes");
    }

    /// xWELL
    function testMultipleUserVotexWellSucceeds() public {
        address user1 = address(1);
        address user2 = address(2);
        address user3 = address(3);
        uint256 voteAmount = 1_000_000 * 1e18;

        xwell.transfer(user1, voteAmount);
        xwell.transfer(user2, voteAmount);
        xwell.transfer(user3, voteAmount);

        vm.prank(user1);
        xwell.delegate(user1);

        vm.prank(user2);
        xwell.delegate(user2);

        vm.prank(user3);
        xwell.delegate(user3);

        /// include users before snapshot timestamp
        vm.warp(block.timestamp + 1);

        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not pending"
        );

        vm.warp(block.timestamp + governor.votingDelay() + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            1,
            "incorrect state, not active"
        );

        vm.prank(user1);
        governor.castVote(proposalId, Constants.VOTE_VALUE_YES);

        vm.prank(user2);
        governor.castVote(proposalId, Constants.VOTE_VALUE_NO);

        vm.prank(user3);
        governor.castVote(proposalId, Constants.VOTE_VALUE_ABSTAIN);

        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = governor
                .getReceipt(proposalId, user1);

            assertTrue(hasVoted, "user1 has not voted");
            assertEq(votes, voteAmount, "user1 has incorrect vote amount");
            assertEq(
                voteValue,
                Constants.VOTE_VALUE_YES,
                "user1 did not vote yes"
            );
        }
        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = governor
                .getReceipt(proposalId, user2);

            assertTrue(hasVoted, "user2 has not voted");
            assertEq(votes, voteAmount, "user2 has incorrect vote amount");
            assertEq(
                voteValue,
                Constants.VOTE_VALUE_NO,
                "user2 did not vote no"
            );
        }
        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = governor
                .getReceipt(proposalId, user3);

            assertTrue(hasVoted, "user3 has not voted");
            assertEq(votes, voteAmount, "user3 has incorrect vote amount");
            assertEq(
                voteValue,
                Constants.VOTE_VALUE_ABSTAIN,
                "user3 did not vote yes"
            );
        }

        (
            ,
            ,
            ,
            ,
            ,
            uint256 totalVotes,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 abstainVotes
        ) = governor.proposalInformation(proposalId);

        assertEq(
            totalVotes,
            forVotes + againstVotes + abstainVotes,
            "incorrect total votes"
        );

        assertEq(totalVotes, 3 * voteAmount, "incorrect total votes");
        assertEq(forVotes, voteAmount, "incorrect for votes");
        assertEq(againstVotes, voteAmount, "incorrect against votes");
        assertEq(abstainVotes, voteAmount, "incorrect abstain votes");
    }

    function testMultipleUserVoteWithxWellDelegationSucceeds() public {
        uint256 voteAmount = 1_000_000 * 1e18;

        address user1 = address(1);
        address user2 = address(2);
        address user3 = address(3);
        address user4 = address(4);

        xwell.transfer(user1, voteAmount);
        xwell.transfer(user3, voteAmount);

        vm.prank(user1);
        xwell.delegate(user2);

        vm.prank(user3);
        xwell.delegate(user4);

        vm.warp(block.timestamp + 1);

        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not pending"
        );

        vm.warp(block.timestamp + governor.votingDelay() + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            1,
            "incorrect state, not active"
        );

        vm.prank(user2);
        governor.castVote(proposalId, Constants.VOTE_VALUE_NO);

        vm.prank(user4);
        governor.castVote(proposalId, Constants.VOTE_VALUE_ABSTAIN);

        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = governor
                .getReceipt(proposalId, user2);

            assertTrue(hasVoted, "user2 has not voted");
            assertEq(votes, voteAmount, "user2 has incorrect vote amount");
            assertEq(
                voteValue,
                Constants.VOTE_VALUE_NO,
                "user2 did not vote no"
            );
        }
        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = governor
                .getReceipt(proposalId, user4);

            assertTrue(hasVoted, "user4 has not voted");
            assertEq(votes, voteAmount, "user4 has incorrect vote amount");
            assertEq(
                voteValue,
                Constants.VOTE_VALUE_ABSTAIN,
                "user4 did not vote abstain"
            );
        }

        (
            ,
            ,
            ,
            ,
            ,
            uint256 totalVotes,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 abstainVotes
        ) = governor.proposalInformation(proposalId);

        assertEq(
            totalVotes,
            forVotes + againstVotes + abstainVotes,
            "incorrect total votes"
        );

        assertEq(totalVotes, 2 * voteAmount, "incorrect total votes");
        assertEq(forVotes, 0, "incorrect for votes");
        assertEq(againstVotes, voteAmount, "incorrect against votes");
        assertEq(abstainVotes, voteAmount, "incorrect abstain votes");
    }

    /// Voting on MultichainVoteCollection
}
