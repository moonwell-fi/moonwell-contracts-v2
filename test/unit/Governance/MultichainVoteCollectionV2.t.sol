pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@protocol/utils/ChainIds.sol";

import {BASE_WORMHOLE_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID} from "@utils/ChainIds.sol";
import {IMultichainGovernorV2} from "@protocol/governance/multichain/IMultichainGovernorV2.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {MultichainVoteCollectionV2} from "@protocol/governance/multichain/MultichainVoteCollectionV2.sol";
import {WormholeBridgeBase} from "@protocol/wormhole/WormholeBridgeBase.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Constants} from "@protocol/governance/multichain/Constants.sol";

import {MultichainBaseTestV2} from "@test/helper/MultichainBaseTestV2.t.sol";

contract MultichainVoteCollectionV2UnitTest is MultichainBaseTestV2 {
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
    }

    function testSetup() public view {
        assertEq(
            votingPowerAggregator.getVotes(address(this), block.timestamp - 1),
            4_000_000_000 * 1e18,
            "incorrect vote amount"
        );
        assertEq(
            voteCollection.getVotes(address(this), block.timestamp - 1),
            4_000_000_000 * 1e18,
            "incorrect vote amount"
        );

        // Vote collection has its own VotingPowerAggregator, different from governor's
        assertFalse(
            address(voteCollection.votingPower()) ==
                address(votingPowerAggregator),
            "vote collection should have its own voting power aggregator"
        );
        assertTrue(
            address(voteCollection.votingPower()) != address(0),
            "vote collection voting power aggregator should be set"
        );

        assertEq(
            address(governor.wormhole()),
            address(wormholeRelayerAdapter),
            "incorrect wormhole"
        );
        assertTrue(
            voteCollection.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                address(governor)
            ),
            "governor not whitelisted to send messages in"
        );
        assertTrue(
            governor.isTrustedSender(
                BASE_WORMHOLE_CHAIN_ID,
                address(voteCollection)
            ),
            "voteCollection not whitelisted to send messages in"
        );

        assertEq(
            governor.bridgeCostAll(),
            0,
            "bridgeCostAll should be 0 (messageFee)"
        );
        assertTrue(governor.getAllTargetChainsLength() > 0, "no targets");

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

        _assertGovernanceBalance();

        return proposalId;
    }

    /// Voting on MultichainVoteCollectionV2

    function testVotingValidProposalIdSucceeds()
        public
        returns (uint256 proposalId)
    {
        proposalId = _createProposalUpdateThreshold(address(this));

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        // get proposal vote snapshot timestamp from proposal information
        (uint256 voteSnapshotTimestamp, , , , , , , ) = voteCollection
            .proposalInformation(proposalId);

        // get user vote power
        uint256 votePower = voteCollection.getVotes(
            address(this),
            voteSnapshotTimestamp
        );

        // get proposal votes before voting
        (
            uint256 totalVotesBefore,
            uint256 votesForBefore,
            uint256 votesAgainstBefore,
            uint256 votesAbstainBefore
        ) = voteCollection.proposalVotes(proposalId);

        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_YES);

        (bool hasVoted, uint256 voteValue, uint256 voteAmount) = voteCollection
            .getReceipt(proposalId, address(this));
        assertTrue(hasVoted, "user did not vote");
        assertEq(voteValue, Constants.VOTE_VALUE_YES, "vote value incorrect");
        assertEq(voteAmount, votePower, "vote amount incorrect");

        (
            uint256 totalVotes,
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 votesAbstain
        ) = voteCollection.proposalVotes(proposalId);

        assertEq(votesFor, 4_000_000_000 * 1e18, "votes for incorrect");
        assertEq(votesFor - votesForBefore, voteAmount, "votes for incorrect");
        assertEq(votesAgainst, votesAgainstBefore, "votes against incorrect");
        assertEq(votesAbstain, votesAbstainBefore, "abstain votes incorrect");
        assertEq(
            totalVotes,
            totalVotesBefore + votePower,
            "total votes incorrect"
        );
        assertEq(votesFor, totalVotes, "total votes incorrect");

        _assertGovernanceBalance();
    }

    function testVotingValidProposalIdBeforeStartFails()
        public
        returns (uint256 proposalId)
    {
        proposalId = _createProposalUpdateThreshold(address(this));

        (, uint256 votingStartTime, , , , , , ) = voteCollection
            .proposalInformation(proposalId);

        vm.warp(votingStartTime - 1);
        vm.expectRevert(
            "MultichainVoteCollectionV2: Voting has not started yet"
        );
        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_YES);
    }

    // voter has no votes
    function testVotingVoterHasNoVotes() public {
        uint256 proposalId = _createProposalUpdateThreshold(address(this));

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );
        vm.prank(address(1));
        vm.expectRevert("MultichainVoteCollectionV2: voter has no votes");
        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_YES);

        _assertGovernanceBalance();
    }

    /// cannot vote twice on the same proposal
    function testVotingTwiceSameProposalFails() public {
        uint256 proposalId = testVotingValidProposalIdSucceeds();

        vm.expectRevert("MultichainVoteCollectionV2: voter already voted");
        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_YES);

        _assertGovernanceBalance();
    }

    function testVotingValidProposalIdInvalidVoteValueFails()
        public
        returns (uint256 proposalId)
    {
        proposalId = _createProposalUpdateThreshold(address(this));

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        vm.expectRevert("MultichainVoteCollectionV2: invalid vote value");
        voteCollection.castVote(proposalId, 3);

        _assertGovernanceBalance();
    }

    function testVotingActiveProposalIdSucceeds()
        public
        returns (uint256 proposalId)
    {
        proposalId = _createProposalUpdateThreshold(address(this));

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        // get proposal votes before cast
        (
            uint256 totalVotesBefore,
            uint256 votesForBefore,
            uint256 votesAgainstBefore,
            uint256 votesAbstainBefore
        ) = voteCollection.proposalVotes(proposalId);

        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_NO);

        (bool hasVoted, uint256 voteValue, uint256 voteAmount) = voteCollection
            .getReceipt(proposalId, address(this));

        assertTrue(hasVoted, "user did not vote");
        assertEq(voteValue, Constants.VOTE_VALUE_NO, "vote value incorrect");
        assertEq(voteAmount, 4_000_000_000 * 1e18, "vote amount incorrect");

        (
            uint256 totalVotes,
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 votesAbstain
        ) = voteCollection.proposalVotes(proposalId);

        assertEq(votesAgainst, 4_000_000_000 * 1e18, "votes against incorrect");
        assertEq(
            votesAgainst - votesAgainstBefore,
            4_000_000_000 * 1e18,
            "votes against incorrect"
        );
        assertEq(votesFor, votesForBefore, "votes for incorrect");
        assertEq(votesAbstain, votesAbstainBefore, "abstain votes incorrect");
        assertEq(
            totalVotes,
            totalVotesBefore + 4_000_000_000 * 1e18,
            "total votes incorrect"
        );
        assertEq(votesAgainst, totalVotes, "total votes incorrect");

        _assertGovernanceBalance();
    }

    function testVotingPastVoteEndTimeProposalFails()
        public
        returns (uint256 proposalId)
    {
        proposalId = _createProposalUpdateThreshold(address(this));

        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            1,
            "incorrect state, not in crosschain vote collection period"
        );

        vm.expectRevert("MultichainVoteCollectionV2: Voting has ended");
        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_NO);

        _assertGovernanceBalance();
    }

    function testVotingInvalidVoteValueFails()
        public
        returns (uint256 proposalId)
    {
        proposalId = _createProposalUpdateThreshold(address(this));

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        vm.expectRevert("MultichainVoteCollectionV2: invalid vote value");
        voteCollection.castVote(proposalId, 3);

        _assertGovernanceBalance();
    }

    function testVotingNoVotesFails() public returns (uint256 proposalId) {
        proposalId = _createProposalUpdateThreshold(address(this));

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        vm.expectRevert("MultichainVoteCollectionV2: voter has no votes");
        vm.prank(address(1));
        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_YES);

        _assertGovernanceBalance();
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

        /// include users before snapshot timestamp
        vm.warp(block.timestamp + 1);

        uint256 snapshotTimestamp = block.timestamp - 1;
        uint256 proposalId = _createProposalUpdateThreshold(address(this));

        // get proposal votes before
        (
            uint256 totalVotesBefore,
            uint256 votesForBefore,
            uint256 votesAgainstBefore,
            uint256 votesAbstainBefore
        ) = voteCollection.proposalVotes(proposalId);

        vm.warp(block.timestamp + 1);

        {
            vm.prank(user1);
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_YES);

            // check proposal votes after
            (
                uint256 totalVotes,
                uint256 votesFor,
                uint256 votesAgainst,
                uint256 votesAbstain
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(votesFor, voteAmount, "votes for incorrect");
            assertEq(
                votesFor - votesForBefore,
                voteAmount,
                "votes for incorrect"
            );
            assertEq(
                votesAgainst,
                votesAgainstBefore,
                "votes against incorrect"
            );
            assertEq(
                votesAbstain,
                votesAbstainBefore,
                "abstain votes incorrect"
            );
            assertEq(
                totalVotes,
                totalVotesBefore + voteAmount,
                "total votes incorrect"
            );
        }

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
            vm.prank(user2);
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_NO);

            // check proposal votes after
            (
                uint256 totalVotes,
                uint256 votesFor,
                uint256 votesAgainst,
                uint256 votesAbstain
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(votesAgainst, voteAmount, "votes against incorrect");
            assertEq(
                votesAgainst - votesAgainstBefore,
                voteAmount,
                "votes against incorrect"
            );
            assertEq(votesFor, voteAmount, "votes for incorrect");
            assertEq(
                votesAbstain,
                votesAbstainBefore,
                "abstain votes incorrect"
            );
            assertEq(
                totalVotes,
                totalVotesBefore + voteAmount * 2,
                "total votes incorrect"
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
            vm.prank(user3);
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_ABSTAIN);

            // check proposal votes after
            (
                uint256 totalVotes,
                uint256 votesFor,
                uint256 votesAgainst,
                uint256 votesAbstain
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(votesAbstain, voteAmount, "abstain votes incorrect");
            assertEq(
                votesAbstain - votesAbstainBefore,
                voteAmount,
                "abstain votes incorrect"
            );
            assertEq(votesFor, voteAmount, "votes for incorrect");
            assertEq(votesAgainst, voteAmount, "votes against incorrect");
            assertEq(
                totalVotes,
                totalVotesBefore + voteAmount * 3,
                "total votes incorrect"
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
            IMultichainGovernorV2.ProposalInformation
                memory voteCollectionInfo = _getVoteCollectionProposalInformation(
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
        }

        _assertGovernanceBalance();
    }

    function testMultipleUserVoteWithXWellDelegationSucceeds() public {
        address user1 = address(1);
        address user2 = address(2);
        address user3 = address(3);
        address user4 = address(4);

        uint256 voteAmount = 1_000_000 * 1e18;

        xwell.transfer(address(user1), voteAmount);
        xwell.transfer(address(user3), voteAmount);

        vm.prank(user1);
        xwell.delegate(user2);

        vm.prank(user3);
        xwell.delegate(user4);

        vm.warp(block.timestamp + 1);

        uint256 proposalId = _createProposalUpdateThreshold(address(this));

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        // get proposal votes before
        (
            uint256 totalVotesBefore,
            uint256 votesForBefore,
            uint256 votesAgainstBefore,
            uint256 votesAbstainBefore
        ) = voteCollection.proposalVotes(proposalId);

        {
            vm.prank(user2);
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_NO);

            // check proposal votes after
            (
                uint256 totalVotes,
                uint256 votesFor,
                uint256 votesAgainst,
                uint256 votesAbstain
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(votesAgainst, voteAmount, "votes against incorrect");
            assertEq(
                votesAgainst - votesAgainstBefore,
                voteAmount,
                "votes against incorrect"
            );
            assertEq(votesFor, votesForBefore, "votes for incorrect");
            assertEq(
                votesAbstain,
                votesAbstainBefore,
                "abstain votes incorrect"
            );
            assertEq(
                totalVotes,
                totalVotesBefore + voteAmount,
                "total votes incorrect"
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
            vm.prank(user4);
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_ABSTAIN);

            // check proposal votes after
            (
                uint256 totalVotes,
                uint256 votesFor,
                uint256 votesAgainst,
                uint256 votesAbstain
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(votesAbstain, voteAmount, "abstain votes incorrect");
            assertEq(
                votesAbstain - votesAbstainBefore,
                voteAmount,
                "abstain votes incorrect"
            );
            assertEq(votesFor, votesForBefore, "votes for incorrect");
            assertEq(
                votesAgainst - votesAgainstBefore,
                voteAmount,
                "votes against incorrect"
            );
            assertEq(
                totalVotes,
                totalVotesBefore + voteAmount * 2,
                "total votes incorrect"
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

        IMultichainGovernorV2.ProposalInformation
            memory voteCollectionInfo = _getVoteCollectionProposalInformation(
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

        _assertGovernanceBalance();
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

        uint256 proposalId = _createProposalUpdateThreshold(address(this));

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        // get proposal votes before
        (
            uint256 totalVotesBefore,
            uint256 votesForBefore,
            uint256 votesAgainstBefore,
            uint256 votesAbstainBefore
        ) = voteCollection.proposalVotes(proposalId);

        {
            vm.prank(user1);
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_YES);

            // check proposal votes after
            (
                uint256 totalVotes,
                uint256 votesFor,
                uint256 votesAgainst,
                uint256 votesAbstain
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(votesFor, voteAmount, "votes for incorrect");
            assertEq(
                votesFor - votesForBefore,
                voteAmount,
                "votes for incorrect"
            );
            assertEq(
                votesAgainst,
                votesAgainstBefore,
                "votes against incorrect"
            );
            assertEq(
                votesAbstain,
                votesAbstainBefore,
                "abstain votes incorrect"
            );
            assertEq(
                totalVotes,
                totalVotesBefore + voteAmount,
                "total votes incorrect"
            );
        }

        {
            vm.prank(user2);
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_NO);

            // check proposal votes after
            (
                uint256 totalVotes,
                uint256 votesFor,
                uint256 votesAgainst,
                uint256 votesAbstain
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(votesAgainst, voteAmount, "votes against incorrect");
            assertEq(
                votesAgainst - votesAgainstBefore,
                voteAmount,
                "votes against incorrect"
            );
            assertEq(votesFor, voteAmount, "votes for incorrect");
            assertEq(
                votesAbstain,
                votesAbstainBefore,
                "abstain votes incorrect"
            );
            assertEq(
                totalVotes,
                totalVotesBefore + voteAmount * 2,
                "total votes incorrect"
            );
        }

        {
            vm.prank(user3);
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_ABSTAIN);

            // check proposal votes after
            (
                uint256 totalVotes,
                uint256 votesFor,
                uint256 votesAgainst,
                uint256 votesAbstain
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(votesAbstain, voteAmount, "abstain votes incorrect");
            assertEq(
                votesAbstain - votesAbstainBefore,
                voteAmount,
                "abstain votes incorrect"
            );
            assertEq(votesFor, voteAmount, "votes for incorrect");
            assertEq(votesAgainst, voteAmount, "votes against incorrect");
            assertEq(
                totalVotes,
                totalVotesBefore + voteAmount * 3,
                "total votes incorrect"
            );
        }

        {
            IMultichainGovernorV2.ProposalInformation
                memory voteCollectionInfo = _getVoteCollectionProposalInformation(
                    proposalId
                );

            assertEq(
                voteCollectionInfo.totalVotes,
                voteCollectionInfo.forVotes +
                    voteCollectionInfo.againstVotes +
                    voteCollectionInfo.abstainVotes,
                "incorrect total votes"
            );
        }

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

        IMultichainGovernorV2.ProposalInformation
            memory governorInfo = _getVoteCollectionProposalInformation(
                proposalId
            );

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

        _assertGovernanceBalance();
    }

    function testMultipleUserVoteWithxWellDelegationSucceeds() public {
        address user1 = address(1);
        address user2 = address(2);
        address user3 = address(3);
        address user4 = address(4);

        uint256 voteAmount = 1_000_000 * 1e18;
        xwell.transfer(user1, voteAmount);
        xwell.transfer(user3, voteAmount);

        vm.prank(user1);
        xwell.delegate(user2);

        vm.prank(user3);
        xwell.delegate(user4);

        vm.warp(block.timestamp + 1);

        uint256 proposalId = _createProposalUpdateThreshold(address(this));

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        // get votes before
        (
            uint256 totalVotesBefore,
            uint256 votesForBefore,
            uint256 votesAgainstBefore,
            uint256 votesAbstainBefore
        ) = voteCollection.proposalVotes(proposalId);

        {
            vm.prank(user2);
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_NO);

            // check proposal votes after
            (
                uint256 totalVotes,
                uint256 votesFor,
                uint256 votesAgainst,
                uint256 votesAbstain
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(votesAgainst, voteAmount, "votes against incorrect");
            assertEq(
                votesAgainst - votesAgainstBefore,
                voteAmount,
                "votes against incorrect"
            );
            assertEq(votesFor, votesForBefore, "votes for incorrect");
            assertEq(
                votesAbstain,
                votesAbstainBefore,
                "abstain votes incorrect"
            );
            assertEq(
                totalVotes,
                totalVotesBefore + voteAmount,
                "total votes incorrect"
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
            vm.prank(user4);
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_ABSTAIN);

            // check proposal votes after
            (
                uint256 totalVotes,
                uint256 votesFor,
                uint256 votesAgainst,
                uint256 votesAbstain
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(votesAbstain, voteAmount, "abstain votes incorrect");
            assertEq(
                votesAbstain - votesAbstainBefore,
                voteAmount,
                "abstain votes incorrect"
            );
            assertEq(votesFor, votesForBefore, "votes for incorrect");
            assertEq(
                votesAgainst - votesAgainstBefore,
                voteAmount,
                "votes against incorrect"
            );
            assertEq(
                totalVotes,
                totalVotesBefore + voteAmount * 2,
                "total votes"
            );
        }

        _assertGovernanceBalance();
    }

    // Emit votes to Governor
    function testEmitVotesToGovernorSucceeded()
        public
        returns (uint256 proposalId)
    {
        testMultipleUserVoteWellSucceeds();

        wormholeRelayerAdapter.setSenderChainId(BASE_WORMHOLE_CHAIN_ID);

        proposalId = governor.proposalCount();

        IMultichainGovernorV2.ProposalInformation
            memory proposalVoteCollection = _getVoteCollectionProposalInformation(
                proposalId
            );

        // test at the last timestamp of the cross chain vote collection period
        vm.warp(proposalVoteCollection.crossChainVoteCollectionEndTimestamp);

        assertEq(
            uint256(governor.state(proposalId)),
            1,
            "incorrect state, not in crosschain vote collection period"
        );

        IMultichainGovernorV2.ProposalInformation
            memory proposalBefore = governor.proposalInformationStruct(
                proposalId
            );

        {
            uint256 bridgeCost = voteCollection.bridgeCost(
                MOONBEAM_WORMHOLE_CHAIN_ID
            );

            vm.deal(address(this), bridgeCost);

            vm.recordLogs();
            voteCollection.emitVotes{value: bridgeCost}(proposalId);
            _deliverBridgeOutEvents(address(voteCollection));
        }

        IMultichainGovernorV2.ProposalInformation
            memory proposalAfter = governor.proposalInformationStruct(
                proposalId
            );

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

        _assertGovernanceBalance();
    }

    function testEmitVotesRefundFails() public {
        uint256 proposalId = testVotingValidProposalIdSucceeds();
        (, , uint256 endTimestamp, , , , , ) = voteCollection
            .proposalInformation(proposalId);
        vm.warp(endTimestamp + 1);

        /// Send excess ETH so the refund path is triggered
        uint256 excessValue = 1 ether;
        vm.deal(address(this), excessValue);

        _receivingFunds = false;
        vm.expectRevert(
            abi.encodeWithSelector(WormholeBridgeBase.RefundFailed.selector)
        );
        voteCollection.emitVotes{value: excessValue}(proposalId);
    }

    function testEmitVotesRefundSucceeds() public {
        uint256 proposalId = testVotingValidProposalIdSucceeds();
        wormholeRelayerAdapter.setSenderChainId(BASE_WORMHOLE_CHAIN_ID);

        uint256 bridgeCost = voteCollection.bridgeCost(
            MOONBEAM_WORMHOLE_CHAIN_ID
        );
        (, , uint256 endTimestamp, , , , , ) = voteCollection
            .proposalInformation(proposalId);
        vm.warp(endTimestamp + 1);
        _receivingFunds = true;

        vm.deal(address(this), bridgeCost * 5);

        voteCollection.emitVotes{value: bridgeCost * 5}(proposalId);
        assertEq(
            address(this).balance,
            bridgeCost * 4,
            "incorrect refund amount"
        );
    }

    function testEmitVotesProposalHasNoVotes() public {
        _createProposalUpdateThreshold(address(this));

        uint256 proposalId = governor.proposalCount();

        vm.expectRevert("MultichainVoteCollectionV2: proposal has no votes");
        voteCollection.emitVotes(proposalId);

        _assertGovernanceBalance();
    }

    function testEmitVotesProposalEndTimeHasNotPassed() public {
        uint256 proposalId = testVotingValidProposalIdSucceeds();

        (, , uint256 endTimestamp, , , , , ) = voteCollection
            .proposalInformation(proposalId);

        // test at the last timestamp of vote period
        vm.warp(endTimestamp);

        vm.expectRevert("MultichainVoteCollectionV2: Voting has not ended");
        voteCollection.emitVotes(proposalId);

        _assertGovernanceBalance();
    }

    /// @notice With bridgeCost returning 0 (messageFee), underpaying is
    ///         impossible. Instead test that excess ETH triggers a refund
    ///         failure when the caller cannot receive funds.
    function testEmitVotesExcessValueRefundFails() public {
        uint256 proposalId = testVotingValidProposalIdSucceeds();

        (, , uint256 endTimestamp, , , , , ) = voteCollection
            .proposalInformation(proposalId);

        // test at the last timestamp of vote period
        vm.warp(endTimestamp + 1);

        uint256 excessValue = 1 ether;
        vm.deal(address(this), excessValue);

        _receivingFunds = false;
        vm.expectRevert(
            abi.encodeWithSelector(WormholeBridgeBase.RefundFailed.selector)
        );
        voteCollection.emitVotes{value: excessValue}(proposalId);

        _assertGovernanceBalance();
    }

    function testEmitVotesProposalCollectionEndTimeHasPassed() public {
        uint256 proposalId = testVotingValidProposalIdSucceeds();

        IMultichainGovernorV2.ProposalInformation
            memory voteCollectionInfo = _getVoteCollectionProposalInformation(
                proposalId
            );

        vm.warp(voteCollectionInfo.crossChainVoteCollectionEndTimestamp + 1);

        vm.expectRevert(
            "MultichainVoteCollectionV2: Voting collection phase has ended"
        );
        voteCollection.emitVotes(proposalId);

        _assertGovernanceBalance();
    }

    /// Only Owner

    function testSetGasLimitDeprecated() public {
        uint96 gasLimit = Constants.MIN_GAS_LIMIT;
        vm.expectRevert("deprecated");
        voteCollection.setGasLimit(gasLimit);
    }

    // ADD / REMOVE TARGET ADDRESS (onlyOwner mutators added for mip-x58 break-glass)

    function testAddTargetAddressOwnerSucceeds() public {
        uint16 newChainId = 99;
        address newSender = address(0xBEEF);

        // owner == address(this) per testSetup; no prank needed
        voteCollection.addTargetAddress(newChainId, newSender);

        assertEq(
            voteCollection.targetAddress(newChainId),
            newSender,
            "targetAddress not stored"
        );
        assertTrue(
            voteCollection.isTrustedSender(newChainId, newSender),
            "isTrustedSender false after add"
        );
        assertEq(
            voteCollection.getAllTargetChainsLength(),
            2,
            "target chains length not incremented"
        );
    }

    function testAddTargetAddressNonOwnerReverts() public {
        vm.prank(address(0xCAFE));
        vm.expectRevert("Ownable: caller is not the owner");
        voteCollection.addTargetAddress(99, address(0xBEEF));
    }

    function testAddTargetAddressZeroAddrReverts() public {
        vm.expectRevert(WormholeBridgeBase.InvalidAddress.selector);
        voteCollection.addTargetAddress(99, address(0));
    }

    function testAddTargetAddressDuplicateChainReverts() public {
        // MOONBEAM_WORMHOLE_CHAIN_ID is already configured in setup;
        // re-adding the same chain id must revert
        vm.expectRevert(WormholeBridgeBase.ChainAlreadyAdded.selector);
        voteCollection.addTargetAddress(
            MOONBEAM_WORMHOLE_CHAIN_ID,
            address(0xBEEF)
        );
    }

    function testRemoveTargetAddressOwnerSucceeds() public {
        uint16 newChainId = 99;
        address newSender = address(0xBEEF);

        voteCollection.addTargetAddress(newChainId, newSender);
        assertEq(
            voteCollection.targetAddress(newChainId),
            newSender,
            "add precondition failed"
        );

        voteCollection.removeTargetAddress(newChainId);

        assertEq(
            voteCollection.targetAddress(newChainId),
            address(0),
            "targetAddress not cleared"
        );
        assertFalse(
            voteCollection.isTrustedSender(newChainId, newSender),
            "isTrustedSender true after remove"
        );
        assertEq(
            voteCollection.getAllTargetChainsLength(),
            1,
            "target chains length not decremented"
        );
    }

    function testRemoveTargetAddressNonOwnerReverts() public {
        vm.prank(address(0xCAFE));
        vm.expectRevert("Ownable: caller is not the owner");
        voteCollection.removeTargetAddress(MOONBEAM_WORMHOLE_CHAIN_ID);
    }

    function testRemoveTargetAddressNotAddedReverts() public {
        vm.expectRevert(WormholeBridgeBase.ChainNotAdded.selector);
        voteCollection.removeTargetAddress(99);
    }

    function testRemoveTargetAddressPreInitializedChainSucceeds() public {
        // MOONBEAM_WORMHOLE_CHAIN_ID is mapped to address(governor) during
        // initialize. Mirrors the mip-x58 break-glass scenario where
        // removeTargetAddress(ETHEREUM_WORMHOLE_CHAIN_ID) on Base/OP VC2 evicts
        // the V2 governor that initializeV3 baked in.
        assertEq(
            voteCollection.targetAddress(MOONBEAM_WORMHOLE_CHAIN_ID),
            address(governor),
            "precondition: governor must be the initialized trusted sender"
        );

        voteCollection.removeTargetAddress(MOONBEAM_WORMHOLE_CHAIN_ID);

        assertEq(
            voteCollection.targetAddress(MOONBEAM_WORMHOLE_CHAIN_ID),
            address(0),
            "targetAddress not cleared for pre-initialized chain"
        );
        assertFalse(
            voteCollection.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                address(governor)
            ),
            "isTrustedSender true after removing pre-initialized chain"
        );
        assertEq(
            voteCollection.getAllTargetChainsLength(),
            0,
            "target chains length should be 0 after removing sole chain"
        );
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
        bytes memory innerPayload = abi.encode(0, 0, 0, 0, 0);
        // Set sender chain to a chain that voteCollection does NOT trust
        wormholeRelayerAdapter.setSenderChainId(BASE_WORMHOLE_CHAIN_ID);

        vm.expectRevert("untrusted emitter");
        wormholeRelayerAdapter.deliverBridgeOut(
            BASE_WORMHOLE_CHAIN_ID,
            address(voteCollection),
            abi.encode(
                BASE_WORMHOLE_CHAIN_ID,
                address(voteCollection),
                innerPayload
            ),
            address(governor)
        );
    }

    function testBridgeInWrongPayloadLength() public {
        bytes memory innerPayload = abi.encode(0, 0, 0, 0);

        vm.expectRevert("MultichainVoteCollectionV2: invalid payload length");
        wormholeRelayerAdapter.deliverBridgeOut(
            BASE_WORMHOLE_CHAIN_ID,
            address(voteCollection),
            abi.encode(
                BASE_WORMHOLE_CHAIN_ID,
                address(voteCollection),
                innerPayload
            ),
            address(governor)
        );
    }

    function testBridgeInProposalAlreadyExist() public {
        uint256 proposalId = _createProposalUpdateThreshold(address(this));

        bytes memory innerPayload = abi.encode(proposalId, 0, 0, 0, 0);

        vm.expectRevert("MultichainVoteCollectionV2: proposal already exists");
        wormholeRelayerAdapter.deliverBridgeOut(
            BASE_WORMHOLE_CHAIN_ID,
            address(voteCollection),
            abi.encode(
                BASE_WORMHOLE_CHAIN_ID,
                address(voteCollection),
                innerPayload
            ),
            address(governor)
        );
    }

    function testBridgeInVotingSnapshotTimeGreaterThanStartTime() public {
        vm.warp(1);

        bytes memory innerPayload = abi.encode(0, 4, 3, 3, 4);

        vm.expectRevert(
            "MultichainVoteCollectionV2: snapshot time must be before start time"
        );
        wormholeRelayerAdapter.deliverBridgeOut(
            BASE_WORMHOLE_CHAIN_ID,
            address(voteCollection),
            abi.encode(
                BASE_WORMHOLE_CHAIN_ID,
                address(voteCollection),
                innerPayload
            ),
            address(governor)
        );
    }

    function testBridgeInVotingSnapshotTimeEqStartTime() public {
        vm.warp(1);

        bytes memory innerPayload = abi.encode(0, 4, 4, 3, 4);

        vm.expectRevert(
            "MultichainVoteCollectionV2: snapshot time must be before start time"
        );
        wormholeRelayerAdapter.deliverBridgeOut(
            BASE_WORMHOLE_CHAIN_ID,
            address(voteCollection),
            abi.encode(
                BASE_WORMHOLE_CHAIN_ID,
                address(voteCollection),
                innerPayload
            ),
            address(governor)
        );
    }

    function testBridgeInVotingStartTimeGreaterThanVoteEndTime() public {
        vm.warp(1);
        bytes memory innerPayload = abi.encode(0, 2, 3, 2, 0);

        vm.expectRevert(
            "MultichainVoteCollectionV2: start time must be before end time"
        );
        wormholeRelayerAdapter.deliverBridgeOut(
            BASE_WORMHOLE_CHAIN_ID,
            address(voteCollection),
            abi.encode(
                BASE_WORMHOLE_CHAIN_ID,
                address(voteCollection),
                innerPayload
            ),
            address(governor)
        );
    }

    function testBridgeInVoteCollectionEndLtThanVoteEndTime() public {
        vm.warp(1);
        bytes memory innerPayload = abi.encode(0, 2, 3, 4, 0);

        vm.expectRevert(
            "MultichainVoteCollectionV2: end time must be before vote collection end"
        );
        wormholeRelayerAdapter.deliverBridgeOut(
            BASE_WORMHOLE_CHAIN_ID,
            address(voteCollection),
            abi.encode(
                BASE_WORMHOLE_CHAIN_ID,
                address(voteCollection),
                innerPayload
            ),
            address(governor)
        );
    }

    function testBridgeInVotingStartTimeEqVoteEndTime() public {
        vm.warp(1);
        bytes memory innerPayload = abi.encode(0, 1, 2, 2, 0);

        vm.expectRevert(
            "MultichainVoteCollectionV2: start time must be before end time"
        );
        wormholeRelayerAdapter.deliverBridgeOut(
            BASE_WORMHOLE_CHAIN_ID,
            address(voteCollection),
            abi.encode(
                BASE_WORMHOLE_CHAIN_ID,
                address(voteCollection),
                innerPayload
            ),
            address(governor)
        );
    }

    function testBridgeInVotingEndTimeLessThanTimestamp() public {
        bytes memory innerPayload = abi.encode(0, 0, 1, 2, 0);

        vm.expectRevert(
            "MultichainVoteCollectionV2: end time must be in the future"
        );
        wormholeRelayerAdapter.deliverBridgeOut(
            BASE_WORMHOLE_CHAIN_ID,
            address(voteCollection),
            abi.encode(
                BASE_WORMHOLE_CHAIN_ID,
                address(voteCollection),
                innerPayload
            ),
            address(governor)
        );
    }

    // test governor bridge in votes already collected here to reuse emit votes test
    function testBridgeInVotesAlreadyCollected() public {
        uint256 proposalId = testEmitVotesToGovernorSucceeded();
        wormholeRelayerAdapter.setSenderChainId(BASE_WORMHOLE_CHAIN_ID);

        bytes memory innerPayload = abi.encode(proposalId, 0, 0, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMultichainGovernorV2.VoteAlreadyCollected.selector
            )
        );
        wormholeRelayerAdapter.deliverBridgeOut(
            MOONBEAM_WORMHOLE_CHAIN_ID,
            address(governor),
            abi.encode(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                address(governor),
                innerPayload
            ),
            address(voteCollection)
        );
    }

    receive() external payable {
        require(_receivingFunds);
    }
}
