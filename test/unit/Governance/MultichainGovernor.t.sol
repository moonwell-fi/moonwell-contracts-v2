pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {IMultichainGovernor, MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";

contract MultichainGovernorUnitTest is Test, MultichainGovernorDeploy {
    MultichainGovernor governor;
    uint256 public constant proposalThreshold = 100_000_000 * 1e18;
    uint256 public constant votingPeriodSeconds = 3 days;
    uint256 public constant votingDelaySeconds = 1 days;
    uint256 public constant crossChainVoteCollectionPeriod = 1 days;
    uint256 public constant quorum = 1_000_000 * 1e18;
    uint256 public constant maxUserLiveProposals = 5;
    uint128 public constant pauseDuration = 10 days;
    address public pauseGuardian = address(this);

    function setUp() public {
        MultichainGovernor.InitializeData memory initData;
        initData.proposalThreshold = proposalThreshold;
        initData.votingPeriodSeconds = votingPeriodSeconds;
        initData.votingDelaySeconds = votingDelaySeconds;
        initData
            .crossChainVoteCollectionPeriod = crossChainVoteCollectionPeriod;
        initData.quorum = quorum;
        initData.maxUserLiveProposals = maxUserLiveProposals;
        initData.pauseDuration = pauseDuration;
        initData.pauseGuardian = pauseGuardian;

        WormholeTrustedSender.TrustedSender[]
            memory trustedSenders = new WormholeTrustedSender.TrustedSender[](
                0
            );

        (
            address proxyAdmin,
            address proxy,
            address governorImpl
        ) = deployMultichainGovernor(initData, trustedSenders);

        governor = MultichainGovernor(proxy);
    }

    function testSetup() public {
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
}
