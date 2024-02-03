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
            14_000_000_000 * 1e18,
            "incorrect vote amount"
        );
        assertEq(
            governor.gasLimit(),
            Constants.MIN_GAS_LIMIT,
            "incorrect gas limit vote collection"
        );
        assertEq(
            voteCollection.gasLimit(),
            Constants.MIN_GAS_LIMIT,
            "incorrect gas limit vote collection"
        );
        assertEq(
            voteCollection.getVotes(address(this), block.timestamp - 1),
            4_000_000_000 * 1e18,
            "incorrect vote amount"
        );

        assertEq(
            address(voteCollection.xWell()),
            address(xwell),
            "xwell incorrect"
        );
        assertEq(
            address(voteCollection.stkWell()),
            address(stkWellBase),
            "stkwell incorrect"
        );

        assertEq(
            address(governor.wormholeRelayer()),
            address(wormholeRelayerAdapter),
            "incorrect wormhole relayer"
        );
        assertTrue(
            voteCollection.isTrustedSender(moonbeamChainId, address(governor)),
            "governor not whitelisted to send messages in"
        );
        assertTrue(
            governor.isTrustedSender(baseChainId, address(voteCollection)),
            "voteCollection not whitelisted to send messages in"
        );

        assertTrue(governor.bridgeCostAll() != 0, "no targets");

        assertEq(
            governor.getAllTargetChains().length,
            1,
            "incorrect target chains length"
        );

        assertEq(voteCollection.owner(), address(this), "incorrect owner");
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
            IMultichainGovernor.ProposalInformation
                memory voteCollectionInfo = getVoteCollectionProposalInformation(
                    proposalId
                );

            IMultichainGovernor.ProposalInformation
                memory governorInfo = governor.proposalInformationStruct(
                    proposalId
                );

            assertEq(
                voteCollectionInfo.voteSnapshotTimestamp,
                governorInfo.voteSnapshotTimestamp,
                "incorrect snapshot start timestamp"
            );
            assertEq(
                voteCollectionInfo.votingStartTime,
                governorInfo.votingStartTime,
                "incorrect voting start time"
            );
            assertEq(
                voteCollectionInfo.votingEndTime,
                governorInfo.votingEndTime,
                "incorrect end timestamp"
            );
            assertEq(
                voteCollectionInfo.crossChainVoteCollectionEndTimestamp,
                governorInfo.crossChainVoteCollectionEndTimestamp,
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

    /// Voting on MultichainVoteCollection

    function testVotingValidProposalIdSucceeds()
        public
        returns (uint256 proposalId)
    {
        proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
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

        assertEq(votesFor, 4_000_000_000 * 1e18, "votes for incorrect");
        assertEq(votesAgainst, 0, "votes against incorrect");
        assertEq(votesAbstain, 0, "abstain votes incorrect");
        assertEq(votesFor, totalVotes, "total votes incorrect");
    }

    function testVotingValidProposalIdBeforeStartFails()
        public
        returns (uint256 proposalId)
    {
        proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.expectRevert("MultichainVoteCollection: Voting has not started yet");
        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_YES);
    }

    // voter has no votes
    function testVotingVoterHasNoVotes() public {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );
        vm.prank(address(1));
        vm.expectRevert("MultichainVoteCollection: voter has no votes");
        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_YES);
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

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        vm.expectRevert("MultichainVoteCollection: invalid vote value");
        voteCollection.castVote(proposalId, 3);
    }

    function testVotingActiveProposalIdSucceeds()
        public
        returns (uint256 proposalId)
    {
        proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_NO);
    }

    function testVotingPastVoteEndTimeProposalFails()
        public
        returns (uint256 proposalId)
    {
        proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            1,
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

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        vm.expectRevert("MultichainVoteCollection: invalid vote value");
        voteCollection.castVote(proposalId, 3);
    }

    function testVotingNoVotesFails() public returns (uint256 proposalId) {
        proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
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
        vm.roll(block.number + 1);

        uint256 snapshotTimestamp = block.timestamp - 1;
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

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
            IMultichainGovernor.ProposalInformation
                memory voteCollectionInfo = getVoteCollectionProposalInformation(
                    proposalId
                );

            assertEq(
                snapshotTimestamp,
                voteCollectionInfo.voteSnapshotTimestamp,
                "snapshot timestamp incorrect"
            );
            assertEq(
                voteCollectionInfo.voteSnapshotTimestamp + 1,
                voteCollectionInfo.votingStartTime,
                "voting start time incorrect"
            );

            assertEq(
                voteCollectionInfo.totalVotes,
                voteCollectionInfo.forVotes +
                    voteCollectionInfo.againstVotes +
                    voteCollectionInfo.abstainVotes,
                "incorrect total votes"
            );

            assertEq(
                voteCollectionInfo.totalVotes,
                3 * voteAmount,
                "incorrect total votes"
            );
            assertEq(
                voteCollectionInfo.forVotes,
                voteAmount,
                "incorrect for votes"
            );
            assertEq(
                voteCollectionInfo.againstVotes,
                voteAmount,
                "incorrect against votes"
            );
            assertEq(
                voteCollectionInfo.abstainVotes,
                voteAmount,
                "incorrect abstain votes"
            );
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
            "incorrect state, not active"
        );

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
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

        IMultichainGovernor.ProposalInformation
            memory voteCollectionInfo = getVoteCollectionProposalInformation(
                proposalId
            );

        assertEq(
            voteCollectionInfo.totalVotes,
            voteCollectionInfo.forVotes +
                voteCollectionInfo.againstVotes +
                voteCollectionInfo.abstainVotes,
            "incorrect total votes"
        );

        assertEq(
            voteCollectionInfo.totalVotes,
            2 * voteAmount,
            "incorrect total votes"
        );
        assertEq(voteCollectionInfo.forVotes, 0, "incorrect for votes");
        assertEq(
            voteCollectionInfo.againstVotes,
            voteAmount,
            "incorrect against votes"
        );
        assertEq(
            voteCollectionInfo.abstainVotes,
            voteAmount,
            "incorrect abstain votes"
        );
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
            "incorrect state, not active"
        );

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
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

        IMultichainGovernor.ProposalInformation memory governorInfo = governor
            .proposalInformationStruct(proposalId);

        assertEq(
            governorInfo.totalVotes,
            governorInfo.forVotes +
                governorInfo.againstVotes +
                governorInfo.abstainVotes,
            "incorrect total votes"
        );

        assertEq(
            governorInfo.totalVotes,
            3 * voteAmount,
            "incorrect total votes"
        );
        assertEq(governorInfo.forVotes, voteAmount, "incorrect for votes");
        assertEq(
            governorInfo.againstVotes,
            voteAmount,
            "incorrect against votes"
        );
        assertEq(
            governorInfo.abstainVotes,
            voteAmount,
            "incorrect abstain votes"
        );
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
            "incorrect state, not active"
        );

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
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

        IMultichainGovernor.ProposalInformation memory governorInfo = governor
            .proposalInformationStruct(proposalId);

        assertEq(
            governorInfo.totalVotes,
            governorInfo.forVotes +
                governorInfo.againstVotes +
                governorInfo.abstainVotes,
            "incorrect total votes"
        );

        assertEq(
            governorInfo.totalVotes,
            2 * voteAmount,
            "incorrect total votes"
        );
        assertEq(governorInfo.forVotes, 0, "incorrect for votes");
        assertEq(
            governorInfo.againstVotes,
            voteAmount,
            "incorrect against votes"
        );
        assertEq(
            governorInfo.abstainVotes,
            voteAmount,
            "incorrect abstain votes"
        );
    }

    // Emit votes to Governor
    function testEmitVotesToGovernorSucceeded()
        public
        returns (uint256 proposalId)
    {
        testMultipleUserVoteWellSucceeds();

        proposalId = governor.proposalCount();

        IMultichainGovernor.ProposalInformation
            memory proposalVoteCollection = getVoteCollectionProposalInformation(
                proposalId
            );

        // test at the last timestamp of the cross chain vote collection period
        vm.warp(proposalVoteCollection.crossChainVoteCollectionEndTimestamp);

        assertEq(
            uint256(governor.state(proposalId)),
            1,
            "incorrect state, not in crosschain vote collection period"
        );

        IMultichainGovernor.ProposalInformation memory proposalBefore = governor
            .proposalInformationStruct(proposalId);

        {
            uint256 bridgeCost = voteCollection.bridgeCost(moonbeamChainId);

            vm.deal(address(this), bridgeCost);

            voteCollection.emitVotes{value: bridgeCost}(proposalId);
        }

        IMultichainGovernor.ProposalInformation memory proposalAfter = governor
            .proposalInformationStruct(proposalId);

        assertEq(
            proposalAfter.totalVotes,
            proposalBefore.totalVotes + proposalVoteCollection.totalVotes,
            "incorrect total votes"
        );
        assertEq(
            proposalAfter.forVotes,
            proposalBefore.forVotes + proposalVoteCollection.forVotes,
            "incorrect for votes"
        );
        assertEq(
            proposalAfter.againstVotes,
            proposalBefore.againstVotes + proposalVoteCollection.againstVotes,
            "incorrect against votes"
        );
        assertEq(
            proposalAfter.abstainVotes,
            proposalBefore.abstainVotes + proposalVoteCollection.abstainVotes,
            "incorrect abstain votes"
        );
    }

    function testEmitVotesProposalHasNoVotes() public {
        testProposeUpdateProposalThresholdSucceeds();

        uint256 proposalId = governor.proposalCount();

        vm.expectRevert("MultichainVoteCollection: proposal has no votes");
        voteCollection.emitVotes(proposalId);
    }

    function testEmitVotesProposalEndTimeHasNotPassed() public {
        uint256 proposalId = testVotingValidProposalIdSucceeds();

        (, , uint256 endTimestamp, , , , , ) = voteCollection
            .proposalInformation(proposalId);

        // test at the last timestamp of vote period
        vm.warp(endTimestamp);

        vm.expectRevert("MultichainVoteCollection: Voting has not ended");
        voteCollection.emitVotes(proposalId);
    }

    function testEmitVotesProposalEndTimeHasPassedBridgeOutIncorrectAmount()
        public
    {
        uint256 proposalId = testVotingValidProposalIdSucceeds();

        (, , uint256 endTimestamp, , , , , ) = voteCollection
            .proposalInformation(proposalId);

        // test at the last timestamp of vote period
        vm.warp(endTimestamp + 1);

        uint256 cost = voteCollection.bridgeCost(
            voteCollection.moonbeamWormholeChainId()
        ) - 1;
        vm.deal(address(this), cost);

        vm.expectRevert("WormholeBridge: cost not equal to quote");
        voteCollection.emitVotes{value: cost}(proposalId);
    }

    function testEmitVotesProposalCollectionEndTimeHasPassed() public {
        uint256 proposalId = testVotingValidProposalIdSucceeds();

        IMultichainGovernor.ProposalInformation
            memory voteCollectionInfo = getVoteCollectionProposalInformation(
                proposalId
            );

        vm.warp(voteCollectionInfo.crossChainVoteCollectionEndTimestamp + 1);

        vm.expectRevert(
            "MultichainVoteCollection: Voting collection phase has ended"
        );
        voteCollection.emitVotes(proposalId);
    }

    /// Only Owner

    function testSetGasLimitOwnerSucceeds() public {
        uint96 gasLimit = Constants.MIN_GAS_LIMIT;
        voteCollection.setGasLimit(gasLimit);
        assertEq(voteCollection.gasLimit(), gasLimit, "incorrect gas limit");
    }

    function testSetGasLimitTooLow() public {
        uint96 gasLimit = Constants.MIN_GAS_LIMIT - 1;
        vm.expectRevert("MultichainVoteCollection: gas limit too low");
        voteCollection.setGasLimit(gasLimit);
    }

    function testSetGasLimitNonOwnerFails() public {
        uint96 gasLimit = Constants.MIN_GAS_LIMIT;
        vm.prank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        voteCollection.setGasLimit(gasLimit);
    }

    // VIEW FUNCTIONS

    function testGetChainAddresVotes() public {
        uint256 proposalId = testEmitVotesToGovernorSucceeded();

        uint256 voteAmount = 1_000_000 * 1e18;

        (
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 votesAbstain
        ) = governor.chainAddressVotes(proposalId, 30); // base chain id

        assertEq(votesFor, voteAmount, "votes for incorrect");
        assertEq(votesAgainst, voteAmount, "votes against incorrect");
        assertEq(votesAbstain, voteAmount, "abstain votes incorrect");
    }

    // bridge in

    function testBridgeInWrongSourceChain() public {
        bytes memory payload = abi.encode(0, 0, 0, 0, 0);
        uint256 gasCost = wormholeRelayerAdapter.nativePriceQuote();

        vm.deal(address(governor), gasCost);
        vm.prank(address(governor));
        vm.expectRevert("WormholeBridge: sender not trusted");
        wormholeRelayerAdapter.sendPayloadToEvm{value: gasCost}(
            moonbeamChainId, // pass moonbeam as the target chain so that relayer adapter do the flip
            address(voteCollection),
            payload,
            0,
            0
        );
    }

    function testBridgeInWrongPayloadLength() public {
        bytes memory payload = abi.encode(0, 0, 0, 0);
        uint256 gasCost = wormholeRelayerAdapter.nativePriceQuote();

        vm.deal(address(governor), gasCost);
        vm.prank(address(governor));
        vm.expectRevert("MultichainVoteCollection: invalid payload length");
        wormholeRelayerAdapter.sendPayloadToEvm{value: gasCost}(
            baseChainId,
            address(voteCollection),
            payload,
            0,
            0
        );
    }

    function testBridgeInProposalAlreadyExist() public {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        bytes memory payload = abi.encode(proposalId, 0, 0, 0, 0);
        uint256 gasCost = wormholeRelayerAdapter.nativePriceQuote();

        vm.deal(address(governor), gasCost);
        vm.prank(address(governor));
        vm.expectRevert("MultichainVoteCollection: proposal already exists");
        wormholeRelayerAdapter.sendPayloadToEvm{value: gasCost}(
            baseChainId,
            address(voteCollection),
            payload,
            0,
            0
        );
    }

    function testBridgeInVotingSnapshotTimeGreatherThanStartTime() public {
        bytes memory payload = abi.encode(0, 1, 0, 0, 0);
        uint256 gasCost = wormholeRelayerAdapter.nativePriceQuote();

        vm.deal(address(governor), gasCost);
        vm.prank(address(governor));
        vm.expectRevert(
            "MultichainVoteCollection: snapshot time must be before start time"
        );
        wormholeRelayerAdapter.sendPayloadToEvm{value: gasCost}(
            30,
            address(voteCollection),
            payload,
            0,
            0
        );
    }

    function testBridgeInVotingStartTimeGreatherThanVoteEndTime() public {
        bytes memory payload = abi.encode(0, 0, 1, 0, 0);
        uint256 gasCost = wormholeRelayerAdapter.nativePriceQuote();

        vm.deal(address(governor), gasCost);
        vm.prank(address(governor));
        vm.expectRevert(
            "MultichainVoteCollection: start time must be before end time"
        );
        wormholeRelayerAdapter.sendPayloadToEvm{value: gasCost}(
            30,
            address(voteCollection),
            payload,
            0,
            0
        );
    }

    function testBridgeInVotingEndTimeLessThanTimestamp() public {
        bytes memory payload = abi.encode(0, 0, 1, 2, 0);
        uint256 gasCost = wormholeRelayerAdapter.nativePriceQuote();

        vm.deal(address(governor), gasCost);
        vm.prank(address(governor));
        vm.expectRevert(
            "MultichainVoteCollection: end time must be in the future"
        );
        wormholeRelayerAdapter.sendPayloadToEvm{value: gasCost}(
            30,
            address(voteCollection),
            payload,
            0,
            0
        );
    }

    // test governor bridge in votes already collected here to reuse emit votes test
    function testBridgeInVotesAlreadyCollected() public {
        uint256 proposalId = testEmitVotesToGovernorSucceeded();

        bytes memory payload = abi.encode(proposalId, 0, 0, 0);
        uint256 gasCost = wormholeRelayerAdapter.nativePriceQuote();

        vm.deal(address(voteCollection), gasCost);
        vm.prank(address(voteCollection));
        vm.expectRevert("MultichainGovernor: vote already collected");
        wormholeRelayerAdapter.sendPayloadToEvm{value: gasCost}(
            moonbeamChainId,
            address(governor),
            payload,
            0,
            0
        );
    }
}
