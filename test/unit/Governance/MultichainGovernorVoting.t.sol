pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {stdError} from "@forge-std/StdError.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {MockWeth} from "@test/mock/MockWeth.sol";
import {Constants} from "@protocol/Governance/MultichainGovernor/Constants.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {SnapshotInterface} from "@protocol/Governance/MultichainGovernor/SnapshotInterface.sol";
import {MultichainBaseTest} from "@test/helper/MultichainBaseTest.t.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {MultichainVoteCollection} from "@protocol/Governance/MultichainGovernor/MultichainVoteCollection.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";
import {IMultichainGovernor, MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";

contract MultichainGovernorVotingUnitTest is MultichainBaseTest {
    event ProposalCanceled(uint256 proposalId);

    event ProposalRebroadcasted(uint256 proposalId, bytes data);

    event BridgeOutFailed(uint16 chainId, bytes payload);

    event ProposalCreated(
        uint id,
        address proposer,
        address[] targets,
        uint[] values,
        string[] signatures,
        bytes[] calldatas,
        uint startTimestamp,
        uint endTimestamp,
        string description
    );

    event BridgeOutSuccess(
        uint16 dstWormholeChainId,
        uint256 cost,
        address dst,
        bytes payload
    );

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

        assertEq(address(governor.well()), address(well));
        assertEq(address(governor.xWell()), address(xwell));
        assertEq(address(governor.stkWell()), address(stkWellMoonbeam));
        assertEq(address(governor.distributor()), address(distributor));

        assertEq(
            address(governor.wormholeRelayer()),
            address(wormholeRelayerAdapter),
            "incorrect wormhole relayer"
        );
        assertTrue(
            governor.isTrustedSender(
                baseWormholeChainId,
                address(voteCollection)
            ),
            "voteCollection not whitelisted to send messages in"
        );

        for (uint256 i = 0; i < approvedCalldata.length; i++) {
            assertTrue(
                governor.whitelistedCalldatas(approvedCalldata[i]),
                "calldata not approved"
            );
        }
    }

    /// Proposing on MultichainGovernor
    function testProposeUpdateProposalThresholdSucceeds()
        public
        returns (uint256)
    {
        uint256 proposalId = _createProposalUpdateThreshold();

        {
            bool proposalFound;

            uint256[] memory proposals = governor.liveProposals();

            for (uint256 i = 0; i < proposals.length; i++) {
                if (proposals[i] == proposalId) {
                    proposalFound = true;
                    break;
                }
            }

            assertTrue(proposalFound, "proposal not found in live proposals");
        }

        {
            bool proposalFound;
            uint256[] memory proposals = governor.getUserLiveProposals(
                address(this)
            );

            for (uint256 i = 0; i < proposals.length; i++) {
                if (proposals[i] == proposalId) {
                    proposalFound = true;
                    break;
                }
            }

            assertTrue(
                proposalFound,
                "proposal not found in user live proposals"
            );
        }

        return proposalId;
    }

    function testProposeInsufficientProposalThresholdFails() public {
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory calldatas = new bytes[](0);
        string memory description = "Mock Proposal MIP-M00";

        assertEq(
            well.getPriorVotes(address(this), 0),
            0,
            "well incorrect votes"
        );
        assertEq(
            distributor.getPriorVotes(address(this), 0),
            0,
            "distributor incorrect votes"
        );
        assertEq(
            SnapshotInterface(address(stkWellMoonbeam)).getPriorVotes(
                address(this),
                0
            ),
            0,
            "stkWellMoonbeam incorrect votes"
        );
        assertEq(
            xwell.getPastVotes(address(this), 0),
            0,
            "xwell incorrect votes"
        );

        vm.warp(1);
        vm.roll(1);

        vm.expectRevert(
            "MultichainGovernor: proposer votes below proposal threshold"
        );
        governor.propose(targets, values, calldatas, description);
    }

    function testProposeExcessiveValueFails() public {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        string memory description = "Mock Proposal MIP-M00";

        values[0] = type(uint256).max;
        values[1] = 1;

        vm.expectRevert(stdError.arithmeticError);
        governor.propose(targets, values, calldatas, description);
    }

    function testProposeArityMismatchFails() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](0);
        bytes[] memory calldatas = new bytes[](0);
        string memory description = "Mock Proposal MIP-M00";

        /// branch 1

        vm.expectRevert(
            "MultichainGovernor: proposal function information arity mismatch"
        );
        governor.propose(targets, values, calldatas, description);

        /// branch 2

        values = new uint256[](1);

        vm.expectRevert(
            "MultichainGovernor: proposal function information arity mismatch"
        );
        governor.propose(targets, values, calldatas, description);
    }

    function testProposeNoActionsFails() public {
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory calldatas = new bytes[](0);
        string memory description = "Mock Empty Proposal MIP-M00";

        vm.expectRevert("MultichainGovernor: must provide actions");
        governor.propose(targets, values, calldatas, description);
    }

    function testProposeNoDescriptionsFails() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "";

        vm.expectRevert("MultichainGovernor: description can not be empty");
        governor.propose(targets, values, calldatas, description);
    }

    function testProposeOverMaxProposalCountFails() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Mock Proposal MIP-M00";

        for (uint256 i = 0; i < governor.maxUserLiveProposals(); i++) {
            uint256 bridgeCost = governor.bridgeCostAll();
            vm.deal(address(this), bridgeCost);

            governor.propose{value: bridgeCost}(
                targets,
                values,
                calldatas,
                description
            );
        }

        vm.expectRevert(
            "MultichainGovernor: too many live proposals for this user"
        );
        governor.propose(targets, values, calldatas, description);
    }

    function testProposeUpdateProposalThresholdFailsIncorrectGas() public {
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

        uint256 bridgeCost = governor.bridgeCostAll() - 1; /// 1 Wei less than needed
        vm.deal(address(this), bridgeCost);

        vm.expectRevert("WormholeBridge: total cost not equal to quote");
        governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );
    }

    /// rebroadcasting
    function testProposeWormholeBroadcastingFailsProposeCreationStillSucceed()
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

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        uint256 startTimestamp = block.timestamp;
        uint256 endTimestamp = startTimestamp + governor.votingPeriod();
        bytes memory payload = abi.encode(
            1,
            startTimestamp - 1,
            startTimestamp,
            endTimestamp,
            endTimestamp + governor.crossChainVoteCollectionPeriod()
        );

        wormholeRelayerAdapter.setShouldRevert(true);
        vm.expectEmit(true, true, true, true, address(governor));
        emit BridgeOutFailed(baseWormholeChainId, payload);
        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        assertTrue(governor.proposalActive(proposalId), "proposal not active");

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

    function testRebroadcastProposalSucceedsProposalActive() public {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();
        (
            ,
            uint256 voteSnapshotTimestamp,
            uint256 votingStartTime,
            uint256 endTimestamp,
            uint256 crossChainVoteCollectionEndTimestamp,
            ,
            ,
            ,

        ) = governor.proposalInformation(proposalId);

        bytes memory payload = abi.encode(
            proposalId,
            voteSnapshotTimestamp,
            votingStartTime,
            endTimestamp,
            crossChainVoteCollectionEndTimestamp
        );

        uint256 cost = governor.bridgeCostAll();
        vm.deal(address(this), cost);

        vm.expectEmit(true, true, true, true, address(governor));
        emit ProposalRebroadcasted(proposalId, payload);

        governor.rebroadcastProposal{value: cost}(proposalId);
    }

    function testRebroadcastProposalTwiceSucceedsProposalActive() public {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();
        (
            ,
            uint256 voteSnapshotTimestamp,
            uint256 votingStartTime,
            uint256 endTimestamp,
            uint256 crossChainVoteCollectionEndTimestamp,
            ,
            ,
            ,

        ) = governor.proposalInformation(proposalId);

        bytes memory payload = abi.encode(
            proposalId,
            voteSnapshotTimestamp,
            votingStartTime,
            endTimestamp,
            crossChainVoteCollectionEndTimestamp
        );

        uint256 cost = governor.bridgeCostAll();
        vm.deal(address(this), cost);

        vm.expectEmit(true, true, true, true, address(governor));
        emit ProposalRebroadcasted(proposalId, payload);

        governor.rebroadcastProposal{value: cost}(proposalId);

        vm.deal(address(this), cost);

        vm.expectEmit(true, true, true, true, address(governor));
        emit ProposalRebroadcasted(proposalId, payload);
        governor.rebroadcastProposal{value: cost}(proposalId);
    }

    function testRebroadcastProposalFailsInvalidProposalId() public {
        uint256 proposalId = 100;

        vm.expectRevert("MultichainGovernor: invalid proposal id");
        governor.rebroadcastProposal(proposalId);
    }

    function testRebroadcastProposalFailsProposalAfterXChainVoteCollection()
        public
    {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        uint256 cost = governor.bridgeCostAll();
        vm.deal(address(this), cost);

        vm.warp(
            block.timestamp +
                governor.votingPeriod() +
                governor.crossChainVoteCollectionPeriod() +
                1
        );
        vm.expectRevert("MultichainGovernor: invalid state");
        governor.rebroadcastProposal{value: cost}(proposalId);
    }

    function testRebroadcastProposalFailsProposalDuringXChainVoteCollection()
        public
    {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        uint256 cost = governor.bridgeCostAll();
        vm.deal(address(this), cost);

        vm.warp(block.timestamp + governor.votingPeriod() + 1);
        vm.expectRevert("MultichainGovernor: invalid state");
        governor.rebroadcastProposal{value: cost}(proposalId);
    }

    function testRebroadcastProposalFailsNoValue() public {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.expectRevert("WormholeBridge: total cost not equal to quote");
        governor.rebroadcastProposal(proposalId);
    }

    function testRebroadcastProposalFailsIncorrectValue() public {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        uint256 cost = governor.bridgeCostAll() - 2012;
        vm.deal(address(this), cost);

        vm.expectRevert("WormholeBridge: total cost not equal to quote");
        governor.rebroadcastProposal{value: cost}(proposalId);
    }

    function testProposeAndRebroadcastProduceSameCalldata() public {
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

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        uint256 startTimestamp = block.timestamp;
        uint256 endTimestamp = startTimestamp + governor.votingPeriod();
        uint256 crossChainVoteCollectionEndTimestamp = endTimestamp +
            governor.crossChainVoteCollectionPeriod();

        bytes memory payload = abi.encode(
            1,
            startTimestamp - 1,
            startTimestamp,
            endTimestamp,
            crossChainVoteCollectionEndTimestamp
        );

        vm.expectEmit(true, true, true, true, address(governor));
        emit BridgeOutSuccess(
            baseWormholeChainId,
            uint96(bridgeCost),
            address(voteCollection),
            payload
        );
        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        vm.deal(address(this), bridgeCost);

        vm.expectEmit(true, true, true, true, address(governor));
        emit ProposalRebroadcasted(proposalId, payload);
        governor.rebroadcastProposal{value: bridgeCost}(proposalId);
    }

    /// Voting on MultichainGovernor

    function testVotingValidProposalIdSucceeds()
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

        governor.castVote(proposalId, Constants.VOTE_VALUE_YES);

        (bool hasVoted, , ) = governor.getReceipt(proposalId, address(this));
        assertTrue(hasVoted, "user did not vote");

        (
            uint256 totalVotes,
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 votesAbstain
        ) = governor.proposalVotes(proposalId);

        assertEq(votesFor, 14_000_000_000 * 1e18, "votes for incorrect");
        assertEq(votesAgainst, 0, "votes against incorrect");
        assertEq(votesAbstain, 0, "abstain votes incorrect");
        assertEq(votesFor, totalVotes, "total votes incorrect");
    }

    /// cannot vote twice on the same proposal

    function testVotingTwiceSameProposalFails() public {
        uint256 proposalId = testVotingValidProposalIdSucceeds();

        vm.expectRevert("MultichainGovernor: voter already voted");
        governor.castVote(proposalId, Constants.VOTE_VALUE_YES);
    }

    function testVotingXChainVoteCollectionPeriodFails()
        public
        returns (uint256 proposalId)
    {
        proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            1,
            "incorrect state, not in xchain vote collection period"
        );

        vm.expectRevert("MultichainGovernor: proposal not active");
        governor.castVote(proposalId, 2);
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

        vm.expectRevert("MultichainGovernor: invalid vote value");
        governor.castVote(proposalId, 3);
    }

    function testVotingBeforeProposalStartsFailsWell()
        public
        returns (uint256 proposalId)
    {
        proposalId = testProposeUpdateProposalThresholdSucceeds();

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        vm.roll(block.number - 1);
        vm.expectRevert("Well::getPriorVotes: not yet determined");
        governor.castVote(proposalId, Constants.VOTE_VALUE_NO);
    }

    function testVotingBeforeProposalStartsFails()
        public
        returns (uint256 proposalId)
    {
        proposalId = testProposeUpdateProposalThresholdSucceeds();

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        vm.roll(block.number - 1);

        vm.expectRevert("Well::getPriorVotes: not yet determined");
        governor.castVote(proposalId, Constants.VOTE_VALUE_NO);
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

        vm.expectRevert("MultichainGovernor: invalid vote value");
        governor.castVote(proposalId, 3);
    }

    function testVotingNoVotesFails() public returns (uint256 proposalId) {
        proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        vm.expectRevert("MultichainGovernor: voter has no votes");
        vm.prank(address(1));
        governor.castVote(proposalId, Constants.VOTE_VALUE_YES);
    }

    /// Multiple users all voting on the same proposal

    /// WELL
    function testMultipleUserVoteWellSucceeds() public {
        address user1 = address(1);
        address user2 = address(2);
        address user3 = address(3);
        uint256 voteAmount = 1_000_000 * 1e18;

        well.transfer(user1, voteAmount);
        well.transfer(user2, voteAmount);
        well.transfer(user3, voteAmount);

        vm.prank(user1);
        well.delegate(user1);

        vm.prank(user2);
        well.delegate(user2);

        vm.prank(user3);
        well.delegate(user3);

        /// include users before snapshot block
        vm.roll(block.number + 1);

        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

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

    function testMultipleUserVoteWithWellDelegationSucceeds() public {
        uint256 voteAmount = 1_000_000 * 1e18;

        address user1 = address(1);
        address user2 = address(2);
        address user3 = address(3);
        address user4 = address(4);

        well.transfer(address(user1), 1_000_000 * 1e18);
        well.transfer(address(user3), 1_000_000 * 1e18);

        vm.prank(user1);
        well.delegate(user2);

        vm.prank(user3);
        well.delegate(user4);

        vm.roll(block.number + 1);

        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

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
                "user4 did not vote no"
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

    // STAKED WELL

    function testMultipleUserVoteStkWellSucceeded() public {
        address user1 = address(1);
        address user2 = address(2);
        address user3 = address(3);
        uint256 voteAmount = 1_000_000 * 1e18;

        xwell.transfer(user1, voteAmount);

        vm.startPrank(user1);
        xwell.approve(address(stkWellMoonbeam), voteAmount);
        stkWellMoonbeam.stake(user1, voteAmount);
        vm.stopPrank();

        xwell.transfer(user2, voteAmount);

        vm.startPrank(user2);
        xwell.approve(address(stkWellMoonbeam), voteAmount);
        stkWellMoonbeam.stake(user2, voteAmount);
        vm.stopPrank();

        xwell.transfer(user3, voteAmount);

        vm.startPrank(user3);
        xwell.approve(address(stkWellMoonbeam), voteAmount);
        stkWellMoonbeam.stake(user3, voteAmount);
        vm.stopPrank();

        /// include users before snapshot timestamp
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.roll(block.number + 1);
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

    function testUserVotingToProposalWithDifferentTokensSucceeds() public {
        address user = address(1);
        uint256 voteAmount = 1_000_000 * 1e18;

        // well * 2 to deposit half to stkWellBase
        well.transfer(user, voteAmount);

        // xwell
        xwell.transfer(user, voteAmount * 2);

        vm.startPrank(user);

        // stkWell
        xwell.approve(address(stkWellMoonbeam), voteAmount);
        stkWellMoonbeam.stake(user, voteAmount);

        well.delegate(user);
        xwell.delegate(user);
        vm.stopPrank();

        /// include user before snapshot block
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        vm.prank(user);
        governor.castVote(proposalId, Constants.VOTE_VALUE_YES);

        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = governor
                .getReceipt(proposalId, user);

            assertTrue(hasVoted, "user has not voted");
            assertEq(votes, voteAmount * 3, "user has incorrect vote amount");
            assertEq(
                voteValue,
                Constants.VOTE_VALUE_YES,
                "user did not vote yes"
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
        assertEq(forVotes, 3 * voteAmount, "incorrect for votes");
        assertEq(againstVotes, 0, "incorrect against votes");
        assertEq(abstainVotes, 0, "incorrect abstain votes");
    }

    function testFromWormholeFormatToAddress() public {
        bytes32 invalidAddress1 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000000000000000000000000;
        bytes32 invalidAddress2 = 0xFFFFFFFFFFFFFFFFFFFFFFFF0000000000000000000000000000000000000000; /// bytes32(uint256(type(uint256).max << 160));

        bytes32 validAddress1 = 0x000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        bytes32 validAddress2 = 0x000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0;
        bytes32 validAddress3 = 0x000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00;
        bytes32 validAddress4 = 0x000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000;
        bytes32 validAddress5 = 0x0000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000;

        vm.expectRevert("WormholeBridge: invalid address");
        governor.fromWormholeFormat(invalidAddress1);

        vm.expectRevert("WormholeBridge: invalid address");
        governor.fromWormholeFormat(invalidAddress2);

        assertEq(
            governor.fromWormholeFormat(validAddress1),
            address(uint160(uint256(validAddress1))),
            "invalid address 1"
        );
        assertEq(
            governor.fromWormholeFormat(validAddress2),
            address(uint160(uint256(validAddress2))),
            "invalid address 2"
        );
        assertEq(
            governor.fromWormholeFormat(validAddress3),
            address(uint160(uint256(validAddress3))),
            "invalid address 3"
        );
        assertEq(
            governor.fromWormholeFormat(validAddress4),
            address(uint160(uint256(validAddress4))),
            "invalid address 4"
        );
        assertEq(
            governor.fromWormholeFormat(validAddress5),
            address(uint160(uint256(validAddress5))),
            "invalid address 5"
        );
    }

    ///  - updateProposalThreshold
    ///  - updateMaxUserLiveProposals
    ///  - updateQuorum
    ///  - updateVotingPeriod
    ///  - updateVotingDelay
    ///  - updateCrossChainVoteCollectionPeriod
    /// mix and match these items, update one parameter while another proposal is in flight
    /// move the max gas limit too low and brick the thing

    /// TODO
    ///  - test different states, approved, canceled, executed, defeated, succeeded

    function _createProposal() private returns (uint256 proposalId) {
        proposalId = testProposeUpdateProposalThresholdSucceeds();
    }

    function _transferQuorumAndDelegate(address user) private {
        uint256 voteAmount = governor.quorum();

        well.transfer(user, voteAmount);

        vm.prank(user);
        well.delegate(user);

        /// include user before snapshot block
        vm.roll(block.number + 1);
    }

    function _warpPastVotingDelay() private {
        vm.warp(block.timestamp + 1);
    }

    function _castVotes(
        uint256 proposalId,
        uint8 voteValue,
        address user
    ) private {
        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        vm.prank(user);
        governor.castVote(proposalId, voteValue);
    }

    function _warpToVotingPeriod(uint256 proposalId) private {
        (, , uint256 votingStartTime, , , , , , ) = governor
            .proposalInformation(proposalId);

        vm.warp(votingStartTime + 1);
    }

    function _warpPastProposalEnd(uint256 proposalId) private {
        (
            ,
            ,
            ,
            ,
            uint256 crossChainVoteCollectionEndTimestamp,
            ,
            ,
            ,

        ) = governor.proposalInformation(proposalId);

        vm.warp(crossChainVoteCollectionEndTimestamp + 1);
    }

    function testVotingMovesToSucceededStateAfterEnoughForVotesPostXChainVoteCollection()
        public
    {
        address user = address(1);
        _transferQuorumAndDelegate(user);

        uint256 proposalId = _createProposal();

        _warpPastVotingDelay();

        _castVotes(proposalId, Constants.VOTE_VALUE_YES, user);

        _warpPastProposalEnd(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            4,
            "incorrect state, not succeeded"
        );
    }

    function testVotingMovesToDefeatedStateAfterEnoughAgainstForVotes() public {
        address user = address(1);
        _transferQuorumAndDelegate(user);

        uint256 proposalId = _createProposal();

        _warpPastVotingDelay();

        _castVotes(proposalId, Constants.VOTE_VALUE_NO, user);

        _warpPastProposalEnd(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            3,
            "incorrect state, not defeated"
        );
    }

    function testVotingMovesToDefeatedStateAfterEnoughAbstainVotes()
        public
        returns (uint256 proposalId)
    {
        address user = address(1);
        _transferQuorumAndDelegate(user);

        proposalId = _createProposal();

        _warpPastVotingDelay();

        _castVotes(proposalId, Constants.VOTE_VALUE_NO, user);

        _warpPastProposalEnd(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            3,
            "incorrect state, not defeated"
        );
    }

    function testStateMovesToExecutedStateAfterExecution()
        public
        returns (uint256 proposalId)
    {
        address user = address(1);

        _transferQuorumAndDelegate(user);

        proposalId = _createProposal();

        _warpPastVotingDelay();

        _castVotes(proposalId, Constants.VOTE_VALUE_YES, user);

        _warpPastProposalEnd(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            4,
            "incorrect state, not succeeded"
        );

        governor.execute(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            5,
            "incorrect state, not executed"
        );
    }

    function testExecuteFailsAfterExecution() public {
        address user = address(1);
        _transferQuorumAndDelegate(user);

        uint256 proposalId = _createProposal();

        _warpPastVotingDelay();

        _castVotes(proposalId, Constants.VOTE_VALUE_YES, user);

        _warpPastProposalEnd(proposalId);

        governor.execute(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            5,
            "incorrect state, not executed"
        );

        vm.expectRevert(
            "MultichainGovernor: proposal can only be executed if it is Succeeded"
        );
        governor.execute(proposalId);
    }

    function testExecuteFailsAfterDefeat() public {
        uint256 proposalId = testVotingMovesToDefeatedStateAfterEnoughAbstainVotes();

        assertEq(
            uint256(governor.state(proposalId)),
            3,
            "incorrect state, not defeated"
        );

        vm.expectRevert(
            "MultichainGovernor: proposal can only be executed if it is Succeeded"
        );
        governor.execute(proposalId);
    }

    function testExecuteFailsAfterCancel() public {
        uint256 proposalId = _createProposal();

        _warpPastVotingDelay();

        governor.cancel(proposalId);
        assertEq(
            uint256(governor.state(proposalId)),
            2,
            "incorrect state, not canceled"
        );

        vm.expectRevert(
            "MultichainGovernor: proposal can only be executed if it is Succeeded"
        );
        governor.execute(proposalId);
    }

    function testExecuteWithValueSucceeds() public {
        address user = address(1);
        _transferQuorumAndDelegate(user);

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        string memory description = "Proposal MIP-M00 - Deposit WETH";

        MockWeth weth = new MockWeth();
        targets[0] = address(weth);
        values[0] = 100 * 1e18;
        calldatas[0] = abi.encodeWithSignature("deposit()");

        targets[1] = address(weth);
        values[1] = 100 * 1e18;
        calldatas[1] = abi.encodeWithSignature("deposit()");

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

        _warpPastVotingDelay();

        _castVotes(proposalId, Constants.VOTE_VALUE_YES, address(user));

        _warpPastProposalEnd(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            4,
            "incorrect state, not succeeded"
        );

        uint256 totalValue = 200 * 1e18;

        /// TODO why did this test not fail?
        /// TODO assert balances of ETH went to the right addresses
        vm.deal(address(this), totalValue);
        governor.execute{value: totalValue}(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            5,
            "incorrect state, not executed"
        );
    }

    function testExecuteWithValueFailsIfValueIsNotEnough() public {
        address user = address(1);
        _transferQuorumAndDelegate(user);

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        string memory description = "Proposal MIP-M00 - Deposit WETH";

        MockWeth weth = new MockWeth();
        targets[0] = address(weth);
        values[0] = 100 * 1e18;
        calldatas[0] = abi.encodeWithSignature("deposit()");

        targets[1] = address(weth);
        values[1] = 100 * 1e18;
        calldatas[1] = abi.encodeWithSignature("deposit()");

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

        _warpPastVotingDelay();

        _castVotes(proposalId, Constants.VOTE_VALUE_YES, address(user));

        _warpPastProposalEnd(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            4,
            "incorrect state, not succeeded"
        );

        // wrong total value
        uint256 totalValue = 100 * 1e18;

        vm.deal(address(this), totalValue);
        vm.expectRevert("MultichainGovernor: invalid value");
        governor.execute{value: totalValue}(proposalId);
    }

    function testExecuteFailsDuringXChainVoteCollection() public {
        address user = address(1);

        _transferQuorumAndDelegate(user);

        uint256 proposalId = _createProposal();

        _warpToVotingPeriod(proposalId);

        _castVotes(proposalId, Constants.VOTE_VALUE_YES, user);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        _warpPastProposalEnd(proposalId);

        vm.warp(block.timestamp - 1);

        assertEq(
            uint256(governor.state(proposalId)),
            1,
            "incorrect state, not crosschain vote collection"
        );

        vm.expectRevert(
            "MultichainGovernor: proposal can only be executed if it is Succeeded"
        );
        governor.execute(proposalId);
    }

    /// test canceling a proposal

    function testCancelProposalSucceded() public {
        uint256 proposalId = _createProposal();

        _warpPastVotingDelay();

        vm.expectEmit(true, false, false, false, address(governor));
        emit ProposalCanceled(proposalId);
        governor.cancel(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            2,
            "incorrect state, not canceled"
        );
    }

    function testCancelIfProposerVotesBelowThresholdSucceded() public {
        uint256 proposalId = _createProposal();

        // zero tokens
        deal(address(well), address(this), 0);
        deal(address(xwell), address(this), 0);
        deal(address(stkWellMoonbeam), address(this), 0);

        _warpPastVotingDelay();

        vm.expectEmit(true, false, false, false, address(governor));
        emit ProposalCanceled(proposalId);
        governor.cancel(proposalId);
        assertEq(
            uint256(governor.state(proposalId)),
            2,
            "incorrect state, not canceled"
        );
    }

    function testCancelFailsIfSenderIsNotProposerNeitherProposerVotesBelowThreshold()
        public
    {
        address user = address(1);

        uint256 proposalId = _createProposal();

        _warpPastVotingDelay();

        vm.prank(user);
        vm.expectRevert("MultichainGovernor: unauthorized cancel");
        governor.cancel(proposalId);
    }

    function testCancelFailsIfProposalIsAlreadyCanceled() public {
        uint256 proposalId = _createProposal();

        _warpPastVotingDelay();

        governor.cancel(proposalId);
        assertEq(uint256(governor.state(proposalId)), 2, "incorrect state");

        vm.expectRevert(
            "MultichainGovernor: cannot cancel non active proposal"
        );
        governor.cancel(proposalId);
    }

    function testCancelSucceededProposalAfterProposalSucceeds() public {
        uint256 proposalId = _createProposal();

        governor.castVote(proposalId, Constants.VOTE_VALUE_YES);

        _warpPastProposalEnd(proposalId);

        assertEq(uint256(governor.state(proposalId)), 4, "incorrect state");

        vm.expectRevert(
            "MultichainGovernor: cannot cancel non active proposal"
        );
        governor.cancel(proposalId);
    }

    function testCancelDefeatedProposalFails() public {
        uint256 proposalId = _createProposal();

        governor.castVote(proposalId, Constants.VOTE_VALUE_NO);

        _warpPastProposalEnd(proposalId);

        assertEq(uint256(governor.state(proposalId)), 3, "incorrect state");

        vm.expectRevert(
            "MultichainGovernor: cannot cancel non active proposal"
        );
        governor.cancel(proposalId);
    }

    ///  - test changing parameters with multiple live proposals

    function testChangingQuorumWithTwoLiveProposals() public {
        address user = address(1);
        _transferQuorumAndDelegate(user);

        uint256 proposalId1 = _createProposal();
        uint256 proposalId2 = _createProposal();

        _warpPastVotingDelay();

        _castVotes(proposalId1, Constants.VOTE_VALUE_YES, user);
        _castVotes(proposalId2, Constants.VOTE_VALUE_YES, user);

        _warpPastProposalEnd(proposalId2);

        assertEq(
            uint256(governor.state(proposalId1)),
            4,
            "incorrect state for proposal 1, not succeeded"
        );

        assertEq(
            uint256(governor.state(proposalId2)),
            4,
            "incorrect state for proposal 2, not succeeded"
        );

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Proposal MIP-M00 - Update Proposal Quorum";

        targets[0] = address(governor);
        values[0] = 0;
        uint256 newQuorum = governor.quorum() + 1_000_000 * 1e18;
        calldatas[0] = abi.encodeWithSignature(
            "updateQuorum(uint256)",
            newQuorum
        );

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        uint256 proposalIdUpdateQuorum = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalIdUpdateQuorum)),
            0,
            "incorrect state, not active"
        );

        vm.prank(user);
        governor.castVote(proposalIdUpdateQuorum, Constants.VOTE_VALUE_YES);

        _warpPastProposalEnd(proposalIdUpdateQuorum);

        assertEq(
            uint256(governor.state(proposalIdUpdateQuorum)),
            4,
            "incorrect state, not succeeded"
        );

        governor.execute(proposalIdUpdateQuorum);

        assertEq(governor.quorum(), newQuorum);

        // quorum not met
        assertEq(
            uint256(governor.state(proposalId1)),
            3,
            "incorrect state for proposal 1, not defeated"
        );

        assertEq(
            uint256(governor.state(proposalId2)),
            3,
            "incorrect state for proposal 2, not defeated"
        );
    }

    function testChangingMaxUserLiveProposalsWithTwoLiveProposals() public {
        address user = address(1);
        _transferQuorumAndDelegate(user);

        uint256 proposalId1 = _createProposal();
        uint256 proposalId2 = _createProposal();

        _warpPastVotingDelay();

        _castVotes(proposalId1, Constants.VOTE_VALUE_YES, user);
        _castVotes(proposalId2, Constants.VOTE_VALUE_YES, user);

        _warpPastProposalEnd(proposalId2);

        assertEq(
            uint256(governor.state(proposalId1)),
            4,
            "incorrect state for proposal 1, not succeeded"
        );

        assertEq(
            uint256(governor.state(proposalId2)),
            4,
            "incorrect state for proposal 2, not succeeded"
        );

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string
            memory description = "Proposal MIP-M00 - Update Max User Live Proposals";

        targets[0] = address(governor);
        values[0] = 0;
        uint256 newMaxUserLiveProposals = governor.maxUserLiveProposals() - 1;
        calldatas[0] = abi.encodeWithSignature(
            "updateMaxUserLiveProposals(uint256)",
            newMaxUserLiveProposals
        );

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        uint256 proposalIdUpdateMaxLiveProposals = governor.propose{
            value: bridgeCost
        }(targets, values, calldatas, description);

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalIdUpdateMaxLiveProposals)),
            0,
            "incorrect state, not active"
        );

        vm.prank(user);
        governor.castVote(
            proposalIdUpdateMaxLiveProposals,
            Constants.VOTE_VALUE_YES
        );

        _warpPastProposalEnd(proposalIdUpdateMaxLiveProposals);

        assertEq(
            uint256(governor.state(proposalIdUpdateMaxLiveProposals)),
            4,
            "incorrect state, not succeeded"
        );

        governor.execute(proposalIdUpdateMaxLiveProposals);

        assertEq(governor.maxUserLiveProposals(), newMaxUserLiveProposals);
    }

    function testPausingWithThreeLiveProposals() public {
        uint256 proposalId1 = _createProposal();
        uint256 proposalId2 = _createProposal();
        uint256 proposalId3 = _createProposal();

        assertEq(
            uint256(governor.state(proposalId1)),
            0,
            "incorrect state, not active"
        );
        assertEq(
            uint256(governor.state(proposalId2)),
            0,
            "incorrect state, not active"
        );
        assertEq(
            uint256(governor.state(proposalId3)),
            0,
            "incorrect state, not active"
        );

        governor.pause();

        assertEq(uint256(governor.state(proposalId1)), 2, "incorrect state");
        assertEq(uint256(governor.state(proposalId2)), 2, "incorrect state");
        assertEq(uint256(governor.state(proposalId3)), 2, "incorrect state");
    }

    // VIEW FUNCTIONS

    function testGetProposalData() public {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = governor.getProposalData(proposalId);

        assertEq(targets.length, 1, "incorrect targets length");
        assertEq(values.length, 1, "incorrect values length");
        assertEq(calldatas.length, 1, "incorrect calldatas length");

        assertEq(targets[0], address(governor), "incorrect target");
        assertEq(values[0], 0, "incorrect value");
        assertEq(
            calldatas[0],
            abi.encodeWithSignature(
                "updateProposalThreshold(uint256)",
                100_000_000 * 1e18
            ),
            "incorrect calldata"
        );
    }

    function testGetNumLiveProposals() public {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();
        assertEq(
            governor.getNumLiveProposals(),
            1,
            "incorrect num live proposals"
        );
        governor.cancel(proposalId);
        assertEq(
            governor.getNumLiveProposals(),
            0,
            "incorrect num live proposals"
        );
    }

    function testCurrentUserLiveProposals() public {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();
        assertEq(
            governor.currentUserLiveProposals(address(this)),
            1,
            "incorrect num live proposals"
        );
        governor.cancel(proposalId);
        assertEq(
            governor.currentUserLiveProposals(address(this)),
            0,
            "incorrect num live proposals"
        );
    }

    function testLiveProposals() public {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();
        assertEq(
            governor.liveProposals()[0],
            proposalId,
            "incorrect num live proposals"
        );
        governor.cancel(proposalId);
        assertEq(
            governor.liveProposals().length,
            0,
            "incorrect num live proposals"
        );
    }

    function testGetUserLiveProposals() public {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        assertEq(uint256(governor.state(proposalId)), 0, "incorrect state");

        assertEq(
            governor.getUserLiveProposals(address(this))[0],
            proposalId,
            "incorrect live proposal at index 0"
        );
        assertEq(
            governor.getUserLiveProposals(address(this)).length,
            1,
            "incorrect num live proposals pre cancellation"
        );
        governor.cancel(proposalId);

        assertEq(
            governor.getUserLiveProposals(address(this)).length,
            0,
            "incorrect num live proposals post cancellation"
        );
    }

    function testGetUserLiveProposalsWithNonActiveProposals() public {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.warp(
            block.timestamp +
                governor.votingPeriod() +
                governor.crossChainVoteCollectionPeriod() +
                1
        );

        assertEq(
            governor.getUserLiveProposals(address(this)).length,
            0,
            "incorrect num live proposals"
        );

        assertEq(uint256(governor.state(proposalId)), 3, "incorrect state");

        vm.expectRevert(
            "MultichainGovernor: cannot cancel non active proposal"
        );
        governor.cancel(proposalId);

        assertEq(
            governor.getUserLiveProposals(address(this)).length,
            0,
            "incorrect num live proposals"
        );
    }

    function testGetCurrentVotes() public {
        testUserVotingToProposalWithDifferentTokensSucceeds();

        assertEq(
            governor.getCurrentVotes(address(1)),
            3_000_000 * 1e18,
            "incorrect current votes"
        );
    }

    function testStateInvalidProposalId() public {
        testProposeUpdateProposalThresholdSucceeds();

        vm.expectRevert("MultichainGovernor: invalid proposal id");
        governor.state(0);

        vm.expectRevert("MultichainGovernor: invalid proposal id");
        governor.state(2);
    }

    // bridge in

    function testBridgeInWrongPayloadLength() public {
        bytes memory payload = abi.encode(0, 0, 0);
        uint256 gasCost = wormholeRelayerAdapter.nativePriceQuote();

        vm.deal(address(voteCollection), gasCost);
        vm.prank(address(voteCollection));
        vm.expectRevert("MultichainGovernor: invalid payload length");
        wormholeRelayerAdapter.sendPayloadToEvm{value: gasCost}(
            moonBeamWormholeChainId,
            address(governor),
            payload,
            0,
            0
        );
    }

    function testBridgeInProposalNotInCrossChainPeriod() public {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        bytes memory payload = abi.encode(proposalId, 0, 0, 0);
        uint256 gasCost = wormholeRelayerAdapter.nativePriceQuote();

        vm.deal(address(voteCollection), gasCost);
        vm.prank(address(voteCollection));
        vm.expectRevert(
            "MultichainGovernor: proposal not in cross chain vote collection period"
        );
        wormholeRelayerAdapter.sendPayloadToEvm{value: gasCost}(
            moonBeamWormholeChainId,
            address(governor),
            payload,
            0,
            0
        );
    }

    // test multiple proposals live at the same time
    // proposal 1 is created at time 102 and has 0 votes, final state: defeated
    // proposal 2 is created at time 103, votes at timestamp 104 vote
    // value is for, final state: succeeded
    // proposal 3 is created at time proposal 1
    // crossChainVoteCollectionEndTimestamp and vote value
    // is against, final state: defeated
    // proposal 4 created at proposal3 crossChainVoteCollectionEndTimestamp, final state: active
    function testMultipleProposalsCreatedAtDifferentTimes() public {
        uint256 proposalId1 = testProposeUpdateProposalThresholdSucceeds(); // timestamp here is proposal1 voting start timestamp (102)

        vm.warp(block.timestamp + 1); // timestamp is 103

        uint256 proposalId2 = testVotingValidProposalIdSucceeds(); // timestamp
        // is 104

        // proposal1 and proposal2 are active at this stage

        {
            // check live proposals
            uint256[] memory proposals = governor.liveProposals();

            bool proposal1Found;
            bool proposal2Found;

            for (uint256 i = 0; i < proposals.length; i++) {
                if (proposal1Found && proposal2Found) {
                    break;
                }
                if (proposals[i] == proposalId1) {
                    proposal1Found = true;
                }
                if (proposals[i] == proposalId2) {
                    proposal2Found = true;
                }
            }

            assertTrue(
                proposal1Found,
                "proposal 1 not found in live proposals"
            );
            assertTrue(
                proposal2Found,
                "proposal 2 not found in live proposals"
            );
        }
        {
            // check user proposals
            uint256[] memory userProposals = governor.getUserLiveProposals(
                address(this)
            );

            bool proposal1Found;
            bool proposal2Found;

            for (uint256 i = 0; i < userProposals.length; i++) {
                if (proposal1Found && proposal2Found) {
                    break;
                }
                if (userProposals[i] == proposalId1) {
                    proposal1Found = true;
                }
                if (userProposals[i] == proposalId2) {
                    proposal2Found = true;
                }
            }
            assertTrue(
                proposal1Found,
                "proposal 1 not found in user live proposals"
            );

            assertTrue(
                proposal2Found,
                "proposal 2 not found in user live proposals"
            );
        }

        IMultichainGovernor.ProposalInformation memory proposal1Info = governor
            .proposalInformationStruct(proposalId1);

        vm.warp(proposal1Info.crossChainVoteCollectionEndTimestamp + 1);

        uint256 proposalId3 = testProposeUpdateProposalThresholdSucceeds();

        // Proposal 1 is defetead, proposal2 active, proposal 3 active
        {
            bool proposal1Found;
            bool proposal2Found;
            bool proposal3Found;

            uint256[] memory proposals = governor.liveProposals();

            for (uint256 i = 0; i < proposals.length; i++) {
                if (proposal1Found && proposal2Found && proposal3Found) {
                    break;
                }
                if (proposals[i] == proposalId1) {
                    proposal1Found = true;
                }
                if (proposals[i] == proposalId2) {
                    proposal2Found = true;
                }
                if (proposals[i] == proposalId3) {
                    proposal3Found = true;
                }
            }

            assertFalse(proposal1Found, "proposal 1 found in live proposals");
            assertTrue(
                proposal2Found,
                "proposal 2 not found in live proposals"
            );
            assertTrue(
                proposal3Found,
                "proposal 3 not found in live proposals"
            );
        }

        {
            // check user live proposals
            bool proposal1Found;
            bool proposal2Found;
            bool proposal3Found;

            /// TODO check array length here
            /// you could probably also get away with removing the for loop
            /// and just accessing array elements directly
            uint256[] memory userProposals = governor.getUserLiveProposals(
                address(this)
            );

            for (uint256 i = 0; i < userProposals.length; i++) {
                if (proposal1Found && proposal2Found && proposal3Found) {
                    break;
                }
                if (userProposals[i] == proposalId1) {
                    proposal1Found = true;
                }
                if (userProposals[i] == proposalId2) {
                    proposal2Found = true;
                }
                if (userProposals[i] == proposalId3) {
                    proposal3Found = true;
                }
            }

            assertFalse(
                proposal1Found,
                "proposal 1 found in user live proposals"
            );

            assertTrue(
                proposal2Found,
                "proposal 2 not found in user live proposals"
            );

            assertTrue(
                proposal3Found,
                "proposal 3 not found in user live proposals"
            );
        }

        IMultichainGovernor.ProposalInformation memory proposal3Info = governor
            .proposalInformationStruct(proposalId3);

        vm.warp(proposal3Info.crossChainVoteCollectionEndTimestamp + 1);

        uint256 proposalId4 = testProposeUpdateProposalThresholdSucceeds();

        // only proposal 4 is active
        {
            bool proposal1Found;
            bool proposal2Found;
            bool proposal3Found;
            bool proposal4Found;

            uint256[] memory proposals = governor.liveProposals();

            for (uint256 i = 0; i < proposals.length; i++) {
                if (
                    proposal1Found &&
                    proposal2Found &&
                    proposal3Found &&
                    proposal4Found
                ) {
                    break;
                }
                if (proposals[i] == proposalId1) {
                    proposal1Found = true;
                }
                if (proposals[i] == proposalId2) {
                    proposal2Found = true;
                }
                if (proposals[i] == proposalId3) {
                    proposal3Found = true;
                }
                if (proposals[i] == proposalId4) {
                    proposal4Found = true;
                }
            }

            assertFalse(proposal1Found, "proposal 1 found in live proposals");
            assertFalse(proposal2Found, "proposal 2 found in live proposals");
            assertFalse(proposal3Found, "proposal 3 found in live proposals");
            assertTrue(
                proposal4Found,
                "proposal 4 not found in live proposals"
            );
        }

        // check user live proposals
        {
            bool proposal1Found;
            bool proposal2Found;
            bool proposal3Found;
            bool proposal4Found;

            uint256[] memory userProposals = governor.getUserLiveProposals(
                address(this)
            );

            for (uint256 i = 0; i < userProposals.length; i++) {
                if (
                    proposal1Found &&
                    proposal2Found &&
                    proposal3Found &&
                    proposal4Found
                ) {
                    break;
                }
                if (userProposals[i] == proposalId1) {
                    proposal1Found = true;
                }
                if (userProposals[i] == proposalId2) {
                    proposal2Found = true;
                }
                if (userProposals[i] == proposalId3) {
                    proposal3Found = true;
                }
                if (userProposals[i] == proposalId4) {
                    proposal4Found = true;
                }
            }

            assertFalse(
                proposal1Found,
                "proposal 1 found in user live proposals"
            );
            assertFalse(
                proposal2Found,
                "proposal 2 found in user live proposals"
            );
            assertFalse(
                proposal3Found,
                "proposal 3 found in user live proposals"
            );
            assertTrue(
                proposal4Found,
                "proposal 4 not found in user live proposals"
            );
        }

        // check final state of proposals
        assertEq(
            uint256(governor.state(proposalId1)),
            3,
            "incorrect state, not defeated"
        );

        assertEq(
            uint256(governor.state(proposalId2)),
            4,
            "incorrect state, not succeeded"
        );

        assertEq(
            uint256(governor.state(proposalId3)),
            3,
            "incorrect state, not defeated"
        );

        assertEq(
            uint256(governor.state(proposalId4)),
            0,
            "incorrect state, not active"
        );

        /// TODO assert that as many of the state transitions that happened are correct
        /// - totalLiveProposals
        /// - current live proposals returned from getter functions
        /// - user live proposals returned from getter functions
    }

    function testUserCanCreateAsManyProposalWantsAsLongNeverExceedsMaxUserLiveProposals()
        public
    {
        for (uint256 i = 0; i < 5; i++) {
            testProposeUpdateProposalThresholdSucceeds();
        }

        assertEq(
            governor.currentUserLiveProposals(address(this)),
            5,
            "incorrect num live proposals"
        );

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Mock Proposal MIP-M00";

        vm.expectRevert(
            "MultichainGovernor: too many live proposals for this user"
        );
        governor.propose(targets, values, calldatas, description);

        governor.cancel(1);

        assertEq(
            governor.currentUserLiveProposals(address(this)),
            4,
            "incorrect num live proposals"
        );

        testProposeUpdateProposalThresholdSucceeds();

        assertEq(
            governor.currentUserLiveProposals(address(this)),
            5,
            "incorrect num live proposals"
        );

        /// TODO vote/execute proposals here, see that the number decreases
        /// TODO try another test like this where multiple users try to hit the max proposal count
    }
}
