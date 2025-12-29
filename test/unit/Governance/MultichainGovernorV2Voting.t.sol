pragma solidity 0.8.19;

import {stdError} from "@forge-std/StdError.sol";
import "@forge-std/Test.sol";

import "@protocol/utils/ChainIds.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {MockWeth} from "@test/mock/MockWeth.sol";
import {Constants} from "@protocol/governance/multichain/Constants.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {SnapshotInterface} from "@protocol/governance/multichain/SnapshotInterface.sol";
import {MultichainBaseTestV2} from "@test/helper/MultichainBaseTestV2.t.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {MultichainVoteCollection} from "@protocol/governance/multichain/MultichainVoteCollection.sol";
import {MultichainGovernorDeploy} from "@script/DeployMultichainGovernor.s.sol";
import {IMultichainGovernorV2, MultichainGovernorV2} from "@protocol/governance/multichain/MultichainGovernorV2.sol";
import {BASE_WORMHOLE_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID} from "@utils/ChainIds.sol";

contract MultichainGovernorV2VotingUnitTest is MultichainBaseTestV2 {
    bool private _receivingFunds;

    string constant DESCRIPTION_URI = "ipfs://proposal123";
    uint256 constant EXECUTION_WINDOW = 7 days;
    uint256 constant MAX_USER_PROPOSAL_COUNT = 2;

    event ProposalCanceled(uint256 proposalId);
    event ProposalRebroadcasted(uint256 proposalId, bytes data);

    event ProposalCreated(
        uint256 id,
        address proposer,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        uint256 votingStartTime,
        uint256 votingEndTime,
        string descriptionUri
    );

    event ProposalInitialized(
        address proposer,
        uint256 proposalId,
        string descriptionUri
    );

    function setUp() public override {
        super.setUp();

        xwell.delegate(address(this));
        well.delegate(address(this));
        distributor.delegate(address(this));

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        _receivingFunds = false;
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

    function _warpPastProposalEnd(uint256) private {
        // Calculate crossChainVoteCollectionEndTimestamp
        // It's votingPeriod + crossChainVoteCollectionPeriod after current timestamp
        uint256 endTimestamp = block.timestamp +
            governor.votingPeriod() +
            governor.crossChainVoteCollectionPeriod();
        vm.warp(endTimestamp + 1);
    }

    function _getProposalTimestamp(uint256) private view returns (uint256) {
        // Calculate crossChainVoteCollectionEndTimestamp
        return
            block.timestamp +
            governor.votingPeriod() +
            governor.crossChainVoteCollectionPeriod();
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

    /// ========================================================================
    /// Proposal Data Helper Functions
    /// ========================================================================

    /// @notice Returns standard proposal data for updating proposal threshold
    function _getUpdateProposalThresholdData()
        private
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        )
    {
        targets = new address[](1);
        targets[0] = address(governor);

        values = new uint256[](1);
        values[0] = 0;

        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "updateProposalThreshold(uint256)",
            100_000_000 * 1e18
        );
    }

    /// @notice Returns standard proposal data for updating quorum
    function _getUpdateQuorumData()
        private
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        )
    {
        targets = new address[](1);
        targets[0] = address(governor);

        values = new uint256[](1);
        values[0] = 0;

        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "updateQuorum(uint256)",
            500_000_000 * 1e18
        );
    }

    /// @notice Returns dual-action proposal data (threshold + quorum update)
    function _getDualActionProposalData()
        private
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        )
    {
        targets = new address[](2);
        targets[0] = address(governor);
        targets[1] = address(governor);

        values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        calldatas = new bytes[](2);
        calldatas[0] = abi.encodeWithSignature(
            "updateProposalThreshold(uint256)",
            100_000_000 * 1e18
        );
        calldatas[1] = abi.encodeWithSignature(
            "updateQuorum(uint256)",
            2_000_000 * 1e18
        );
    }

    /// @notice Returns empty arrays for testing
    function _getEmptyProposalData()
        private
        pure
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        )
    {
        targets = new address[](0);
        values = new uint256[](0);
        calldatas = new bytes[](0);
    }

    /// @notice Returns mismatched arrays for arity testing
    function _getArityMismatchData()
        private
        pure
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        )
    {
        targets = new address[](1);
        values = new uint256[](0);
        calldatas = new bytes[](0);
    }

    function testSetup() public view {
        assertEq(
            votingPowerAggregator.getVotes(
                address(this),
                block.timestamp - 1,
                block.number - 1
            ),
            14_000_000_000 * 1e18,
            "incorrect vote amount"
        );

        assertEq(
            address(governor.votingPower()),
            address(votingPowerAggregator),
            "incorrect voting power aggregator"
        );

        assertEq(
            address(governor.wormholeRelayer()),
            address(wormholeRelayerAdapter),
            "incorrect wormhole relayer"
        );
        assertTrue(
            governor.isTrustedSender(
                BASE_WORMHOLE_CHAIN_ID,
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

    /// ========================================================================
    /// Proposal Creation Tests
    /// ========================================================================

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

        _assertGovernanceBalance();

        return proposalId;
    }

    function testProposeInsufficientProposalThresholdFails() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = _getEmptyProposalData();

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
            IMultichainGovernorV2.VotesBelowProposalThreshold.selector
        );
        governor.propose(targets, values, calldatas, DESCRIPTION_URI, true);

        _assertGovernanceBalance();
    }

    function testProposeExcessiveValueFails() public {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);

        values[0] = type(uint256).max;
        values[1] = 1;

        vm.expectRevert(stdError.arithmeticError);
        governor.propose(targets, values, calldatas, DESCRIPTION_URI, true);

        _assertGovernanceBalance();
    }

    function testProposeArityMismatchFails() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = _getArityMismatchData();

        /// branch 1
        vm.expectRevert(IMultichainGovernorV2.ArityMismatch.selector);
        governor.propose(targets, values, calldatas, DESCRIPTION_URI, true);

        /// branch 2
        values = new uint256[](1);

        vm.expectRevert(IMultichainGovernorV2.ArityMismatch.selector);
        governor.propose(targets, values, calldatas, DESCRIPTION_URI, true);

        _assertGovernanceBalance();
    }

    function testProposeNoActionsFails() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = _getEmptyProposalData();

        vm.expectRevert(IMultichainGovernorV2.EmptyArray.selector);
        governor.propose(targets, values, calldatas, DESCRIPTION_URI, true);

        _assertGovernanceBalance();
    }

    function testProposeNoDescriptionFails() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = _getUpdateProposalThresholdData();

        vm.expectRevert(IMultichainGovernorV2.EmptyDescriptionUri.selector);
        governor.propose(targets, values, calldatas, "", true);

        _assertGovernanceBalance();
    }

    function testProposeOverMaxProposalCountFails() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = _getUpdateProposalThresholdData();

        for (uint256 i = 0; i < MAX_USER_PROPOSAL_COUNT; i++) {
            uint256 bridgeCostLoop = governor.bridgeCostAll();
            vm.deal(address(this), bridgeCostLoop);

            governor.propose{value: bridgeCostLoop}(
                targets,
                values,
                calldatas,
                string(abi.encodePacked(DESCRIPTION_URI, vm.toString(i))),
                true
            );
        }

        uint256 bridgeCostFinal = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCostFinal);

        vm.expectRevert(IMultichainGovernorV2.TooManyLiveProposals.selector);
        governor.propose{value: bridgeCostFinal}(
            targets,
            values,
            calldatas,
            string(abi.encodePacked(DESCRIPTION_URI, "final")),
            true
        );

        _assertGovernanceBalance();
    }

    /// ========================================================================
    /// V2-Specific: Multi-Step Proposal Tests
    /// ========================================================================

    function testProposeWithoutFinalize() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = _getUpdateProposalThresholdData();

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        vm.expectEmit(true, true, true, true, address(governor));
        emit ProposalInitialized(address(this), 1, DESCRIPTION_URI);

        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            DESCRIPTION_URI,
            false
        );

        assertEq(proposalId, 1, "incorrect proposal id");

        // Verify proposal is not active yet (not finalized)
        assertFalse(
            governor.proposalActive(proposalId),
            "proposal should not be active"
        );

        // Check proposal data was stored
        (address[] memory storedTargets, , ) = governor.getProposalData(
            proposalId
        );
        assertEq(storedTargets.length, 1, "targets not stored");
    }

    function testProposeAppendToExistingProposal() public {
        // Create initial proposal without finalizing
        (
            address[] memory targets1,
            uint256[] memory values1,
            bytes[] memory calldatas1
        ) = _getUpdateProposalThresholdData();

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets1,
            values1,
            calldatas1,
            DESCRIPTION_URI,
            false
        );

        // Append more targets to the proposal
        (
            address[] memory targets2,
            uint256[] memory values2,
            bytes[] memory calldatas2
        ) = _getUpdateQuorumData();

        governor.propose(
            proposalId,
            targets2,
            values2,
            calldatas2,
            false // Still not finalizing
        );

        (address[] memory storedTargets, , ) = governor.getProposalData(
            proposalId
        );
        assertEq(storedTargets.length, 2, "targets not appended");
        assertFalse(
            governor.proposalActive(proposalId),
            "proposal should not be finalized yet"
        );
    }

    function testProposeAppendAndFinalize() public {
        // Create initial proposal without finalizing
        (
            address[] memory targets1,
            uint256[] memory values1,
            bytes[] memory calldatas1
        ) = _getUpdateProposalThresholdData();

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets1,
            values1,
            calldatas1,
            DESCRIPTION_URI,
            false
        );

        // Append and finalize
        (
            address[] memory targets2,
            uint256[] memory values2,
            bytes[] memory calldatas2
        ) = _getUpdateQuorumData();

        vm.deal(address(this), bridgeCost);

        governor.propose{value: bridgeCost}(
            proposalId,
            targets2,
            values2,
            calldatas2,
            true
        );

        (address[] memory storedTargets, , ) = governor.getProposalData(
            proposalId
        );
        assertEq(storedTargets.length, 2, "targets not appended");
        assertTrue(
            governor.proposalActive(proposalId),
            "proposal should be active"
        );
    }

    function testProposeAppendToFinalizedProposalFails() public {
        uint256 proposalId = testProposeUpdateProposalThresholdSucceeds();

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = _getUpdateQuorumData();

        vm.expectRevert(
            IMultichainGovernorV2.ProposalAlreadyFinalized.selector
        );
        governor.propose(proposalId, targets, values, calldatas, false);
    }

    function testProposeAppendByNonProposerFails() public {
        // Create initial proposal without finalizing
        (
            address[] memory targets1,
            uint256[] memory values1,
            bytes[] memory calldatas1
        ) = _getUpdateProposalThresholdData();

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets1,
            values1,
            calldatas1,
            DESCRIPTION_URI,
            false
        );

        // Try to append from different address
        (
            address[] memory targets2,
            uint256[] memory values2,
            bytes[] memory calldatas2
        ) = _getUpdateQuorumData();

        vm.prank(address(0x123));
        vm.expectRevert(IMultichainGovernorV2.OnlyProposer.selector);
        governor.propose(proposalId, targets2, values2, calldatas2, false);
    }

    /// ========================================================================
    /// Voting Tests
    /// ========================================================================

    function testVotingValidProposalIdSucceeds() public returns (uint256) {
        address user1 = address(0x1);
        uint256 voteAmount = 1_000_000 * 1e18;

        // Give user voting power BEFORE creating the proposal
        _delegateVoteAmountForUser(address(well), user1, voteAmount);

        uint256 proposalId = _createProposal();

        _castVotes(proposalId, Constants.VOTE_VALUE_YES, user1);

        (bool hasVoted, uint8 voteValue, uint256 votes) = governor.getReceipt(
            proposalId,
            user1
        );

        assertTrue(hasVoted, "user should have voted");
        assertEq(voteValue, Constants.VOTE_VALUE_YES, "incorrect vote value");
        assertEq(votes, voteAmount, "incorrect vote amount");

        (
            uint256 totalVotes,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 abstainVotes
        ) = governor.proposalVotes(proposalId);

        assertEq(totalVotes, voteAmount, "incorrect total votes");
        assertEq(forVotes, voteAmount, "incorrect for votes");
        assertEq(againstVotes, 0, "incorrect against votes");
        assertEq(abstainVotes, 0, "incorrect abstain votes");

        return proposalId;
    }

    function testVotingTwiceSameProposalFails() public {
        uint256 proposalId = _createProposal();

        vm.prank(address(this));
        governor.castVote(proposalId, Constants.VOTE_VALUE_YES);

        vm.expectRevert(IMultichainGovernorV2.AlreadyVoted.selector);
        vm.prank(address(this));
        governor.castVote(proposalId, Constants.VOTE_VALUE_YES);
    }

    function testVotingInvalidVoteValueFails() public {
        uint256 proposalId = _createProposal();

        vm.expectRevert(IMultichainGovernorV2.InvalidVoteValue.selector);
        vm.prank(address(this));
        governor.castVote(proposalId, 3); // Max is 2 (abstain)
    }

    function testVotingNoVotesFails() public returns (uint256 proposalId) {
        proposalId = _createProposal();

        address user = address(0x1);

        vm.expectRevert(IMultichainGovernorV2.NoVotingPower.selector);
        vm.prank(user);
        governor.castVote(proposalId, Constants.VOTE_VALUE_YES);
    }

    function testVotingXChainVoteCollectionPeriodFails() public {
        uint256 proposalId = _createProposal();

        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMultichainGovernorV2.InvalidProposalState.selector,
                IMultichainGovernorV2.ProposalState.CrossChainVoteCollection,
                IMultichainGovernorV2.ProposalState.Active
            )
        );
        vm.prank(address(this));
        governor.castVote(proposalId, Constants.VOTE_VALUE_YES);
    }

    /// ========================================================================
    /// V2-Specific: Execution Window Tests
    /// ========================================================================

    function testExecuteSucceedsWithinWindow() public {
        uint256 proposalId = testVotingValidProposalIdSucceeds();

        _warpPastProposalEnd(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IMultichainGovernorV2.ProposalState.Succeeded),
            "proposal should be succeeded"
        );

        // Execute within window
        governor.execute(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IMultichainGovernorV2.ProposalState.Executed),
            "proposal should be executed"
        );
    }

    function testExecuteFailsAfterWindowExpires() public {
        uint256 proposalId = testVotingValidProposalIdSucceeds();

        _warpPastProposalEnd(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IMultichainGovernorV2.ProposalState.Succeeded),
            "proposal should be succeeded"
        );

        // Warp past execution window
        vm.warp(block.timestamp + EXECUTION_WINDOW + 1);

        vm.expectRevert(IMultichainGovernorV2.ProposalExpired.selector);
        governor.execute(proposalId);
    }

    function testExecuteFailsExactlyAtWindowBoundary() public {
        uint256 proposalId = testVotingValidProposalIdSucceeds();

        _warpPastProposalEnd(proposalId);

        // Warp to exactly at the boundary (should still fail)
        uint256 endTimestamp = _getProposalTimestamp(proposalId);
        vm.warp(endTimestamp + EXECUTION_WINDOW + 1);

        vm.expectRevert(IMultichainGovernorV2.ProposalExpired.selector);
        governor.execute(proposalId);
    }

    /// ========================================================================
    /// Proposal State Transition Tests
    /// ========================================================================

    function testStateMovesToExecutedStateAfterExecution() public {
        uint256 proposalId = testVotingValidProposalIdSucceeds();

        _warpPastProposalEnd(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IMultichainGovernorV2.ProposalState.Succeeded),
            "proposal should be succeeded before execution"
        );

        governor.execute(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IMultichainGovernorV2.ProposalState.Executed),
            "proposal should be executed"
        );
    }

    function testExecuteFailsAfterExecution() public {
        uint256 proposalId = testVotingValidProposalIdSucceeds();

        _warpPastProposalEnd(proposalId);
        governor.execute(proposalId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMultichainGovernorV2.InvalidProposalState.selector,
                IMultichainGovernorV2.ProposalState.Executed,
                IMultichainGovernorV2.ProposalState.Succeeded
            )
        );
        governor.execute(proposalId);
    }

    function testExecuteFailsAfterCancel() public {
        uint256 proposalId = _createProposal();

        governor.cancel(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IMultichainGovernorV2.ProposalState.Canceled),
            "proposal should be canceled"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IMultichainGovernorV2.InvalidProposalState.selector,
                IMultichainGovernorV2.ProposalState.Canceled,
                IMultichainGovernorV2.ProposalState.Succeeded
            )
        );
        governor.execute(proposalId);
    }

    /// ========================================================================
    /// Proposal Cancellation Tests
    /// ========================================================================

    function testCancelProposalSucceeded() public {
        uint256 proposalId = _createProposal();

        assertTrue(
            governor.proposalActive(proposalId),
            "proposal should be active"
        );

        vm.expectEmit(true, true, true, true, address(governor));
        emit ProposalCanceled(proposalId);

        governor.cancel(proposalId);

        assertFalse(
            governor.proposalActive(proposalId),
            "proposal should not be active"
        );

        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IMultichainGovernorV2.ProposalState.Canceled),
            "proposal should be canceled"
        );
    }

    function testCancelIfProposerVotesBelowThresholdSucceeded() public {
        uint256 proposalId = _createProposal();

        // Transfer away ALL voting power to drop below proposal threshold
        well.transfer(address(0xdead), well.balanceOf(address(this)));
        distributor.transfer(
            address(0xdead),
            distributor.balanceOf(address(this))
        );

        // Unstake from stkWellMoonbeam to remove staked voting power
        // This will return xWELL to us
        uint256 stakedBalance = stkWellMoonbeam.balanceOf(address(this));
        stkWellMoonbeam.cooldown();
        vm.warp(block.timestamp + stkWellMoonbeam.COOLDOWN_SECONDS() + 1);
        stkWellMoonbeam.redeem(address(this), stakedBalance);

        // Now transfer away all xWELL (including what we had before and what we got from unstaking)
        xwell.transfer(address(0xdead), xwell.balanceOf(address(this)));

        vm.roll(block.number + 1);

        // Anyone can cancel if proposer votes dropped below threshold
        vm.prank(address(0x123));
        governor.cancel(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IMultichainGovernorV2.ProposalState.Canceled),
            "proposal should be canceled"
        );
    }

    function testCancelFailsIfSenderIsNotProposerNeitherProposerVotesBelowThreshold()
        public
    {
        uint256 proposalId = _createProposal();

        vm.expectRevert(IMultichainGovernorV2.UnauthorizedCancel.selector);
        vm.prank(address(0x123));
        governor.cancel(proposalId);
    }

    function testCancelFailsIfProposalIsAlreadyCanceled() public {
        uint256 proposalId = _createProposal();

        governor.cancel(proposalId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMultichainGovernorV2.InvalidProposalState.selector,
                IMultichainGovernorV2.ProposalState.Canceled,
                IMultichainGovernorV2.ProposalState.Active
            )
        );
        governor.cancel(proposalId);
    }

    function testCancelSucceedsWhenProposerVotesEqualThreshold() public {
        // Setup: Create a user with exactly proposalThreshold voting power
        address proposer = address(0x456);
        uint256 threshold = governor.proposalThreshold();

        // Give proposer exactly threshold voting power
        deal(address(well), proposer, threshold);
        vm.prank(proposer);
        well.delegate(proposer);

        vm.roll(block.number + 1);

        // Verify proposer has exactly threshold voting power
        assertEq(
            votingPowerAggregator.getCurrentVotes(proposer),
            threshold,
            "proposer should have exactly threshold votes"
        );

        // Proposer creates proposal (should succeed since votes >= threshold)
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = _getUpdateProposalThresholdData();

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(proposer, bridgeCost);

        vm.prank(proposer);
        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            DESCRIPTION_URI,
            true
        );

        assertTrue(
            governor.proposalActive(proposalId),
            "proposal should be active"
        );

        // Another user can cancel since proposer votes equal to threshold (rather than > threshold)
        vm.prank(address(0x789));
        governor.cancel(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IMultichainGovernorV2.ProposalState.Canceled),
            "proposal should be canceled"
        );
    }

    /// ========================================================================
    /// View Function Tests
    /// ========================================================================

    function testGetProposalData() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = _getDualActionProposalData();

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            DESCRIPTION_URI,
            true
        );

        (
            address[] memory returnedTargets,
            uint256[] memory returnedValues,
            bytes[] memory returnedCalldatas
        ) = governor.getProposalData(proposalId);

        assertEq(returnedTargets.length, 2, "incorrect targets length");
        assertEq(returnedValues.length, 2, "incorrect values length");
        assertEq(returnedCalldatas.length, 2, "incorrect calldatas length");

        assertEq(returnedTargets[0], targets[0], "incorrect target 0");
        assertEq(returnedTargets[1], targets[1], "incorrect target 1");
        assertEq(returnedValues[0], values[0], "incorrect value 0");
        assertEq(returnedValues[1], values[1], "incorrect value 1");
        assertEq(returnedCalldatas[0], calldatas[0], "incorrect calldata 0");
        assertEq(returnedCalldatas[1], calldatas[1], "incorrect calldata 1");
    }

    function testGetNumLiveProposals() public {
        assertEq(governor.getNumLiveProposals(), 0, "should start with 0");

        _createProposal();
        assertEq(
            governor.getNumLiveProposals(),
            1,
            "should have 1 after creation"
        );

        _createProposal();
        assertEq(
            governor.getNumLiveProposals(),
            2,
            "should have 2 after second"
        );
    }

    function testLiveProposals() public {
        uint256 proposalId1 = _createProposal();
        uint256 proposalId2 = _createProposal();

        uint256[] memory liveProposals = governor.liveProposals();

        assertEq(liveProposals.length, 2, "should have 2 live proposals");
        assertEq(liveProposals[0], proposalId1, "first proposal id incorrect");
        assertEq(liveProposals[1], proposalId2, "second proposal id incorrect");
    }

    function testStateInvalidProposalId() public {
        vm.expectRevert(IMultichainGovernorV2.InvalidProposalId.selector);
        governor.state(999);
    }

    /// ========================================================================
    /// V2-Specific: VotingPowerAggregator Integration Tests
    /// ========================================================================

    function testVotingPowerFromMultipleSources() public {
        address user = address(0x1);
        uint256 wellAmount = 100_000 * 1e18;
        uint256 distributorAmount = 50_000 * 1e18;
        uint256 xwellAmount = 25_000 * 1e18;

        // Give user voting power from multiple sources
        well.transfer(user, wellAmount);
        vm.prank(user);
        well.delegate(user);

        distributor.transfer(user, distributorAmount);
        vm.prank(user);
        distributor.delegate(user);

        xwell.transfer(user, xwellAmount);
        vm.prank(user);
        xwell.delegate(user);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        // Check aggregated voting power
        uint256 totalVotingPower = votingPowerAggregator.getVotes(
            user,
            block.timestamp - 1,
            block.number - 1
        );

        assertEq(
            totalVotingPower,
            wellAmount + distributorAmount + xwellAmount,
            "voting power should be aggregated"
        );
    }

    function testAddSnapshotSourceAsOwner() public {
        address newSource = address(0x999);

        votingPowerAggregator.addSnapshotSource(newSource);

        assertTrue(
            votingPowerAggregator.isSnapshotSource(newSource),
            "source should be added"
        );
    }

    function testRemoveSnapshotSourceAsOwner() public {
        // Remove distributor
        votingPowerAggregator.removeSnapshotSource(address(distributor));

        assertFalse(
            votingPowerAggregator.isSnapshotSource(address(distributor)),
            "source should be removed"
        );
    }

    function testAddSnapshotSourceNonOwnerFails() public {
        address newSource = address(0x999);

        vm.prank(address(0x123));
        vm.expectRevert("Ownable: caller is not the owner");
        votingPowerAggregator.addSnapshotSource(newSource);
    }

    /// ========================================================================
    /// Complex Scenario Tests
    /// ========================================================================

    function testChangingQuorumWithTwoLiveProposals() public {
        uint256 proposalId1 = _createProposal();

        // Create second proposal to change quorum
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = _getUpdateQuorumData();

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        uint256 proposalId2 = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            DESCRIPTION_URI,
            true
        );

        // Vote on second proposal (the one that updates quorum) to make it succeed
        vm.prank(address(this));
        governor.castVote(proposalId2, Constants.VOTE_VALUE_YES);

        _warpPastProposalEnd(proposalId2);
        governor.execute(proposalId2);

        // Verify quorum changed
        assertEq(governor.quorum(), 500_000_000 * 1e18, "quorum not updated");

        // First proposal will have expired since we warped past its end time too
        // The important thing is that the quorum was successfully updated
        assertEq(
            uint256(governor.state(proposalId1)),
            uint256(IMultichainGovernorV2.ProposalState.Defeated),
            "first proposal should be defeated (expired without votes)"
        );
    }

    function testPausingWithThreeLiveProposals() public {
        // Create first proposal from address(this)
        uint256 proposalId1 = _createProposal();

        // Create second proposal from address(this) (MAX_USER_PROPOSAL_COUNT is 2)
        uint256 proposalId2 = _createProposal();

        // Need a different user for third proposal to avoid TooManyLiveProposals
        address user2 = address(0x2);
        // Transfer proposal threshold amount (not just quorum) to allow user2 to propose
        uint256 voteAmount = governor.proposalThreshold();
        well.transfer(user2, voteAmount);
        vm.prank(user2);
        well.delegate(user2);
        vm.roll(block.number + 1);

        uint256 proposalId3 = _createProposalUpdateThreshold(user2);

        assertTrue(
            governor.proposalActive(proposalId1),
            "proposal 1 should be active"
        );
        assertTrue(
            governor.proposalActive(proposalId2),
            "proposal 2 should be active"
        );
        assertTrue(
            governor.proposalActive(proposalId3),
            "proposal 3 should be active"
        );

        // Pause governor
        vm.prank(governor.pauseGuardian());
        governor.pause();

        // All proposals should be canceled
        assertFalse(
            governor.proposalActive(proposalId1),
            "proposal 1 should be canceled"
        );
        assertFalse(
            governor.proposalActive(proposalId2),
            "proposal 2 should be canceled"
        );
        assertFalse(
            governor.proposalActive(proposalId3),
            "proposal 3 should be canceled"
        );

        assertEq(
            uint256(governor.state(proposalId1)),
            uint256(IMultichainGovernorV2.ProposalState.Canceled),
            "proposal 1 should be canceled"
        );
    }

    receive() external payable {
        if (!_receivingFunds) {
            revert("not receiving funds");
        }
    }
}
