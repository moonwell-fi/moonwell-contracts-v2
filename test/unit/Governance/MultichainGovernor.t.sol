pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {IMultichainGovernor, MultichainGovernor} from "@protocol/governance/multichainGovernor/MultichainGovernor.sol";
import {MultichainGovernorDeploy} from "@protocol/governance/multichainGovernor/MultichainGovernorDeploy.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {MultichainVoteCollection} from "@protocol/governance/multichainGovernor/MultichainVoteCollection.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Constants} from "@protocol/governance/multichainGovernor/Constants.sol";

import {MultichainBaseTest} from "@test/helper/MultichainBaseTest.t.sol";

contract MockTimelock {
    function transferOwnership(address) external pure returns (bool) {
        return true;
    }
}

contract MultichainGovernorUnitTest is MultichainBaseTest {
    event BreakGlassGuardianChanged(address oldValue, address newValue);
    event PauseGuardianUpdated(address indexed oldPauseGuardian, address indexed newPauseGuardian);

    function setUp() public override {
        super.setUp();

        xwell.delegate(address(this));
        well.delegate(address(this));
        distributor.delegate(address(this));

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }

    function testGovernorSetup() public {
        assertFalse(
            governor.useTimestamps(),
            "useTimestamps should start off false after initialization"
        );
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
        assertEq(
            governor.maxUserLiveProposals(),
            maxUserLiveProposals,
            "maxUserLiveProposals"
        );
        assertEq(governor.pauseStartTime(), 0, "pauseStartTime");
        assertEq(governor.pauseDuration(), pauseDuration, "pauseDuration");
        assertEq(governor.pauseGuardian(), pauseGuardian, "pauseGuardian");
        assertFalse(governor.paused(), "paused");
        assertFalse(governor.pauseUsed(), "paused used");

        assertEq(address(governor.well()), address(well), "well address");
        assertEq(address(governor.xWell()), address(xwell), "xwell");
        assertEq(
            address(governor.stkWell()),
            address(stkWellMoonbeam),
            "stkwell"
        );
        assertEq(
            address(governor.distributor()),
            address(distributor),
            "distributor"
        );

        assertEq(
            address(governor.targetAddress(baseWormholeChainId)),
            address(voteCollection),
            "target address on moonbeam incorrect"
        );

        assertEq(
            governor.getAllTargetChains().length,
            1,
            "getAllTargetChains length incorrect"
        );
        assertEq(
            governor.getAllTargetChains()[0],
            baseWormholeChainId,
            "getAllTargetChains chainid incorrect"
        );
        assertEq(
            governor.bridgeCost(moonBaseWormholeChainId),
            0.01 ether,
            "bridgecost incorrect"
        );
        assertEq(
            governor.bridgeCostAll(),
            0.01 ether,
            "bridgecostall incorrect"
        );
    }

    function testVoteCollectionSetup() public {
        assertEq(
            address(voteCollection.xWell()),
            address(xwell),
            "xWell address"
        );
        assertTrue(
            voteCollection.isTrustedSender(
                moonBeamWormholeChainId,
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

    function testInitLogicFails() public {
        MultichainGovernor.InitializeData memory initData;
        WormholeTrustedSender.TrustedSender[]
            memory trustedSenders = new WormholeTrustedSender.TrustedSender[](
                0
            );

        vm.expectRevert("Initializable: contract is already initialized");

        governorLogic.initialize(initData, trustedSenders, new bytes[](0));
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

    function testSetNewStkWellNonGovernorFails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.setNewStakedWell(address(0), true);
    }

    function testUpdateApprovedCalldataNonGovernorFails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.updateApprovedCalldata("", true);
    }

    function testUpdateApprovedCalldataAlreadyWhitelistedFails() public {
        testUpdateApprovedCalldataGovernorSucceeds();
        vm.prank(address(governor));
        vm.expectRevert("MultichainGovernor: calldata already approved");
        governor.updateApprovedCalldata("", true);
    }

    function testRemoveNonApprovedCalldataWhitelistedFails() public {
        testUpdateApprovedCalldataGovernorSucceeds();
        vm.prank(address(governor));
        vm.expectRevert("MultichainGovernor: calldata not approved");
        governor.updateApprovedCalldata(hex"00eeff", false);
    }

    function testUpdateApprovedCalldataNonWhitelistedFails() public {
        vm.prank(address(governor));
        vm.expectRevert("MultichainGovernor: calldata not approved");
        governor.updateApprovedCalldata("", false);
    }

    function testremoveExternalChainConfigsNonGovernorFails() public {
        WormholeTrustedSender.TrustedSender[]
            memory _trustedSenders = new WormholeTrustedSender.TrustedSender[](
                0
            );
        vm.expectRevert("MultichainGovernor: only governor");
        governor.removeExternalChainConfigs(_trustedSenders);
    }

    function testAddExternalChainConfigsNonGovernorFails() public {
        WormholeTrustedSender.TrustedSender[]
            memory _trustedSenders = new WormholeTrustedSender.TrustedSender[](
                0
            );
        vm.expectRevert("MultichainGovernor: only governor");
        governor.addExternalChainConfigs(_trustedSenders);
    }

    function testAddExternalChainConfigsAddressZeroFails() public {
        WormholeTrustedSender.TrustedSender[]
            memory _trustedSenders = new WormholeTrustedSender.TrustedSender[](
                1
            );
        _trustedSenders[0].chainId = 1;
        _trustedSenders[0].addr = address(0);

        vm.expectRevert("WormholeBridge: invalid target address");
        vm.prank(address(governor));
        governor.addExternalChainConfigs(_trustedSenders);
    }

    function testUpdateProposalThresholdNonGovernorFails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.updateProposalThreshold(1000);
    }

    function testUpdateProposalThresholdTooLowFails() public {
        vm.expectRevert("MultichainGovernor: proposal threshold out of bounds");
        vm.prank(address(governor));
        governor.updateProposalThreshold(Constants.MIN_PROPOSAL_THRESHOLD - 1);
    }

    function testUpdateProposalThresholdTooHighFails() public {
        vm.expectRevert("MultichainGovernor: proposal threshold out of bounds");
        vm.prank(address(governor));
        governor.updateProposalThreshold(Constants.MAX_PROPOSAL_THRESHOLD + 1);
    }

    function testUpdateMaxUserLiveProposalsNonGovernorFails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.updateMaxUserLiveProposals(1000);
    }

    function testUpdateMaxUserLiveProposalsZeroFails() public {
        vm.expectRevert("MultichainGovernor: invalid max user live proposals");
        vm.prank(address(governor));
        governor.updateMaxUserLiveProposals(0);
    }

    function testUpdateMaxUserLiveProposalsTooHighFails() public {
        vm.expectRevert("MultichainGovernor: invalid max user live proposals");
        vm.prank(address(governor));
        governor.updateMaxUserLiveProposals(
            Constants.MAX_USER_PROPOSAL_COUNT + 1
        );
    }

    function testUpdateQuorumNonGovernorFails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.updateQuorum(1000);
    }

    function testUpdateQuorumTooHighFails() public {
        vm.expectRevert("MultichainGovernor: invalid quorum");
        vm.prank(address(governor));
        governor.updateQuorum(Constants.MAX_QUORUM + 1);
    }

    function testUpdateVotingPeriodNonGovernorFails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.updateVotingPeriod(1000);
    }

    function testUpdateVotingPeriodTooLowFails() public {
        vm.expectRevert("MultichainGovernor: voting period out of bounds");
        vm.prank(address(governor));
        governor.updateVotingPeriod(Constants.MIN_VOTING_PERIOD - 1);
    }

    function testUpdateVotingPeriodTooHighFails() public {
        vm.expectRevert("MultichainGovernor: voting period out of bounds");
        vm.prank(address(governor));
        governor.updateVotingPeriod(Constants.MAX_VOTING_PERIOD + 1);
    }

    function testUpdateCrossChainVoteCollectionPeriodNonGovernorFails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.updateCrossChainVoteCollectionPeriod(1000);
    }

    function testUpdateCrossChainVoteCollectionPeriodTooLowFails() public {
        vm.expectRevert("MultichainGovernor: invalid vote collection period");
        vm.prank(address(governor));

        governor.updateCrossChainVoteCollectionPeriod(
            Constants.MIN_CROSS_CHAIN_VOTE_COLLECTION_PERIOD - 1
        );
    }

    function testUpdateCrossChainVoteCollectionPeriodTooHighFails() public {
        vm.expectRevert("MultichainGovernor: invalid vote collection period");
        vm.prank(address(governor));

        governor.updateCrossChainVoteCollectionPeriod(
            Constants.MAX_CROSS_CHAIN_VOTE_COLLECTION_PERIOD + 1
        );
    }

    function testSetBreakGlassGuardianNonGovernorFails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.setBreakGlassGuardian(address(this));
    }

    function testGrantPauseGuardianFails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.grantPauseGuardian(address(this));
    }

    function testSetGasLimitNonGovernorFails() public {
        uint96 gasLimit = Constants.MIN_GAS_LIMIT;
        vm.prank(address(1));
        vm.expectRevert("MultichainGovernor: only governor");
        governor.setGasLimit(gasLimit);
    }

    function testSetGasLimitTooLow() public {
        uint96 gasLimit = Constants.MIN_GAS_LIMIT - 1;
        vm.expectRevert("MultichainGovernor: gas limit too low");
        vm.prank(address(governor));
        governor.setGasLimit(gasLimit);
    }

    /// BREAK GLASS GUARDIAN

    function testExecuteBreakGlassNonBreakGlassGuardianFails() public {
        vm.expectRevert("MultichainGovernor: only break glass guardian");
        governor.executeBreakGlass(new address[](0), new bytes[](0));
    }

    function testExecuteBreakGlassEmptyArray() public {
        vm.prank(governor.breakGlassGuardian());
        vm.expectRevert("MultichainGovernor: empty array");
        governor.executeBreakGlass(new address[](0), new bytes[](0));
    }

    function testExecuteBreakGlassDifferentLengths() public {
        vm.prank(governor.breakGlassGuardian());
        vm.expectRevert("MultichainGovernor: arity mismatch");
        governor.executeBreakGlass(new address[](1), new bytes[](0));
    }

    function testExecuteBreakGlassNonWhitelistedFails() public {
        vm.prank(governor.breakGlassGuardian());
        vm.expectRevert("MultichainGovernor: calldata not whitelisted");
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
        vm.expectRevert("MultichainGovernor: break glass guardian not null");
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
        vm.expectRevert("ConfigurablePauseGuardian: only pause guardian");
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

    function testSetNewStakedWellGovernorSucceeds() public {
        address newStakedWell = address(1);
        assertFalse(governor.useTimestamps(), "timestamps incorrectly in use");

        vm.prank(address(governor));
        governor.setNewStakedWell(newStakedWell, true);

        assertEq(
            address(governor.stkWell()),
            newStakedWell,
            "new stkwell not set"
        );
        assertTrue(governor.useTimestamps(), "timestamps not in use");
    }

    function testSetNewStakedWellBaseWellGovernorSucceeds() public {
        uint256 startingVotes = governor.getVotes(
            address(this),
            block.timestamp - 1,
            block.number - 1
        );
        address newStakedWell = address(stkWellBase);
        assertFalse(governor.useTimestamps(), "timestamps incorrectly in use");

        vm.prank(address(governor));
        governor.setNewStakedWell(newStakedWell, true);

        uint256 endingVotes = governor.getVotes(
            address(this),
            block.timestamp - 1,
            block.number - 1
        );
        assertEq(endingVotes, startingVotes, "votes incorrect");
        assertEq(
            address(governor.stkWell()),
            newStakedWell,
            "new stkwell not set"
        );
        assertTrue(governor.useTimestamps(), "timestamps not in use");
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
        vm.expectRevert("WormholeBridge: chain not added");
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
        vm.expectRevert("WormholeBridge: chain already added");
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

    function testUpdateMaxUserLiveProposalsGovernorSucceeds() public {
        uint256 newMaxUserLiveProposals = 4;

        vm.prank(address(governor));
        governor.updateMaxUserLiveProposals(newMaxUserLiveProposals);

        assertEq(
            governor.maxUserLiveProposals(),
            newMaxUserLiveProposals,
            "maxUserLiveProposals not updated"
        );
    }

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
            memory description = "Proposal MIP-M00 - Update Proposal Threshold";

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
            description
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

    function testProposeWhenPausedFails() public {
        testPausePauseGuardianSucceeds();

        vm.expectRevert("Pausable: paused");
        governor.propose(
            new address[](0),
            new uint256[](0),
            new bytes[](0),
            ""
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

    // VIEW FUNCTIONS

    function testVoteCollectorIsTrustedSender() public {
        testaddExternalChainConfigsGovernorSucceeds();
        assertTrue(
            governor.isTrustedSender(1, address(this)),
            "vote collector not trusted"
        );
    }
}
