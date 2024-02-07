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

    event BridgeOutFailed(uint16 chainId, bytes payload, uint256 refundAmount);

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

    function setUp() public override {
        super.setUp();

        xwell.delegate(address(this));
        well.delegate(address(this));
        distributor.delegate(address(this));

        vm.roll(block.number + 1);
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
        uint256 proposalId = _createProposalUpdateThreshold(address(this));

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
        _assertGovernanceBalance();

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

        _assertGovernanceBalance();
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

        _assertGovernanceBalance();
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

        _assertGovernanceBalance();
    }

    function testProposeNoActionsFails() public {
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory calldatas = new bytes[](0);
        string memory description = "Mock Empty Proposal MIP-M00";

        vm.expectRevert("MultichainGovernor: must provide actions");
        governor.propose(targets, values, calldatas, description);

        _assertGovernanceBalance();
    }

    function testProposeNoDescriptionsFails() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "";

        vm.expectRevert("MultichainGovernor: description can not be empty");
        governor.propose(targets, values, calldatas, description);

        _assertGovernanceBalance();
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

        _assertGovernanceBalance();
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

        _assertGovernanceBalance();
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

        uint256 startTimestamp = block.timestamp;
        uint256 endTimestamp = startTimestamp + governor.votingPeriod();
        bytes memory payload = abi.encode(
            1,
            startTimestamp - 1,
            startTimestamp,
            endTimestamp,
            endTimestamp + governor.crossChainVoteCollectionPeriod()
        );

        address proposer = address(2);
        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(proposer, bridgeCost);

        uint256 proposerBalance = proposer.balance;

        wormholeRelayerAdapter.setShouldRevert(true);

        _delegateVoteAmountForUser(
            address(well),
            proposer,
            governor.proposalThreshold()
        );

        vm.roll(block.number + 1);

        vm.expectEmit(true, true, true, true, address(governor));
        emit BridgeOutFailed(baseWormholeChainId, payload, bridgeCost);

        vm.prank(proposer);
        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        uint256 proposerBalanceAfter = proposer.balance;

        // bridge out failed so proposer balance should not change
        assertEq(proposerBalanceAfter, proposerBalance, "incorrect balance");
        assertEq(proposerBalanceAfter, bridgeCost, "incorrect balance");

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

        _assertGovernanceBalance();

        return proposalId;
    }

    function testBridgeFailOutRefundFail() public {
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

        uint256 startTimestamp = block.timestamp;
        uint256 endTimestamp = startTimestamp + governor.votingPeriod();
        bytes memory payload = abi.encode(
            1,
            startTimestamp - 1,
            startTimestamp,
            endTimestamp,
            endTimestamp + governor.crossChainVoteCollectionPeriod()
        );

        // address(this) doesn't have fallback function
        address proposer = address(this);
        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(proposer, bridgeCost);

        uint256 proposerBalance = proposer.balance;

        wormholeRelayerAdapter.setShouldRevert(true);

        _delegateVoteAmountForUser(
            address(well),
            proposer,
            governor.proposalThreshold()
        );

        vm.roll(block.number + 1);

        vm.expectEmit(true, true, true, true, address(governor));
        emit BridgeOutFailed(baseWormholeChainId, payload, bridgeCost);

        vm.expectRevert("WormholeBridge: refund failed");
        vm.prank(proposer);
        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        uint256[] memory proposals = governor.liveProposals();

        bool proposalFound;

        for (uint256 i = 0; i < proposals.length; i++) {
            if (proposals[i] == proposalId) {
                proposalFound = true;
                break;
            }
        }

        assertFalse(proposalFound, "proposal found in live proposals");

        uint256 proposerBalanceAfter = proposer.balance;

        // call revert so proposer balance should not change
        assertEq(proposerBalanceAfter, proposerBalance, "incorrect balance");
        assertEq(proposerBalanceAfter, bridgeCost, "incorrect balance");

        _assertGovernanceBalance();
    }

    function testBridgeOutQuoteEVMPriceRevert() public {
        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        wormholeRelayerAdapter.setShouldRevertQuote(true);
        vm.expectRevert("WormholeBridge: total cost not equal to quote");
        governor.propose{value: bridgeCost}(
            new address[](1),
            new uint256[](1),
            new bytes[](1),
            "Proposal MIP-M00 - Update Proposal Threshold"
        );

        uint256 startTimestamp = block.timestamp;
        uint256 endTimestamp = startTimestamp + governor.votingPeriod();
        bytes memory payload = abi.encode(
            1,
            startTimestamp - 1,
            startTimestamp,
            endTimestamp,
            endTimestamp + governor.crossChainVoteCollectionPeriod()
        );

        // calling without value should not revert but emit BridgeOutFailed
        vm.expectEmit(true, true, true, true, address(governor));
        emit BridgeOutFailed(baseWormholeChainId, payload, 0);
        governor.propose(
            new address[](1),
            new uint256[](1),
            new bytes[](1),
            "Proposal MIP-M00 - Update Proposal Threshold"
        );

        _assertGovernanceBalance();
    }

    function testRebroadcastProposalSucceedsProposalActive() public {
        uint256 proposalId = _createProposalUpdateThreshold(address(this));
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

        address caller = address(2);
        vm.deal(caller, cost);

        vm.expectEmit(true, true, true, true, address(governor));
        emit ProposalRebroadcasted(proposalId, payload);

        vm.prank(caller);
        governor.rebroadcastProposal{value: cost}(proposalId);

        _assertGovernanceBalance();
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
        address caller = address(2);
        vm.deal(caller, cost);

        vm.expectEmit(true, true, true, true, address(governor));
        emit BridgeOutFailed(baseWormholeChainId, payload, cost);

        vm.expectEmit(true, true, true, true, address(governor));
        emit ProposalRebroadcasted(proposalId, payload);

        vm.prank(caller);
        governor.rebroadcastProposal{value: cost}(proposalId);

        vm.deal(caller, cost);

        vm.expectEmit(true, true, true, true, address(governor));
        emit BridgeOutFailed(baseWormholeChainId, payload, cost);

        vm.expectEmit(true, true, true, true, address(governor));
        emit ProposalRebroadcasted(proposalId, payload);

        vm.prank(caller);
        governor.rebroadcastProposal{value: cost}(proposalId);

        _assertGovernanceBalance();
    }

    function testRebroadcastProposalFailsInvalidProposalId() public {
        uint256 proposalId = 100;

        vm.expectRevert("MultichainGovernor: invalid proposal id");
        governor.rebroadcastProposal(proposalId);

        _assertGovernanceBalance();
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

        _assertGovernanceBalance();
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

        _assertGovernanceBalance();
    }

    function testRebroadcastProposalFailsNoValue() public {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        vm.expectRevert("WormholeBridge: total cost not equal to quote");
        governor.rebroadcastProposal(proposalId);

        _assertGovernanceBalance();
    }

    function testRebroadcastProposalFailsIncorrectValue() public {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        uint256 cost = governor.bridgeCostAll() - 2012;
        vm.deal(address(this), cost);

        vm.expectRevert("WormholeBridge: total cost not equal to quote");
        governor.rebroadcastProposal{value: cost}(proposalId);

        _assertGovernanceBalance();
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

        vm.deal(address(2), bridgeCost);

        vm.expectEmit(true, true, true, true, address(governor));
        emit ProposalRebroadcasted(proposalId, payload);
        vm.prank(address(2));
        governor.rebroadcastProposal{value: bridgeCost}(proposalId);

        _assertGovernanceBalance();
    }

    /// Voting on MultichainGovernor
    function testVotingValidProposalIdSucceeds()
        public
        returns (uint256 proposalId)
    {
        proposalId = testProposeUpdateProposalThresholdSucceeds();

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        // get user votes

        uint256 votesUserBefore = governor.getVotes(
            address(this),
            block.timestamp - 1,
            block.number - 1
        );

        // get total votes before
        (
            uint256 totalVotesBefore,
            uint256 votesForBefore,
            uint256 votesAgainstBefore,
            uint256 votesAbstainBefore
        ) = governor.proposalVotes(proposalId);

        governor.castVote(proposalId, Constants.VOTE_VALUE_YES);

        (bool hasVoted, uint256 voteValue, uint256 votes) = governor.getReceipt(
            proposalId,
            address(this)
        );
        assertTrue(hasVoted, "user did not vote");
        assertEq(voteValue, Constants.VOTE_VALUE_YES, "user did not vote yes");
        assertEq(votes, votesUserBefore, "user votes incorrect");

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        (
            uint256 totalVotes,
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 votesAbstain
        ) = governor.proposalVotes(proposalId);

        assertEq(
            votesFor - votesForBefore,
            14_000_000_000 * 1e18,
            "votes for incorrect"
        );
        assertEq(
            votesAgainst - votesAgainstBefore,
            0,
            "votes against incorrect"
        );
        assertEq(
            votesAbstain - votesAbstainBefore,
            0,
            "abstain votes incorrect"
        );
        assertEq(votesFor, totalVotes, "total votes incorrect");
        assertEq(
            totalVotes - totalVotesBefore,
            14_000_000_000 * 1e18,
            "total votes incorrect"
        );

        _assertGovernanceBalance();
    }

    /// cannot vote twice on the same proposal

    function testVotingTwiceSameProposalFails() public {
        uint256 proposalId = testVotingValidProposalIdSucceeds();

        vm.expectRevert("MultichainGovernor: voter already voted");
        governor.castVote(proposalId, Constants.VOTE_VALUE_YES);

        _assertGovernanceBalance();
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

        _assertGovernanceBalance();
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

        _assertGovernanceBalance();
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

        _assertGovernanceBalance();
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

        _assertGovernanceBalance();
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

        _assertGovernanceBalance();
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

        _assertGovernanceBalance();
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

        {
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

            assertEq(totalVotes, voteAmount, "incorrect total votes");
            assertEq(forVotes, voteAmount, "incorrect for votes");
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }

        vm.prank(user2);
        governor.castVote(proposalId, Constants.VOTE_VALUE_NO);

        {
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

            assertEq(totalVotes, 2 * voteAmount, "incorrect total votes");
            assertEq(forVotes, voteAmount, "incorrect for votes");
            assertEq(againstVotes, voteAmount, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }

        vm.prank(user3);
        governor.castVote(proposalId, Constants.VOTE_VALUE_ABSTAIN);

        {
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

            assertEq(totalVotes, 3 * voteAmount, "incorrect total votes");
            assertEq(forVotes, voteAmount, "incorrect for votes");
            assertEq(againstVotes, voteAmount, "incorrect against votes");
            assertEq(abstainVotes, voteAmount, "incorrect abstain votes");
        }

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

        _assertGovernanceBalance();
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

        _assertGovernanceBalance();
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

        _assertGovernanceBalance();
    }

    // STAKED WELL
    function testMultipleUserVoteStkWellSucceeded() public {
        address user1 = address(1);
        address user2 = address(2);
        address user3 = address(3);
        uint256 voteAmount = 1_000_000 * 1e18;

        {
            xwell.transfer(user1, voteAmount);

            uint256 stkWellBalanceBefore = stkWellMoonbeam.balanceOf(user1);
            uint256 stkWellTotalSupplyBefore = stkWellMoonbeam.totalSupply();
            // get votes before
            uint256 votesUserBefore = governor.getVotes(
                user1,
                block.timestamp - 1,
                block.number - 1
            );

            vm.startPrank(user1);
            xwell.approve(address(stkWellMoonbeam), voteAmount);
            stkWellMoonbeam.stake(user1, voteAmount);
            vm.stopPrank();

            uint256 stkWellBalanceAfter = stkWellMoonbeam.balanceOf(user1);
            uint256 stkWellTotalSupplyAfter = stkWellMoonbeam.totalSupply();

            vm.roll(block.number + 1);

            // get votes after
            uint256 votesUserAfter = governor.getVotes(
                user1,
                block.timestamp - 1,
                block.number - 1
            );

            assertEq(
                stkWellBalanceAfter - stkWellBalanceBefore,
                voteAmount,
                "incorrect stkWell balance"
            );
            assertEq(
                stkWellTotalSupplyAfter - stkWellTotalSupplyBefore,
                voteAmount,
                "incorrect total supply"
            );
            assertEq(
                votesUserAfter - votesUserBefore,
                voteAmount,
                "incorrect votes"
            );
        }

        {
            uint256 stkWellBalanceBefore = stkWellMoonbeam.balanceOf(user2);
            uint256 stkWellTotalSupplyBefore = stkWellMoonbeam.totalSupply();
            // get votes before
            uint256 votesUserBefore = governor.getVotes(
                user2,
                block.timestamp - 1,
                block.number - 1
            );

            xwell.transfer(user2, voteAmount);

            vm.startPrank(user2);
            xwell.approve(address(stkWellMoonbeam), voteAmount);
            stkWellMoonbeam.stake(user2, voteAmount);
            vm.stopPrank();

            uint256 stkWellBalanceAfter = stkWellMoonbeam.balanceOf(user2);
            uint256 stkWellTotalSupplyAfter = stkWellMoonbeam.totalSupply();

            vm.roll(block.number + 1);

            // get votes after
            uint256 votesUserAfter = governor.getVotes(
                user2,
                block.timestamp - 1,
                block.number - 1
            );

            assertEq(
                stkWellBalanceAfter - stkWellBalanceBefore,
                voteAmount,
                "incorrect stkWell balance"
            );

            assertEq(
                stkWellTotalSupplyAfter - stkWellTotalSupplyBefore,
                voteAmount,
                "incorrect total supply"
            );

            assertEq(
                votesUserAfter - votesUserBefore,
                voteAmount,
                "incorrect votes"
            );
        }

        {
            xwell.transfer(user3, voteAmount);

            uint256 stkWellBalanceBefore = stkWellMoonbeam.balanceOf(user3);
            uint256 stkWellTotalSupplyBefore = stkWellMoonbeam.totalSupply();
            // get votes before
            uint256 votesUserBefore = governor.getVotes(
                user3,
                block.timestamp - 1,
                block.number - 1
            );

            vm.startPrank(user3);
            xwell.approve(address(stkWellMoonbeam), voteAmount);
            stkWellMoonbeam.stake(user3, voteAmount);
            vm.stopPrank();

            uint256 stkWellBalanceAfter = stkWellMoonbeam.balanceOf(user3);
            uint256 stkWellTotalSupplyAfter = stkWellMoonbeam.totalSupply();

            vm.roll(block.number + 1);

            // get votes after
            uint256 votesUserAfter = governor.getVotes(
                user3,
                block.timestamp - 1,
                block.number - 1
            );

            assertEq(
                stkWellBalanceAfter - stkWellBalanceBefore,
                voteAmount,
                "incorrect stkWell balance"
            );

            assertEq(
                stkWellTotalSupplyAfter - stkWellTotalSupplyBefore,
                voteAmount,
                "incorrect total supply"
            );

            assertEq(
                votesUserAfter - votesUserBefore,
                voteAmount,
                "incorrect votes"
            );
        }

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

        _assertGovernanceBalance();
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

        _assertGovernanceBalance();
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

    function testVotingMovesToSucceededStateAfterEnoughForVotesPostXChainVoteCollection()
        public
    {
        address user = address(1);
        _transferQuorumAndDelegate(user);

        uint256 proposalId = _createProposal();

        _castVotes(proposalId, Constants.VOTE_VALUE_YES, user);

        _warpPastProposalEnd(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            4,
            "incorrect state, not succeeded"
        );

        _assertGovernanceBalance();
    }

    function testVotingMovesToDefeatedStateAfterEnoughAgainstForVotes() public {
        address user = address(1);
        _transferQuorumAndDelegate(user);

        uint256 proposalId = _createProposal();

        _castVotes(proposalId, Constants.VOTE_VALUE_NO, user);

        _warpPastProposalEnd(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            3,
            "incorrect state, not defeated"
        );

        _assertGovernanceBalance();
    }

    function testVotingMovesToDefeatedStateAfterEnoughAbstainVotes()
        public
        returns (uint256 proposalId)
    {
        address user = address(1);
        _transferQuorumAndDelegate(user);

        proposalId = _createProposal();

        _castVotes(proposalId, Constants.VOTE_VALUE_NO, user);

        _warpPastProposalEnd(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            3,
            "incorrect state, not defeated"
        );

        _assertGovernanceBalance();
    }

    function testStateMovesToExecutedStateAfterExecution()
        public
        returns (uint256 proposalId)
    {
        address user = address(1);

        _transferQuorumAndDelegate(user);

        proposalId = _createProposal();

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

        _assertGovernanceBalance();
    }

    function testExecuteFailsAfterExecution() public {
        address user = address(1);
        _transferQuorumAndDelegate(user);

        uint256 proposalId = _createProposal();

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

        vm.expectRevert(
            "MultichainGovernor: proposal can only be executed if it is Succeeded"
        );
        governor.execute(proposalId);

        _assertGovernanceBalance();
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

        _assertGovernanceBalance();
    }

    function testExecuteFailsAfterCancel() public {
        uint256 proposalId = _createProposal();

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

        _assertGovernanceBalance();
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

        _castVotes(proposalId, Constants.VOTE_VALUE_YES, address(user));

        _warpPastProposalEnd(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            4,
            "incorrect state, not succeeded"
        );

        uint256 totalValue = 200 * 1e18;

        uint256 wethEthBalanceBefore = address(weth).balance;

        vm.deal(address(this), totalValue);
        governor.execute{value: totalValue}(proposalId);

        uint256 wethEthBalanceAfter = address(weth).balance;
        assertEq(
            wethEthBalanceAfter - wethEthBalanceBefore,
            totalValue,
            "incorrect weth eth balance"
        );
        assertEq(address(this).balance, 0, "incorrect eth balance");

        assertEq(
            uint256(governor.state(proposalId)),
            5,
            "incorrect state, not executed"
        );

        _assertGovernanceBalance();
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

        _assertGovernanceBalance();
    }

    function testExecuteFailsDuringXChainVoteCollection() public {
        address user = address(1);

        _transferQuorumAndDelegate(user);

        uint256 proposalId = _createProposal();

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

        _assertGovernanceBalance();
    }

    /// test canceling a proposal

    function testCancelProposalSucceded() public {
        uint256 proposalId = _createProposal();

        vm.expectEmit(true, false, false, false, address(governor));
        emit ProposalCanceled(proposalId);
        governor.cancel(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            2,
            "incorrect state, not canceled"
        );

        _assertGovernanceBalance();
    }

    function testCancelIfProposerVotesBelowThresholdSucceded() public {
        uint256 proposalId = _createProposal();

        // zero tokens
        deal(address(well), address(this), 0);
        deal(address(xwell), address(this), 0);
        deal(address(stkWellMoonbeam), address(this), 0);

        vm.expectEmit(true, false, false, false, address(governor));
        emit ProposalCanceled(proposalId);
        governor.cancel(proposalId);
        assertEq(
            uint256(governor.state(proposalId)),
            2,
            "incorrect state, not canceled"
        );

        _assertGovernanceBalance();
    }

    function testCancelFailsIfSenderIsNotProposerNeitherProposerVotesBelowThreshold()
        public
    {
        address user = address(1);

        uint256 proposalId = _createProposal();

        vm.prank(user);
        vm.expectRevert("MultichainGovernor: unauthorized cancel");

        governor.cancel(proposalId);

        _assertGovernanceBalance();
    }

    function testCancelFailsIfProposalIsAlreadyCanceled() public {
        uint256 proposalId = _createProposal();

        governor.cancel(proposalId);
        assertEq(uint256(governor.state(proposalId)), 2, "incorrect state");

        vm.expectRevert(
            "MultichainGovernor: cannot cancel non active proposal"
        );
        governor.cancel(proposalId);

        _assertGovernanceBalance();
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

        _assertGovernanceBalance();
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

        _assertGovernanceBalance();
    }

    ///  - test changing parameters with multiple live proposals

    function testChangingQuorumWithTwoLiveProposals() public {
        address user = address(1);
        _transferQuorumAndDelegate(user);

        uint256 proposalId1 = _createProposal();
        uint256 proposalId2 = _createProposal();

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

        _assertGovernanceBalance();
    }

    function testChangingMaxUserLiveProposalsWithTwoLiveProposals() public {
        address user = address(1);
        _transferQuorumAndDelegate(user);

        uint256 proposalId1 = _createProposal();
        uint256 proposalId2 = _createProposal();

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

        _assertGovernanceBalance();
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

        _assertGovernanceBalance();
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

        _assertGovernanceBalance();
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

        // create proposal and vote
        proposalId = testProposeUpdateProposalThresholdSucceeds();

        assertEq(
            governor.liveProposals()[0],
            proposalId,
            "incorrect num live proposals"
        );

        vm.warp(block.timestamp + 1);

        governor.castVote(proposalId, Constants.VOTE_VALUE_YES);

        _warpPastProposalEnd(proposalId);

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

        // create proposal and vote
        proposalId = testProposeUpdateProposalThresholdSucceeds();

        assertEq(
            governor.getUserLiveProposals(address(this))[0],
            proposalId,
            "incorrect live proposal at index 0"
        );

        vm.warp(block.timestamp + 1);

        governor.castVote(proposalId, Constants.VOTE_VALUE_YES);

        _warpPastProposalEnd(proposalId);

        assertEq(
            governor.getUserLiveProposals(address(this)).length,
            0,
            "incorrect num live proposals"
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
            assertEq(proposals.length, 2, "incorrect live proposals length");
            assertEq(
                proposals[0],
                proposalId1,
                "incorrect live proposal at index 0"
            );
            assertEq(
                proposals[1],
                proposalId2,
                "incorrect live proposal at index 1"
            );

            // check user proposals
            uint256[] memory userProposals = governor.getUserLiveProposals(
                address(this)
            );
            assertEq(
                userProposals.length,
                2,
                "incorrect user live proposals length"
            );
            assertEq(
                userProposals[0],
                proposalId1,
                "incorrect user live proposal at index 0"
            );
            assertEq(
                userProposals[1],
                proposalId2,
                "incorrect user live proposal at index 1"
            );
        }

        IMultichainGovernor.ProposalInformation memory proposal1Info = governor
            .proposalInformationStruct(proposalId1);

        vm.warp(proposal1Info.crossChainVoteCollectionEndTimestamp + 1);

        uint256 proposalId3 = testProposeUpdateProposalThresholdSucceeds();

        {
            uint256[] memory proposals = governor.liveProposals();
            assertEq(proposals.length, 2, "incorrect live proposals length");
            assertEq(
                proposals[0],
                proposalId2,
                "incorrect live proposal at index 0"
            );
            assertEq(
                proposals[1],
                proposalId3,
                "incorrect live proposal at index 1"
            );

            uint256[] memory userProposals = governor.getUserLiveProposals(
                address(this)
            );
            assertEq(
                userProposals.length,
                2,
                "incorrect user live proposals length"
            );
            assertEq(
                userProposals[0],
                proposalId2,
                "incorrect user live proposal at index 0"
            );
            assertEq(
                userProposals[1],
                proposalId3,
                "incorrect user live proposal at index 1"
            );
        }

        IMultichainGovernor.ProposalInformation memory proposal3Info = governor
            .proposalInformationStruct(proposalId3);

        vm.warp(proposal3Info.crossChainVoteCollectionEndTimestamp + 1);

        uint256 proposalId4 = testProposeUpdateProposalThresholdSucceeds();

        {
            // check live proposals
            uint256[] memory proposals = governor.liveProposals();
            assertEq(proposals.length, 1, "incorrect live proposals length");
            assertEq(proposals[0], proposalId4, "incorrect live proposal");

            // check user live proposals
            uint256[] memory userProposals = governor.getUserLiveProposals(
                address(this)
            );
            assertEq(
                userProposals.length,
                1,
                "incorrect user live proposals length"
            );
            assertEq(
                userProposals[0],
                proposalId4,
                "incorrect user live proposal at index 0"
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

        _assertGovernanceBalance();
    }

    function testUserCanCreateAsManyProposalWantsAsLongNeverExceedsMaxUserLiveProposals()
        public
    {
        for (uint256 i = 0; i < 5; i++) {
            testProposeUpdateProposalThresholdSucceeds();
            vm.warp(block.timestamp + 1);

            assertEq(governor.currentUserLiveProposals(address(this)), i + 1);
            assertEq(governor.liveProposals().length, i + 1);
        }

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
        assertEq(governor.liveProposals().length, 4);

        testProposeUpdateProposalThresholdSucceeds();

        assertEq(
            governor.currentUserLiveProposals(address(this)),
            5,
            "incorrect num live proposals"
        );
        assertEq(governor.liveProposals().length, 5);

        uint256 proposalId = 2;

        _castVotes(proposalId, Constants.VOTE_VALUE_YES, address(this));

        _warpPastProposalEnd(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            4,
            "incorrect state, not succeeded"
        );

        assertEq(
            governor.currentUserLiveProposals(address(this)),
            4,
            "incorrect num live proposals"
        );
        assertEq(governor.liveProposals().length, 4);

        // execute
        governor.execute(proposalId);
        assertEq(
            uint256(governor.state(proposalId)),
            5,
            "incorrect state, not executed"
        );

        assertEq(
            governor.currentUserLiveProposals(address(this)),
            4,
            "incorrect num live proposals"
        );
        assertEq(governor.liveProposals().length, 4);

        _assertGovernanceBalance();
    }

    function testMultipleUsersCanCreateAsManyProposalWantsAsLongNeverExceedsMaxUserLiveProposals()
        public
    {
        address user1 = address(1);
        address user2 = address(2);
        address user3 = address(3);
        address user4 = address(4);

        uint256 amount = governor.proposalThreshold();
        uint256 bridgeCost = governor.bridgeCostAll();

        _delegateVoteAmountForUser(address(well), user1, amount);
        vm.deal(user1, bridgeCost);

        _delegateVoteAmountForUser(address(stkWellMoonbeam), user2, amount);
        vm.deal(user2, bridgeCost);

        _delegateVoteAmountForUser(address(xwell), user3, amount);
        vm.deal(user3, bridgeCost);

        _delegateVoteAmountForUser(address(distributor), user4, amount);
        vm.deal(user4, bridgeCost);

        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        vm.startPrank(user1);
        for (uint256 i = 0; i < 5; i++) {
            _createProposalUpdateThreshold(user1);
            vm.warp(block.timestamp + 1);
        }
        vm.stopPrank();
        assertEq(
            governor.currentUserLiveProposals(user1),
            5,
            "incorrect num live proposals"
        );
        assertEq(
            governor.liveProposals().length,
            5,
            "incorrect num live proposals"
        );

        vm.startPrank(user2);
        for (uint256 i = 0; i < 5; i++) {
            _createProposalUpdateThreshold(user2);
            vm.warp(block.timestamp + 1);
        }
        vm.stopPrank();
        assertEq(
            governor.currentUserLiveProposals(user2),
            5,
            "incorrect num live proposals"
        );
        assertEq(
            governor.liveProposals().length,
            10,
            "incorrect num live proposals"
        );

        vm.startPrank(user3);
        for (uint256 i = 0; i < 5; i++) {
            _createProposalUpdateThreshold(user3);
            vm.warp(block.timestamp + 1);
        }
        vm.stopPrank();
        assertEq(
            governor.currentUserLiveProposals(user3),
            5,
            "incorrect num live proposals"
        );
        assertEq(
            governor.liveProposals().length,
            15,
            "incorrect num live proposals"
        );

        vm.startPrank(user4);
        for (uint256 i = 0; i < 5; i++) {
            _createProposalUpdateThreshold(user4);
            vm.warp(block.timestamp + 1);
        }
        vm.stopPrank();
        assertEq(
            governor.currentUserLiveProposals(user4),
            5,
            "incorrect num live proposals"
        );
        assertEq(
            governor.liveProposals().length,
            20,
            "incorrect num live proposals"
        );

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Mock Proposal MIP-M00";

        // no user can create more proposals
        vm.expectRevert(
            "MultichainGovernor: too many live proposals for this user"
        );
        vm.prank(user1);
        governor.propose(targets, values, calldatas, description);

        vm.expectRevert(
            "MultichainGovernor: too many live proposals for this user"
        );
        vm.prank(user2);
        governor.propose(targets, values, calldatas, description);

        vm.expectRevert(
            "MultichainGovernor: too many live proposals for this user"
        );
        vm.prank(user3);
        governor.propose(targets, values, calldatas, description);

        vm.expectRevert(
            "MultichainGovernor: too many live proposals for this user"
        );
        vm.prank(user4);
        governor.propose(targets, values, calldatas, description);

        // cancel proposal 1, 6, 11, 16
        // 17 live proposals
        vm.prank(user1);
        governor.cancel(1);

        assertEq(
            governor.currentUserLiveProposals(user1),
            4,
            "incorrect num live proposals"
        );
        assertEq(
            governor.liveProposals().length,
            19,
            "incorrect num live proposals"
        );

        vm.prank(user2);
        governor.cancel(6);

        assertEq(
            governor.currentUserLiveProposals(user2),
            4,
            "incorrect num live proposals"
        );
        assertEq(
            governor.liveProposals().length,
            18,
            "incorrect num live proposals"
        );

        vm.prank(user3);
        governor.cancel(11);
        assertEq(
            governor.currentUserLiveProposals(user3),
            4,
            "incorrect num live proposals"
        );
        assertEq(
            governor.liveProposals().length,
            17,
            "incorrect num live proposals"
        );

        vm.prank(user4);
        governor.cancel(16);
        assertEq(
            governor.currentUserLiveProposals(user4),
            4,
            "incorrect num live proposals"
        );
        assertEq(
            governor.liveProposals().length,
            16,
            "incorrect num live proposals"
        );

        //  pass proposal 2, 7
        _castVotes(2, Constants.VOTE_VALUE_YES, address(this));

        // user 1 has 4 live proposals
        assertEq(
            governor.currentUserLiveProposals(user1),
            4,
            "incorrect num live proposals"
        );
        assertEq(
            governor.liveProposals().length,
            16,
            "incorrect num live proposals"
        );

        _castVotes(7, Constants.VOTE_VALUE_NO, address(this));

        _warpPastProposalEnd(7);

        // user 1 has 0 live proposals
        assertEq(
            governor.currentUserLiveProposals(user1),
            0,
            "incorrect num live proposals"
        );

        // user 2 has 3 live proposals
        assertEq(
            governor.currentUserLiveProposals(user2),
            3,
            "incorrect num live proposals"
        );

        assertEq(
            governor.liveProposals().length,
            11,
            "incorrect num live proposals"
        );

        _assertGovernanceBalance();
    }
}
