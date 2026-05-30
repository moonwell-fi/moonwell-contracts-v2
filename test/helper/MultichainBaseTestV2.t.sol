pragma solidity 0.8.19;

import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "@forge-std/Test.sol";

import {Well} from "@protocol/governance/Well.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {ITemporalGovernor} from "@protocol/governance/ITemporalGovernor.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {MockMultichainGovernorV2} from "@test/mock/MockMultichainGovernorV2.sol";
import {MockVotingPowerAggregator} from "@test/mock/MockVotingPowerAggregator.sol";
import {MultichainVoteCollectionV2} from "@protocol/governance/multichain/MultichainVoteCollectionV2.sol";
import {MultichainVoteCollectionMoonbeam} from "@protocol/governance/multichain/MultichainVoteCollectionMoonbeam.sol";
import {BridgeOutHelper} from "@test/helper/BridgeOutHelper.sol";
import {MultichainGovernorDeploy} from "@script/DeployMultichainGovernor.s.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {IMultichainGovernorV2, MultichainGovernorV2} from "@protocol/governance/multichain/MultichainGovernorV2.sol";
import {VotingPowerAggregator} from "@protocol/governance/multichain/VotingPowerAggregator.sol";
import {ChainIds, BASE_WORMHOLE_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID} from "@utils/ChainIds.sol";

