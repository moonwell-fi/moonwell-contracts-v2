pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {IMultichainGovernor, MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {MultichainVoteCollection} from "@protocol/Governance/MultichainGovernor/MultichainVoteCollection.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {ITemporalGovernor} from "@protocol/Governance/ITemporalGovernor.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Well} from "@protocol/Governance/Well.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

contract MultichainBaseTest is Test, MultichainGovernorDeploy, xWELLDeploy {
    /// @notice reference to the mock wormhole trusted sender contract
    WormholeRelayerAdapter public wormholeRelayerAdapter;

    /// @notice reference to the Multichain vote collection contract
    MultichainVoteCollection public voteCollection;

    /// @notice reference to the Multichain governor logic contract
    MultichainGovernor public governorLogic;

    /// @notice reference to the Multichain governor proxy contract
    MultichainGovernor public governor;

    /// @notice reference to the xWELL token
    xWELL public xwell;

    /// @notice reference to the well token
    Well public well;

    /// @notice reference to the well distributor contract
    Well public distributor;

    /// @notice reference to the staked well contract
    IStakedWell public stkWell;

    /// @notice threshold of tokens required to create a proposal
    uint256 public constant proposalThreshold = 100_000_000 * 1e18;

    /// @notice duration of the cross chain vote collection period
    uint256 public constant crossChainVoteCollectionPeriod = 1 days;

    /// @notice address used to simulate a rollback
    address public constant rollbackAddress = address(0xdead);

    /// @notice duration of the voting period for a proposal
    uint256 public constant votingPeriodSeconds = 3 days;

    /// @notice minimum number of votes cast required for a proposal to pass
    uint256 public constant quorum = 1_000_000 * 1e18;

    /// @notice maximum number of live proposals that a user can have
    uint256 public constant maxUserLiveProposals = 5;

    /// @notice duration of the pause
    uint128 public constant pauseDuration = 10 days;

    /// @notice moonbeam wormhole chain id
    uint16 public constant moonbeamChainId = 16;

    /// @notice base wormhole chain id
    uint16 public constant baseChainId = 30;

    /// @notice pause guardian
    address public pauseGuardian = address(this);

    /// @notice address of the temporal governor
    address[] public temporalGovernanceTargets = [address(this)];

    /// @notice trusted senders for temporal governor
    ITemporalGovernor.TrustedSender[] public temporalGovernanceTrustedSenders;

    /// @notice calldata for temporal governor
    bytes[] public temporalGovernanceCalldata;

    /// @notice whitelisted calldata for MultichainGovernor
    bytes[] public approvedCalldata;

    constructor() {
        temporalGovernanceTrustedSenders.push(
            ITemporalGovernor.TrustedSender({
                chainId: moonbeamChainId,
                addr: address(this)
            })
        );

        temporalGovernanceCalldata.push(
            abi.encodeWithSignature(
                "setTrustedSenders((uint16,address)[])",
                temporalGovernanceTrustedSenders
            )
        );

        approvedCalldata.push(
            abi.encodeWithSignature(
                "transferOwnership(address)",
                rollbackAddress
            )
        );

        approvedCalldata.push(
            abi.encodeWithSignature("changeAdmin(address)", rollbackAddress)
        );

        approvedCalldata.push(
            abi.encodeWithSignature(
                "setEmissionsManager(address)",
                rollbackAddress
            )
        );

        approvedCalldata.push(
            abi.encodeWithSignature(
                "publishMessage(uint32,bytes,uint8)",
                1000,
                abi.encode(
                    temporalGovernanceTargets[0],
                    temporalGovernanceTargets,
                    new uint256[](1),
                    temporalGovernanceCalldata
                ),
                200
            )
        );

        approvedCalldata.push(
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                rollbackAddress
            )
        );
    }

    function setUp() public virtual {
        vm.warp(100 + block.timestamp);

        well = new Well(address(this));
        distributor = new Well(address(this));

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

        address proxyAdmin = address(new ProxyAdmin());
        (address stkWellProxy, ) = deployStakedWell(
            address(xwellProxy),
            address(xwellProxy),
            1 days,
            1 weeks,
            address(this), // rewardsVault
            address(this), // emissionManager
            1 days, // distributionDuration
            address(0), // governance
            proxyAdmin // proxyAdmin
        );

        stkWell = IStakedWell(stkWellProxy);

        MultichainGovernor.InitializeData memory initData;
        initData.proposalThreshold = proposalThreshold;
        initData.votingPeriodSeconds = votingPeriodSeconds;
        initData
            .crossChainVoteCollectionPeriod = crossChainVoteCollectionPeriod;
        initData.quorum = quorum;
        initData.maxUserLiveProposals = maxUserLiveProposals;
        initData.pauseDuration = pauseDuration;
        initData.pauseGuardian = pauseGuardian;
        initData.breakGlassGuardian = address(123);
        initData.xWell = xwellProxy;
        initData.well = address(well);
        initData.stkWell = address(stkWell);
        initData.distributor = address(distributor);

        MultichainGovernorDeploy.MultichainAddresses
            memory addresses = deployGovernorRelayerAndVoteCollection(
                initData,
                approvedCalldata,
                proxyAdmin, // proxyAdmin
                moonbeamChainId, // wormhole moonbeam chain id
                baseChainId, // wormhole base chain id
                address(this) // voteCollectionOwner
            );

        governor = MultichainGovernor(addresses.governorProxy);
        governorLogic = MultichainGovernor(addresses.governorImplementation);
        xwell = xWELL(xwellProxy);
        wormholeRelayerAdapter = WormholeRelayerAdapter(
            addresses.wormholeRelayerAdapter
        );
        voteCollection = MultichainVoteCollection(
            addresses.voteCollectionProxy
        );

        xwell.addBridge(
            MintLimits.RateLimitMidPointInfo({
                bridge: address(this),
                rateLimitPerSecond: 0,
                bufferCap: 10_000_000_000 * 1e18
            })
        );

        xwell.mint(address(this), 5_000_000_000 * 1e18);

        uint256 amountToStake = 2_000_000_000 * 1e18;
        xwell.approve(address(stkWell), amountToStake);
        stkWell.stake(address(this), amountToStake);

        xwell.delegate(address(this));
        well.delegate(address(this));
        distributor.delegate(address(this));

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }

    function _createProposalUpdateThreshold() internal returns (uint256) {
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

        return proposalId;
    }

    // helper functions
    function _getVoteCollectionProposalInformation(
        uint256 proposalId
    )
        internal
        view
        returns (
            IMultichainGovernor.ProposalInformation memory proposalInformation
        )
    {
        (
            proposalInformation.snapshotStartTimestamp,
            proposalInformation.votingStartTime,
            proposalInformation.endTimestamp,
            proposalInformation.crossChainVoteCollectionEndTimestamp,
            proposalInformation.totalVotes,
            proposalInformation.forVotes,
            proposalInformation.againstVotes,
            proposalInformation.abstainVotes
        ) = voteCollection.proposalInformation(proposalId);
    }
}
