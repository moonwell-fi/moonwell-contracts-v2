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

contract MultichainBaseTest is Test, MultichainGovernorDeploy, xWELLDeploy {
    WormholeRelayerAdapter public wormholeRelayerAdapter;
    MultichainVoteCollection public voteCollection;
    MultichainGovernor public governorLogic; /// logic contract
    MultichainGovernor public governor; /// proxy contract
    xWELL public xwell;

    uint256 public constant proposalThreshold = 100_000_000 * 1e18;
    uint256 public constant votingPeriodSeconds = 3 days;
    uint256 public constant votingDelaySeconds = 1 days;
    uint256 public constant crossChainVoteCollectionPeriod = 1 days;
    uint256 public constant quorum = 1_000_000 * 1e18;
    uint256 public constant maxUserLiveProposals = 5;
    uint128 public constant pauseDuration = 10 days;
    uint16 public constant moonbeanChainId = 16;
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
        /// TODO add relayer to initData

        WormholeTrustedSender.TrustedSender[]
            memory trustedSenders = new WormholeTrustedSender.TrustedSender[](
                0
            );

        (
            address proxyAdmin,
            address governorProxy,
            address governorImplementation
        ) = deployMultichainGovernor(initData, trustedSenders);

        governor = MultichainGovernor(governorProxy);
        governorLogic = MultichainGovernor(governorImplementation);

        MintLimits.RateLimitMidPointInfo[]
            memory newRateLimits = new MintLimits.RateLimitMidPointInfo[](0);

        /// deploy xWELL
        (, address xwellProxy, ) = deployXWell(
            "XWell",
            "XWELL",
            address(this), //owner
            newRateLimits,
            pauseDuration,
            pauseGuardian
        );

        xwell = xWELL(xwellProxy);

        wormholeRelayerAdapter = new WormholeRelayerAdapter();

        (address voteCollectionProxy, ) = deployVoteCollection(
            xwellProxy,
            governorProxy,
            address(wormholeRelayerAdapter),
            moonbeanChainId,
            proxyAdmin
        );
        voteCollection = MultichainVoteCollection(voteCollectionProxy);
    }
}
