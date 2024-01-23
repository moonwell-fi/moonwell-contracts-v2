pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {IMultichainGovernor, MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {MultichainVoteCollection} from "@protocol/Governance/MultichainGovernor/MultichainVoteCollection.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Well} from "@protocol/Governance/Well.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";

contract MultichainBaseTest is Test, MultichainGovernorDeploy, xWELLDeploy {
    WormholeRelayerAdapter public wormholeRelayerAdapter;
    MultichainVoteCollection public voteCollection;
    MultichainGovernor public governorLogic; /// logic contract
    MultichainGovernor public governor; /// proxy contract

    xWELL public xwell;
    Well public well;
    Well public distributor;
    IStakedWell public stkWell;

    uint256 public constant proposalThreshold = 100_000_000 * 1e18;
    uint256 public constant votingPeriodSeconds = 3 days;
    uint256 public constant votingDelaySeconds = 1 days;
    uint256 public constant crossChainVoteCollectionPeriod = 1 days;
    uint256 public constant quorum = 1_000_000 * 1e18;
    uint256 public constant maxUserLiveProposals = 5;
    uint128 public constant pauseDuration = 10 days;
    uint16 public constant moonbeanChainId = 16;
    address public pauseGuardian = address(this);

    function setUp() public virtual {
        vm.warp(100 + block.timestamp);

        well = new Well(address(this));
        distributor = new Well(address(this));
        address stakedWellAddress = deployCode("StakedWell.sol:StakedWell");
        stkWell = IStakedWell(stakedWellAddress);

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
        initData.xWell = xwellProxy;
        initData.well = address(well);
        initData.stkWell = address(stkWell);
        initData.distributor = address(distributor);

        (
            address governorProxy,
            address governorImplementation,
            address voteCollectionProxy,
            address wormholeRelayerAdapterAddress,

        ) = deployGovernorRelayerAndVoteCollection(initData, address(0), 16);

        governor = MultichainGovernor(governorProxy);
        governorLogic = MultichainGovernor(governorImplementation);
        xwell = xWELL(xwellProxy);
        wormholeRelayerAdapter = WormholeRelayerAdapter(
            wormholeRelayerAdapterAddress
        );
        voteCollection = MultichainVoteCollection(voteCollectionProxy);

        xwell.addBridge(
            MintLimits.RateLimitMidPointInfo({
                bridge: address(this),
                rateLimitPerSecond: 0,
                bufferCap: 10_000_000_000 * 1e18
            })
        );

        xwell.mint(address(this), 5_000_000_000 * 1e18);
    }
}