contract MultichainBaseTestV2 is Test, MultichainGovernorDeploy, xWELLDeploy {
    using ChainIds for uint256;

    event BridgeOutSuccess(
        uint16 dstWormholeChainId,
        uint256 cost,
        address dst,
        bytes payload
    );

    event BridgeOutFailed(uint16 chainId, bytes payload, uint256 refundAmount);

    /// @notice reference to the mock wormhole trusted sender contract
    WormholeRelayerAdapter public wormholeRelayerAdapter;

    /// @notice reference to the Multichain vote collection contract (Base/OP version)
    MultichainVoteCollectionV2 public voteCollection;

    /// @notice reference to the Multichain vote collection contract (Moonbeam version)
    MultichainVoteCollectionMoonbeam public voteCollectionMoonbeam;

    /// @notice reference to the Multichain governor logic contract
    MockMultichainGovernorV2 public governorLogic;

    /// @notice reference to the Multichain governor proxy contract
    MockMultichainGovernorV2 public governor;

    /// @notice reference to the VotingPowerAggregator
    MockVotingPowerAggregator public votingPowerAggregator;

    /// @notice reference to the xWELL token
    xWELL public xwell;

    /// @notice reference to the well token
    Well public well;

    /// @notice reference to the well distributor contract
    Well public distributor;

    /// @notice reference to the staked well contract
    IStakedWell public stkWellMoonbeam;

    /// @notice reference to the staked well contract
    IStakedWell public stkWellBase;

    address public proxyAdmin;
    address public xwellProxyAdmin;

    /// @notice threshold of tokens required to create a proposal
    uint256 public constant proposalThreshold = 50_000_000 * 1e18;

    /// @notice duration of the cross chain vote collection period
    uint256 public constant crossChainVoteCollectionPeriod = 1 days;

    /// @notice address used to simulate a rollback
    address public constant rollbackAddress = address(0xdead);

    /// @notice duration of the voting period for a proposal
    uint256 public constant votingPeriodSeconds = 3 days;

    /// @notice minimum number of votes cast required for a proposal to pass
    uint256 public constant quorum = 1_000_000 * 1e18;

    /// @notice duration of the pause
    uint128 public constant pauseDuration = 10 days;

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

    /// @notice break glass guardian
    address public constant breakGlassGuardian = address(123);

    constructor() {
        temporalGovernanceTrustedSenders.push(
            ITemporalGovernor.TrustedSender({
                chainId: MOONBEAM_WORMHOLE_CHAIN_ID,
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
        (, address xwellProxy, address _xwellProxyAdmin) = deployXWell(
            "XWell",
            "XWELL",
            address(this), //owner
            newRateLimits,
            pauseDuration,
            pauseGuardian
        );
        xwellProxyAdmin = _xwellProxyAdmin;

        proxyAdmin = address(new ProxyAdmin());
        {
            /// deploy staked well with timestamps (upgraded to use timestamps per governance changes)
            /// all chains now use timestamps instead of block numbers
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
            stkWellMoonbeam = IStakedWell(stkWellProxy);
        }

        {
            /// deploy staked well with timestamps
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

            stkWellBase = IStakedWell(stkWellProxy);
        }

        xwell = xWELL(xwellProxy);

        // Deploy VotingPowerAggregator
        MockVotingPowerAggregator votingPowerImpl = new MockVotingPowerAggregator();
        TransparentUpgradeableProxy votingPowerProxy = new TransparentUpgradeableProxy(
                address(votingPowerImpl),
                proxyAdmin,
                abi.encodeWithSignature(
                    "initialize(address,address)",
                    address(this),
                    address(xwell)
                )
            );
        votingPowerAggregator = MockVotingPowerAggregator(
            address(votingPowerProxy)
        );

        // Add snapshot sources to VotingPowerAggregator
        // NOTE: well and distributor removed as voting sources per governance changes
        // Most users have migrated to xWell, and distributor tokens have mostly vested
        votingPowerAggregator.addSnapshotSource(address(stkWellMoonbeam));

        // Deploy wormhole relayer adapter
        wormholeRelayerAdapter = new WormholeRelayerAdapter(
            new uint16[](0),
            new uint256[](0)
        );
        wormholeRelayerAdapter.setSenderChainId(MOONBEAM_WORMHOLE_CHAIN_ID);

        // Deploy MultichainGovernorV2
        MultichainGovernorV2.InitializeData memory initData;

        initData.votingPower = address(votingPowerAggregator);
        initData.proposalThreshold = proposalThreshold;
        initData.votingPeriodSeconds = votingPeriodSeconds;
        initData
            .crossChainVoteCollectionPeriod = crossChainVoteCollectionPeriod;
        initData.quorum = quorum;
        initData.pauseDuration = pauseDuration;
        initData.pauseGuardian = pauseGuardian;
        initData.breakGlassGuardian = breakGlassGuardian;
        initData.wormholeCore = address(wormholeRelayerAdapter);
        initData.startingProposalCount = 0;

        governorLogic = new MockMultichainGovernorV2();

        WormholeTrustedSender.TrustedSender[]
            memory trustedSenders = new WormholeTrustedSender.TrustedSender[](
                1
            );
        trustedSenders[0].chainId = BASE_WORMHOLE_CHAIN_ID;
        trustedSenders[0].addr = address(0x1); // placeholder, will be updated

        TransparentUpgradeableProxy governorProxy = new TransparentUpgradeableProxy(
                address(governorLogic),
                proxyAdmin,
                abi.encodeWithSignature(
                    "initialize((address,uint256,uint256,uint256,uint256,uint128,uint128,address,address,address),(uint16,address)[],bytes[])",
                    initData,
                    trustedSenders,
                    approvedCalldata
                )
            );

        governor = MockMultichainGovernorV2(payable(address(governorProxy)));

        // Deploy vote collection V2 with its own VotingPowerAggregator
        // VoteCollection needs xWell + stkWellBase sources
        (address voteCollectionProxy, ) = deployVoteCollectionV2(
            address(0), // create a new VotingPowerAggregator for vote collection
            address(xwell),
            address(stkWellBase),
            address(governor),
            address(wormholeRelayerAdapter),
            MOONBEAM_WORMHOLE_CHAIN_ID,
            proxyAdmin,
            address(this) // owner
        );

        voteCollection = MultichainVoteCollectionV2(voteCollectionProxy);

        // Deploy vote collection Moonbeam version with its own VotingPowerAggregator
        // VoteCollection needs xWell + well + distributor + stkWell sources (Moonbeam pattern)
        (address voteCollectionMoonbeamProxy, ) = deployVoteCollectionMoonbeam(
            address(0), // create a new VotingPowerAggregator for vote collection
            address(xwell),
            address(stkWellMoonbeam), // Use Moonbeam stkWell not Base
            address(governor),
            address(wormholeRelayerAdapter),
            MOONBEAM_WORMHOLE_CHAIN_ID,
            proxyAdmin,
            address(this) // owner
        );

        voteCollectionMoonbeam = MultichainVoteCollectionMoonbeam(
            voteCollectionMoonbeamProxy
        );

        // Update trusted sender to point to vote collection (V2 by default)
        vm.prank(address(governor));
        governor.removeExternalChainConfigs(trustedSenders);

        trustedSenders[0].addr = address(voteCollection);
        vm.prank(address(governor));
        governor.addExternalChainConfigs(trustedSenders);

        xwell.addBridge(
            MintLimits.RateLimitMidPointInfo({
                bridge: address(this),
                rateLimitPerSecond: 0,
                bufferCap: 10_000_000_000 * 1e18
            })
        );

        /// 3b xWELL left over
        xwell.mint(address(this), 5_000_000_000 * 1e18);

        uint256 amountToStake = 1_000_000_000 * 1e18;

        xwell.approve(address(stkWellMoonbeam), amountToStake);
        xwell.approve(address(stkWellBase), amountToStake);
        stkWellMoonbeam.stake(address(this), amountToStake);
        stkWellBase.stake(address(this), amountToStake);

        xwell.delegate(address(this));
        well.delegate(address(this));
        distributor.delegate(address(this));

        vm.warp(block.timestamp + 1);
    }

    function _createProposalUpdateThreshold(
        address creator
    ) internal returns (uint256) {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string
            memory descriptionUri = "ipfs://QmProposalMIPM00UpdateProposalThreshold";

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "updateProposalThreshold(uint256)",
            40_000_000 * 1e18
        );

        uint256 startProposalCount = governor.proposalCount();
        uint256 bridgeCost = governor.bridgeCostAll();

        vm.deal(creator, bridgeCost);
        vm.recordLogs();
        vm.prank(creator);
        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            descriptionUri,
            true // finalize
        );

        uint256 endProposalCount = governor.proposalCount();

        assertEq(
            startProposalCount + 1,
            endProposalCount,
            "proposal count incorrect"
        );
        assertEq(proposalId, endProposalCount, "proposal id incorrect");
        assertTrue(governor.proposalActive(proposalId), "proposal not active");

        /// publishMessage does not auto-deliver; parse BridgeOutSuccess events
        /// and manually relay each to the target via processVAA
        _deliverBridgeOutEvents(address(governor));

        return proposalId;
    }

    // helper functions
    function _getVoteCollectionProposalInformation(
        uint256 proposalId
    )
        internal
        view
        virtual
        returns (
            IMultichainGovernorV2.ProposalInformation memory proposalInformation
        )
    {
        (
            proposalInformation.voteSnapshotTimestamp,
            proposalInformation.votingStartTime,
            proposalInformation.votingEndTime,
            proposalInformation.crossChainVoteCollectionEndTimestamp,
            proposalInformation.totalVotes,
            proposalInformation.forVotes,
            proposalInformation.againstVotes,
            proposalInformation.abstainVotes
        ) = voteCollection.proposalInformation(proposalId);
    }

    // token can be xWELL, WELL or stkWELL
    function _delegateVoteAmountForUser(
        address token,
        address user,
        uint256 voteAmount
    ) internal {
        if (
            token != address(stkWellMoonbeam) && token != address(stkWellBase)
        ) {
            if (token == address(xwell)) {
                xwell.transfer(user, voteAmount);
            } else if (token == address(well)) {
                well.transfer(user, voteAmount);
            } else if (token == address(distributor)) {
                distributor.transfer(user, voteAmount);
            }

            vm.prank(user);
            Well(token).delegate(user);
        } else {
            xwell.transfer(user, voteAmount);

            vm.prank(user);
            xwell.approve(token, voteAmount);

            vm.prank(user);
            IStakedWell(token).stake(user, voteAmount);
        }

        /// include user before snapshot timestamp
        vm.warp(block.timestamp + 1);
    }

    /// @notice Convenience wrapper: parse BridgeOutSuccess events and deliver via processVAA
    function _deliverBridgeOutEvents(address emitter) internal {
        BridgeOutHelper.deliverBridgeOutEvents(
            vm,
            wormholeRelayerAdapter,
            emitter
        );
    }

    function _assertGovernanceBalance() internal view {
        // governor and vote collection should never have ether at the end of a test
        assertEq(address(governor).balance, 0, "governor has ether");
        assertEq(
            address(voteCollection).balance,
            0,
            "vote collection has ether"
        );
    }

    // Override to use MockVotingPowerAggregator in tests instead of real implementation
    function _deployVotingPowerAggregatorForMoonbeam(
        address xWell,
        address stkWell,
        address _proxyAdmin,
        address owner
    ) internal override returns (address votingPowerProxy) {
        MockVotingPowerAggregator vpaImpl = new MockVotingPowerAggregator();

        TransparentUpgradeableProxy vpaProxy = new TransparentUpgradeableProxy(
            address(vpaImpl),
            _proxyAdmin,
            abi.encodeWithSignature("initialize(address,address)", owner, xWell)
        );
        votingPowerProxy = address(vpaProxy);

        // Add snapshot sources for Moonbeam
        // NOTE: well and distributor removed as voting sources per governance changes
        // Most users have migrated to xWell, and distributor tokens have mostly vested
        // xWell is already added through the VotingPowerAggregator's _getCustomVotes
        MockVotingPowerAggregator(votingPowerProxy).addSnapshotSource(stkWell);
    }
}
