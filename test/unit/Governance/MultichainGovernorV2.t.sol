pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import "@utils/ChainIds.sol";

import {IMultichainGovernorV2, MultichainGovernorV2} from "@protocol/governance/multichain/MultichainGovernorV2.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Constants} from "@protocol/governance/multichain/Constants.sol";
import {ConfigurablePauseGuardian} from "@protocol/xWELL/ConfigurablePauseGuardian.sol";
import {MultichainBaseTestV2} from "@test/helper/MultichainBaseTestV2.t.sol";
import {WormholeBridgeBase} from "@protocol/wormhole/WormholeBridgeBase.sol";

contract MockTimelock {
    function transferOwnership(address) external pure returns (bool) {
        return true;
    }
}

contract MultichainGovernorV2UnitTest is MultichainBaseTestV2 {
    event BreakGlassGuardianChanged(address oldValue, address newValue);
    event PauseGuardianUpdated(
        address indexed oldPauseGuardian,
        address indexed newPauseGuardian
    );

    function setUp() public override {
        super.setUp();

        xwell.delegate(address(this));
        well.delegate(address(this));
        distributor.delegate(address(this));

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }

    function testGovernorSetup() public view {
        assertEq(
            governor.gasLimit(),
            Constants.MIN_GAS_LIMIT,
            "incorrect gas limit vote collection"
        );
        assertEq(governor.proposalCount(), 0, "proposalCount");
        assertEq(
            governor.breakGlassGuardian(),
            breakGlassGuardian,
            "breakGlassGuardian"
        );
        assertEq(
            governor.proposalThreshold(),
            proposalThreshold,
            "proposalThreshold"
        );
        assertEq(
            governor.votingPeriod(),
            votingPeriodSeconds,
            "votingPeriodSeconds"
        );

        assertEq(
            governor.crossChainVoteCollectionPeriod(),
            crossChainVoteCollectionPeriod,
            "crossChainVoteCollectionPeriod"
        );
        assertEq(governor.quorum(), quorum, "quorum");
        assertEq(governor.pauseStartTime(), 0, "pauseStartTime");
        assertEq(governor.pauseDuration(), pauseDuration, "pauseDuration");
        assertEq(governor.pauseGuardian(), pauseGuardian, "pauseGuardian");
        assertFalse(governor.paused(), "paused");
        assertFalse(governor.pauseUsed(), "paused used");

        // V2: votingPower reference instead of individual tokens
        assertEq(
            address(governor.votingPower()),
            address(votingPowerAggregator),
            "votingPower"
        );

        assertEq(
            address(governor.targetAddress(BASE_WORMHOLE_CHAIN_ID)),
            address(voteCollection),
            "target address on base incorrect"
        );

        assertEq(
            governor.getAllTargetChains().length,
            1,
            "getAllTargetChains length incorrect"
        );
        assertEq(
            governor.getAllTargetChains()[0],
            BASE_WORMHOLE_CHAIN_ID,
            "getAllTargetChains chainid incorrect"
        );
        assertEq(
            governor.bridgeCost(MOONBASE_WORMHOLE_CHAIN_ID),
            0.1 ether,
            "bridgecost incorrect"
        );
        assertEq(
            governor.bridgeCostAll(),
            0.1 ether,
            "bridgecostall incorrect"
        );
    }

    function testVoteCollectionSetup() public view {
        // V2: votingPower aggregator instead of direct xWell reference
        // Vote collection has its own separate VotingPowerAggregator instance
        assertTrue(
            address(voteCollection.votingPower()) != address(0),
            "votingPower aggregator should not be zero"
        );
        assertTrue(
            address(voteCollection.votingPower()) !=
                address(votingPowerAggregator),
            "vote collection should have separate voting power aggregator from governor"
        );
        assertTrue(
            voteCollection.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                address(governor)
            ),
            "governor address not trusted sender"
        );
        assertEq(
            address(voteCollection.wormholeRelayer()),
            address(wormholeRelayerAdapter),
            "relayer address"
        );
    }

    function testVotingPowerAggregatorSetup() public view {
        assertEq(
            address(votingPowerAggregator.xWell()),
            address(xwell),
            "xWell address"
        );
        // NOTE: well and distributor removed as voting sources per governance changes
        // Most users have migrated to xWell, and distributor tokens have mostly vested
        assertTrue(
            votingPowerAggregator.isSnapshotSource(address(stkWellMoonbeam)),
            "stkWellMoonbeam not in snapshot sources"
        );
    }

    function testInitLogicFails() public {
        MultichainGovernorV2.InitializeData memory initData;
        WormholeTrustedSender.TrustedSender[]
            memory trustedSenders = new WormholeTrustedSender.TrustedSender[](
                0
            );

        vm.expectRevert("Initializable: contract is already initialized");

        MultichainGovernorV2(payable(governorLogic)).initialize(
            initData,
            trustedSenders,
            new bytes[](0)
        );
    }

    function testDeployxWell() public {
        MintLimits.RateLimitMidPointInfo[]
            memory newRateLimits = new MintLimits.RateLimitMidPointInfo[](0);

        (, address xwellProxy, ) = deployXWell(
            "XWell",
            "XWELL",
            address(this), //owner
            newRateLimits,
            pauseDuration,
            pauseGuardian
        );

        xwell = xWELL(xwellProxy);
    }

    /// ACL Negative Tests

    /// GOVERNOR

    function testUpdateApprovedCalldataNonGovernorFails() public {
        vm.expectRevert(IMultichainGovernorV2.OnlyGovernor.selector);
        governor.updateApprovedCalldata("", true);
    }

    function testUpdateApprovedCalldataAlreadyWhitelistedFails() public {
        testUpdateApprovedCalldataGovernorSucceeds();
        vm.prank(address(governor));
        vm.expectRevert(IMultichainGovernorV2.CalldataAlreadyApproved.selector);
        governor.updateApprovedCalldata("", true);
    }

    function testRemoveNonApprovedCalldataWhitelistedFails() public {
        testUpdateApprovedCalldataGovernorSucceeds();
        vm.prank(address(governor));
        vm.expectRevert(IMultichainGovernorV2.CalldataNotApproved.selector);
        governor.updateApprovedCalldata(hex"00eeff", false);
    }

    function testUpdateApprovedCalldataNonWhitelistedFails() public {
        vm.prank(address(governor));
        vm.expectRevert(IMultichainGovernorV2.CalldataNotApproved.selector);
        governor.updateApprovedCalldata("", false);
    }

    function testremoveExternalChainConfigsNonGovernorFails() public {
        WormholeTrustedSender.TrustedSender[]
            memory _trustedSenders = new WormholeTrustedSender.TrustedSender[](
                0
            );
        vm.expectRevert(IMultichainGovernorV2.OnlyGovernor.selector);
        governor.removeExternalChainConfigs(_trustedSenders);
    }

    function testAddExternalChainConfigsNonGovernorFails() public {
        WormholeTrustedSender.TrustedSender[]
            memory _trustedSenders = new WormholeTrustedSender.TrustedSender[](
                0
            );
        vm.expectRevert(IMultichainGovernorV2.OnlyGovernor.selector);
        governor.addExternalChainConfigs(_trustedSenders);
    }

    function testAddExternalChainConfigsAddressZeroFails() public {
        WormholeTrustedSender.TrustedSender[]
            memory _trustedSenders = new WormholeTrustedSender.TrustedSender[](
                1
            );
        _trustedSenders[0].chainId = 1;
        _trustedSenders[0].addr = address(0);

        vm.expectRevert(WormholeBridgeBase.InvalidAddress.selector);
        vm.prank(address(governor));
        governor.addExternalChainConfigs(_trustedSenders);
    }

    function testUpdateProposalThresholdNonGovernorFails() public {
        vm.expectRevert(IMultichainGovernorV2.OnlyGovernor.selector);
        governor.updateProposalThreshold(1000);
    }

    function testUpdateProposalThresholdTooLowFails() public {
        vm.expectRevert(
            IMultichainGovernorV2.ProposalThresholdOutOfBounds.selector
        );
        vm.prank(address(governor));
        governor.updateProposalThreshold(Constants.MIN_PROPOSAL_THRESHOLD - 1);
    }

    function testUpdateProposalThresholdTooHighFails() public {
        vm.expectRevert(
            IMultichainGovernorV2.ProposalThresholdOutOfBounds.selector
        );
        vm.prank(address(governor));
        governor.updateProposalThreshold(Constants.MAX_PROPOSAL_THRESHOLD + 1);
    }

    // V2: maxUserLiveProposals is now a constant, so setter tests are removed

    function testUpdateQuorumNonGovernorFails() public {
        vm.expectRevert(IMultichainGovernorV2.OnlyGovernor.selector);
        governor.updateQuorum(1000);
    }

    function testUpdateQuorumTooHighFails() public {
        vm.expectRevert(IMultichainGovernorV2.InvalidQuorum.selector);
        vm.prank(address(governor));
        governor.updateQuorum(Constants.MAX_QUORUM + 1);
    }

    function testUpdateVotingPeriodNonGovernorFails() public {
        vm.expectRevert(IMultichainGovernorV2.OnlyGovernor.selector);
        governor.updateVotingPeriod(1000);
    }

    function testUpdateVotingPeriodTooLowFails() public {
        vm.expectRevert(IMultichainGovernorV2.VotingPeriodOutOfBounds.selector);
        vm.prank(address(governor));
        governor.updateVotingPeriod(Constants.MIN_VOTING_PERIOD - 1);
    }

    function testUpdateVotingPeriodTooHighFails() public {
        vm.expectRevert(IMultichainGovernorV2.VotingPeriodOutOfBounds.selector);
        vm.prank(address(governor));
        governor.updateVotingPeriod(Constants.MAX_VOTING_PERIOD + 1);
    }

    function testUpdateCrossChainVoteCollectionPeriodNonGovernorFails() public {
        vm.expectRevert(IMultichainGovernorV2.OnlyGovernor.selector);
        governor.updateCrossChainVoteCollectionPeriod(1000);
    }

    function testUpdateCrossChainVoteCollectionPeriodTooLowFails() public {
        vm.expectRevert(
            IMultichainGovernorV2.InvalidVoteCollectionPeriod.selector
        );
        vm.prank(address(governor));

        governor.updateCrossChainVoteCollectionPeriod(
            Constants.MIN_CROSS_CHAIN_VOTE_COLLECTION_PERIOD - 1
        );
    }

    function testUpdateCrossChainVoteCollectionPeriodTooHighFails() public {
        vm.expectRevert(
            IMultichainGovernorV2.InvalidVoteCollectionPeriod.selector
        );
        vm.prank(address(governor));

        governor.updateCrossChainVoteCollectionPeriod(
            Constants.MAX_CROSS_CHAIN_VOTE_COLLECTION_PERIOD + 1
        );
    }

    function testSetBreakGlassGuardianNonGovernorFails() public {
        vm.expectRevert(IMultichainGovernorV2.OnlyGovernor.selector);
        governor.setBreakGlassGuardian(address(this));
    }

    function testGrantPauseGuardianFails() public {
        vm.expectRevert(IMultichainGovernorV2.OnlyGovernor.selector);
        governor.grantPauseGuardian(address(this));
    }

    function testSetGasLimitNonGovernorFails() public {
        uint96 gasLimit = Constants.MIN_GAS_LIMIT;
        vm.prank(address(1));
        vm.expectRevert(IMultichainGovernorV2.OnlyGovernor.selector);
        governor.setGasLimit(gasLimit);
    }

    function testSetGasLimitTooLow() public {
        uint96 gasLimit = Constants.MIN_GAS_LIMIT - 1;
        vm.expectRevert(IMultichainGovernorV2.GasLimitTooLow.selector);
        vm.prank(address(governor));
        governor.setGasLimit(gasLimit);
    }

    /// BREAK GLASS GUARDIAN

    function testExecuteBreakGlassNonBreakGlassGuardianFails() public {
        vm.expectRevert(IMultichainGovernorV2.OnlyBreakGlassGuardian.selector);
        governor.executeBreakGlass(new address[](0), new bytes[](0));
    }

    function testExecuteBreakGlassEmptyArray() public {
        vm.prank(governor.breakGlassGuardian());
        vm.expectRevert(IMultichainGovernorV2.EmptyArray.selector);
        governor.executeBreakGlass(new address[](0), new bytes[](0));
    }

    function testExecuteBreakGlassDifferentLengths() public {
        vm.prank(governor.breakGlassGuardian());
        vm.expectRevert(IMultichainGovernorV2.ArityMismatch.selector);
        governor.executeBreakGlass(new address[](1), new bytes[](0));
    }

    function testExecuteBreakGlassNonWhitelistedFails() public {
        vm.prank(governor.breakGlassGuardian());
        vm.expectRevert(IMultichainGovernorV2.CalldataNotWhitelisted.selector);
        governor.executeBreakGlass(new address[](1), new bytes[](1));
    }

    function testExecuteBreakGlassTryToGiveBGGToSelfFails() public {
        bytes memory setBreakGlassCalldata = abi.encodeWithSignature(
            "setBreakGlassGuardian(address)",
            address(this)
        );

        vm.prank(address(governor));
        governor.updateApprovedCalldata(setBreakGlassCalldata, true);

        assertTrue(
            governor.whitelistedCalldatas(setBreakGlassCalldata),
            "calldata not whitelisted"
        );

        address[] memory targets = new address[](1);
        targets[0] = address(governor);

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = setBreakGlassCalldata;

        vm.prank(governor.breakGlassGuardian());
        vm.expectRevert(
            IMultichainGovernorV2.BreakGlassGuardianNotNull.selector
        );
        governor.executeBreakGlass(targets, calldatas);
    }

    function testExecuteBreakGlassBreakGlassGuardianSucceeds() public {
        address[] memory targets = new address[](1);
        targets[0] = address(new MockTimelock());

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "transferOwnership(address)",
            rollbackAddress
        );
        address bgg = governor.breakGlassGuardian();

        vm.prank(bgg);
        vm.expectEmit(true, true, true, true, address(governor));
        emit BreakGlassGuardianChanged(bgg, address(0));
        governor.executeBreakGlass(targets, calldatas);

        assertEq(
            governor.breakGlassGuardian(),
            address(0),
            "break glass guardian not reset"
        );

        _assertGovernanceBalance();
    }

    /// PAUSE GUARDIAN
    function testPauseNonPauseGuardianFails() public {
        vm.expectRevert(ConfigurablePauseGuardian.OnlyPauseGuardian.selector);
        vm.prank(address(1));
        governor.pause();
    }

    function testNewGuardianCannotBeSetWhenGovernorPaused() public {
        address pauseGuardian = governor.pauseGuardian();
        vm.prank(pauseGuardian);
        governor.pause();

        address newPauseGuardian = address(1);
        vm.prank(address(governor));

        vm.expectRevert("Pausable: paused");
        governor.grantPauseGuardian(newPauseGuardian);
    }

    /// ACL Positive Tests

    function testUpdateApprovedCalldataGovernorSucceeds() public {
        vm.prank(address(governor));
        governor.updateApprovedCalldata("", true);
        assertTrue(
            governor.whitelistedCalldatas(""),
            "calldata not whitelisted"
        );
    }

    function testRemoveExternalChainConfigsGovernorSucceeds() public {
        WormholeTrustedSender.TrustedSender[]
            memory _trustedSenders = testaddExternalChainConfigsGovernorSucceeds();

        vm.prank(address(governor));
        governor.removeExternalChainConfigs(_trustedSenders);

        assertFalse(
            governor.isTrustedSender(
                _trustedSenders[0].chainId,
                _trustedSenders[0].addr
            ),
            "trusted sender not removed"
        );
    }

    function testRemoveNonExistentExternalChainConfigGovernorFails() public {
        WormholeTrustedSender.TrustedSender[]
            memory _trustedSenders = new WormholeTrustedSender.TrustedSender[](
                1
            );

        _trustedSenders[0].chainId = 1;
        _trustedSenders[0].addr = address(this);

        vm.prank(address(governor));
        vm.expectRevert(WormholeBridgeBase.ChainNotAdded.selector);
        governor.removeExternalChainConfigs(_trustedSenders);
    }

    function testaddExternalChainConfigsGovernorSucceeds()
        public
        returns (WormholeTrustedSender.TrustedSender[] memory)
    {
        WormholeTrustedSender.TrustedSender[]
            memory _trustedSenders = new WormholeTrustedSender.TrustedSender[](
                1
            );

        _trustedSenders[0].chainId = 1;
        _trustedSenders[0].addr = address(this);

        vm.prank(address(governor));
        governor.addExternalChainConfigs(_trustedSenders);
        assertTrue(
            governor.isTrustedSender(
                _trustedSenders[0].chainId,
                _trustedSenders[0].addr
            ),
            "trusted sender not added"
        );

        return _trustedSenders;
    }

    function testaddExternalChainConfigsGovernorTwiceFails() public {
        WormholeTrustedSender.TrustedSender[]
            memory _trustedSenders = testaddExternalChainConfigsGovernorSucceeds();

        vm.prank(address(governor));
        vm.expectRevert(WormholeBridgeBase.ChainAlreadyAdded.selector);
        governor.addExternalChainConfigs(_trustedSenders);
    }

    function testUpdateProposalThresholdGovernorSucceeds() public {
        uint256 newProposalThreshold = Constants.MIN_PROPOSAL_THRESHOLD;

        vm.prank(address(governor));
        governor.updateProposalThreshold(newProposalThreshold);

        assertEq(
            governor.proposalThreshold(),
            newProposalThreshold,
            "proposalThreshold not updated"
        );
    }

    // V2: maxUserLiveProposals is now a constant - removed setter test

    function testUpdateQuorumGovernorSucceeds() public {
        uint256 newQuorum = 400_000_000 * 1e18;

        vm.prank(address(governor));
        governor.updateQuorum(newQuorum);

        assertEq(governor.quorum(), newQuorum, "quorum not updated");
    }

    function testUpdateVotingPeriodGovernorSucceeds() public {
        uint256 newVotingPeriod = 1 hours;

        vm.prank(address(governor));
        governor.updateVotingPeriod(newVotingPeriod);

        assertEq(
            governor.votingPeriod(),
            newVotingPeriod,
            "votingPeriod not updated"
        );
    }

    function testUpdateCrossChainVoteCollectionPeriodGovernorSucceeds() public {
        uint256 newCrossChainVoteCollectionPeriod = 1 hours;
        vm.prank(address(governor));
        governor.updateCrossChainVoteCollectionPeriod(
            newCrossChainVoteCollectionPeriod
        );

        assertEq(
            governor.crossChainVoteCollectionPeriod(),
            newCrossChainVoteCollectionPeriod,
            "crossChainVoteCollectionPeriod not updated"
        );
    }

    function testSetBreakGlassGuardianGovernorSucceeds() public {
        address newBgg = address(1);

        vm.prank(address(governor));
        governor.setBreakGlassGuardian(newBgg);

        assertEq(
            governor.breakGlassGuardian(),
            newBgg,
            "breakGlassGuardian not updated"
        );
    }

    function testGrantPauseGuardianSucceeds() public {
        address oldPauseGuardian = governor.pauseGuardian();
        address newPauseGuardian = address(1);

        vm.prank(address(governor));
        vm.expectEmit(true, true, true, true, address(governor));
        emit PauseGuardianUpdated(oldPauseGuardian, newPauseGuardian);

        governor.grantPauseGuardian(newPauseGuardian);

        assertEq(
            governor.pauseGuardian(),
            newPauseGuardian,
            "pauseGuardian not updated"
        );
    }

    function testSetGasLimitGovernorSucceeds() public {
        uint96 gasLimit = Constants.MIN_GAS_LIMIT;
        vm.prank(address(governor));
        governor.setGasLimit(gasLimit);
        assertEq(governor.gasLimit(), gasLimit, "incorrect gas limit");
    }

    /// PAUSE GUARDIAN
    function testPausePauseGuardianSucceeds() public {
        vm.warp(block.timestamp + 1);

        vm.prank(governor.pauseGuardian());
        governor.pause();

        assertTrue(governor.paused(), "governor not paused");
        assertTrue(governor.pauseUsed(), "pauseUsed not updated");
        assertEq(governor.pauseStartTime(), block.timestamp, "pauseStartTime");
    }

    function testPauseGuardianWithActiveProposalsCancelProposals() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string
            memory descriptionUri = "ipfs://QmProposalMIPM00UpdateProposalThreshold";

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "updateProposalThreshold(uint256)",
            100_000_000 * 1e18
        );

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            descriptionUri,
            true // V2: finalize parameter
        );

        assertTrue(governor.proposalActive(proposalId), "proposal not active");

        vm.prank(governor.pauseGuardian());
        governor.pause();

        assertTrue(governor.paused(), "governor not paused");
        assertTrue(governor.pauseUsed(), "pauseUsed not updated");
        assertEq(governor.pauseStartTime(), block.timestamp, "pauseStartTime");
        assertEq(
            governor.proposalActive(proposalId),
            false,
            "proposal not cancelled"
        );
    }

    function testProposeExcessValueRefunded() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string
            memory descriptionUri = "ipfs://QmProposalMIPM00UpdateProposalThreshold";

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "updateProposalThreshold(uint256)",
            100_000_000 * 1e18
        );

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost * 5);

        uint256 proposalId = governor.propose{value: bridgeCost * 5}(
            targets,
            values,
            calldatas,
            descriptionUri,
            true // V2: finalize parameter
        );

        assertTrue(governor.proposalActive(proposalId), "proposal not active");

        assertEq(
            address(this).balance,
            bridgeCost * 4,
            "excess value not refunded"
        );
    }

    function testProposeWhenPausedFails() public {
        testPausePauseGuardianSucceeds();

        vm.expectRevert("Pausable: paused");
        governor.propose(
            new address[](0),
            new uint256[](0),
            new bytes[](0),
            "",
            true // V2: finalize parameter
        );
    }

    function testExecuteWhenPausedFails() public {
        testPausePauseGuardianSucceeds();

        vm.expectRevert("Pausable: paused");
        governor.execute(0);
    }

    function testCastVoteWhenPausedFails() public {
        testPausePauseGuardianSucceeds();

        vm.expectRevert("Pausable: paused");
        governor.castVote(0, 0);
    }

    function testSendEthToGovernorSucceeds() public {
        uint256 sendAmount = 1 ether;
        vm.deal(address(this), sendAmount);

        (bool success, ) = address(governor).call{value: sendAmount}("");
        assertEq(
            address(governor).balance,
            sendAmount,
            "governor did not accept eth"
        );
        assertTrue(success, "eth transfer failed");
    }

    // VIEW FUNCTIONS

    function testVoteCollectorIsTrustedSender() public {
        testaddExternalChainConfigsGovernorSucceeds();
        assertTrue(
            governor.isTrustedSender(1, address(this)),
            "vote collector not trusted"
        );
    }

    receive() external payable {}
}
