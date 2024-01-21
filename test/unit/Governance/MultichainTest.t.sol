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

import {MultichainBaseTest} from "@test/helper/MultichainBaseTest.t.sol";

contract MultichainGovernorUnitTest is MultichainBaseTest {
    function testGovernorSetup() public {
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
            governor.votingDelay(),
            votingDelaySeconds,
            "votingDelaySeconds"
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
        assertEq(governor.pauseDuration(), pauseDuration, "pauseDuration");
        assertEq(governor.pauseGuardian(), pauseGuardian, "pauseGuardian");
        assertFalse(governor.paused(), "paused");
        assertFalse(governor.pauseUsed(), "paused used");
    }

    function testVoteCollectionSetup() public {
        assertEq(
            address(voteCollection.xWell()),
            address(xwell),
            "xWell address"
        );
        assertTrue(
            voteCollection.isTrustedSender(moonbeanChainId, address(governor)),
            "governor address is trusted sender"
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

        governorLogic.initialize(initData, trustedSenders);
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
    function test_updateApprovedCalldata_NonGovernor_Fails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.updateApprovedCalldata("", true);
    }

    function test_removeTrustedSenders_NonGovernor_Fails() public {
        WormholeTrustedSender.TrustedSender[]
            memory _trustedSenders = new WormholeTrustedSender.TrustedSender[](
                0
            );
        vm.expectRevert("MultichainGovernor: only governor");
        governor.removeTrustedSenders(_trustedSenders);
    }

    function test_addTrustedSenders_NonGovernor_Fails() public {
        WormholeTrustedSender.TrustedSender[]
            memory _trustedSenders = new WormholeTrustedSender.TrustedSender[](
                0
            );
        vm.expectRevert("MultichainGovernor: only governor");
        governor.addTrustedSenders(_trustedSenders);
    }

    function test_updateProposalThreshold_NonGovernor_Fails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.updateProposalThreshold(1000);
    }

    function test_updateMaxUserLiveProposals_NonGovernor_Fails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.updateMaxUserLiveProposals(1000);
    }

    function test_updateQuorum_NonGovernor_Fails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.updateQuorum(1000);
    }

    function test_updateVotingPeriod_NonGovernor_Fails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.updateVotingPeriod(1000);
    }

    function test_updateVotingDelay_NonGovernor_Fails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.updateVotingDelay(1000);
    }

    function test_updateCrossChainVoteCollectionPeriod_NonGovernor_Fails()
        public
    {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.updateCrossChainVoteCollectionPeriod(1000);
    }

    function test_setBreakGlassGuardian_NonGovernor_Fails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.setBreakGlassGuardian(address(this));
    }

    /// BREAK GLASS GUARDIAN

    function test_executeBreakGlass_NonBreakGlassGuardian_Fails() public {
        vm.expectRevert("MultichainGovernor: only break glass guardian");
        governor.executeBreakGlass(new address[](0), new bytes[](0));
    }

    /// PAUSE GUARDIAN
    function test_pause_NonPauseGuardian_Fails() public {
        vm.expectRevert("ConfigurablePauseGuardian: only pause guardian");
        vm.prank(address(1));
        governor.pause();
    }

    /// ACL Positive Tests

    /// Voting on MultichainGovernor

    /// Voting on MultichainVoteCollection
}
