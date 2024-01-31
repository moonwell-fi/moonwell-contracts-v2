//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ChainIds} from "@test/utils/ChainIds.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {ITemporalGovernor} from "@protocol/Governance/ITemporalGovernor.sol";
import {MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";

/// Proposal to run on Moonbeam to initialize the Multichain Governor contract
contract mipm18c is HybridProposal, MultichainGovernorDeploy, ChainIds {
    string public constant name = "MIP-M18C";

    /// @notice whitelisted calldata for the break glass guardian
    bytes[] public approvedCalldata;

    /// @notice whitelisted calldata for the temporal governor
    bytes[] public temporalGovernanceCalldata;

    /// @notice trusted senders for the temporal governor
    ITemporalGovernor.TrustedSender[] public temporalGovernanceTrustedSenders;

    /// TODO verify these params with Luke before code freeze

    /// @notice duration of the voting period for a proposal
    uint256 public constant votingPeriodSeconds = 3 days;

    /// @notice minimum number of votes cast required for a proposal to pass
    uint256 public constant quorum = 1_000_000 * 1e18;

    /// @notice maximum number of live proposals that a user can have
    uint256 public constant maxUserLiveProposals = 5;

    /// @notice duration of the pause
    uint128 public constant pauseDuration = 10 days;

    /// @notice address of the temporal governor
    address[] public temporalGovernanceTargets;

    /// @notice threshold of tokens required to create a proposal
    uint256 public constant proposalThreshold = 100_000_000 * 1e18;

    /// @notice duration of the cross chain vote collection period
    uint256 public constant crossChainVoteCollectionPeriod = 1 days;

    /// @notice proposal's actions all happen on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    function buildCalldata(Addresses addresses) private {
        require(
            temporalGovernanceTargets.length == 0,
            "calldata already set in mip-18-c"
        );

        address artemisTimelock = addresses.getAddress("ARTEMIS_TIMELOCK");
        address temporalGovernor = addresses.getAddress(
            "TEMPORAL_GOVERNOR",
            sendingChainIdToReceivingChainId[block.chainid]
        );

        /// add temporal governor to list
        temporalGovernanceTargets.push(temporalGovernor);

        temporalGovernanceTrustedSenders.push(
            ITemporalGovernor.TrustedSender({
                chainId: moonBeamWormholeChainId, /// this chainId is 16 (moonBeamWormholeChainId) regardless of testnet or mainnet
                addr: artemisTimelock /// this timelock on this chain
            })
        );

        /// roll back trusted senders to artemis timelock
        /// in reality this just adds the artemis timelock as a trusted sender
        /// a second proposal is needed to revoke the Multichain Governor as a trusted sender
        temporalGovernanceCalldata.push(
            abi.encodeWithSignature(
                "setTrustedSenders((uint16,address)[])",
                temporalGovernanceTrustedSenders
            )
        );

        approvedCalldata.push(
            abi.encodeWithSignature(
                "transferOwnership(address)",
                artemisTimelock
            )
        );

        approvedCalldata.push(
            abi.encodeWithSignature("changeAdmin(address)", artemisTimelock)
        );

        approvedCalldata.push(
            abi.encodeWithSignature(
                "setEmissionsManager(address)",
                artemisTimelock
            )
        );

        approvedCalldata.push(
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                artemisTimelock
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
    }

    function deploy(Addresses addresses, address) public override {
        buildCalldata(addresses);
    }

    function afterDeploy(Addresses addresses, address) public override {
        MultichainGovernor governor = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY", moonBeamChainId)
        );

        /// executing proposal on moonbeam, but this proposal needs an address from base
        address multichainVoteCollection = addresses.getAddress(
            "VOTE_COLLECTION_PROXY",
            baseChainId
        );

        WormholeTrustedSender.TrustedSender[]
            memory trustedSenders = new WormholeTrustedSender.TrustedSender[](
                1
            );

        /// TODO give this extra review, ensure addresses and chainids are correct
        trustedSenders[0].addr = multichainVoteCollection;
        trustedSenders[0].chainId = chainIdToWormHoleId[block.chainid];

        MultichainGovernor.InitializeData memory initData;

        initData.well = addresses.getAddress("WELL");
        initData.xWell = addresses.getAddress("xWELL_PROXY");
        initData.stkWell = addresses.getAddress("stkWELL");
        initData.distributor = addresses.getAddress(
            "TOKEN_SALE_DISTRIBUTOR_PROXY"
        );
        initData.proposalThreshold = proposalThreshold;
        initData.votingPeriodSeconds = votingPeriodSeconds;
        initData
            .crossChainVoteCollectionPeriod = crossChainVoteCollectionPeriod;
        initData.quorum = quorum;
        initData.maxUserLiveProposals = maxUserLiveProposals;
        initData.pauseDuration = pauseDuration;

        initData.pauseGuardian = addresses.getAddress(
            "MOONBEAM_PAUSE_GUARDIAN_MULTISIG"
        );
        initData.breakGlassGuardian = addresses.getAddress(
            "BREAK_GLASS_GUARDIAN"
        );
        initData.wormholeRelayer = addresses.getAddress(
            "WORMHOLE_BRIDGE_RELAYER"
        );

        governor.initialize(initData, trustedSenders, approvedCalldata);
    }

    function afterDeploySetup(Addresses) public override {}

    function build(Addresses) public override {}

    function teardown(Addresses, address) public pure override {}

    function run(Addresses, address) public override {
        /// @dev enable debugging
    }

    function validate(Addresses addresses, address) public override {
        MultichainGovernor governor = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY", moonBeamChainId)
        );

        assertEq(
            governor.gasLimit(),
            400_000,
            "incorrect gas limit on multichain governor"
        );

        assertEq(
            governor.proposalThreshold(),
            proposalThreshold,
            "incorrect proposal threshold"
        );
        assertEq(
            governor.crossChainVoteCollectionPeriod(),
            crossChainVoteCollectionPeriod,
            "incorrect cross chain vote collection period"
        );
        assertEq(
            governor.maxUserLiveProposals(),
            maxUserLiveProposals,
            "incorrect max live users proposal period"
        );
        assertEq(governor.quorum(), quorum, "incorrect quorum");
        assertEq(
            governor.votingPeriod(),
            votingPeriodSeconds,
            "incorrect voting period"
        );
        assertEq(
            governor.proposalCount(),
            0,
            "incorrect starting proposalCount"
        );
        assertEq(
            address(governor.xWell()),
            addresses.getAddress("xWELL_PROXY"),
            "incorrect xwell address"
        );
        assertEq(
            address(governor.well()),
            addresses.getAddress("WELL"),
            "incorrect well address"
        );
        assertEq(
            address(governor.stkWell()),
            addresses.getAddress("stkWELL"),
            "incorrect stkWell address"
        );
        assertEq(
            address(governor.distributor()),
            addresses.getAddress("TOKEN_SALE_DISTRIBUTOR_PROXY"),
            "incorrect distributor address"
        );
        assertEq(
            governor.getNumLiveProposals(),
            0,
            "incorrect number of live proposals"
        );
        assertEq(
            governor.liveProposals().length,
            0,
            "incorrect live proposals count"
        );
        assertEq(
            governor.pauseGuardian(),
            addresses.getAddress("MOONBEAM_PAUSE_GUARDIAN_MULTISIG"),
            "incorrect moonbeam pause guardian"
        );
        assertEq(governor.pauseStartTime(), 0, "incorrect pauseStartTime");
        assertEq(
            governor.pauseDuration(),
            pauseDuration,
            "incorrect pauseDuration"
        );
        assertFalse(governor.paused(), "incorrect paused state");
        assertFalse(governor.pauseUsed(), "incorrect pauseUsed state");

        assertTrue(
            governor.isCrossChainVoteCollector(
                chainIdToWormHoleId[block.chainid],
                addresses.getAddress(
                    "VOTE_COLLECTION_PROXY",
                    sendingChainIdToReceivingChainId[block.chainid]
                )
            ),
            "incorrect cross chain vote collector"
        );
        assertTrue(
            governor.isTrustedSender(
                chainIdToWormHoleId[block.chainid],
                addresses.getAddress(
                    "VOTE_COLLECTION_PROXY",
                    sendingChainIdToReceivingChainId[block.chainid]
                )
            ),
            "vote collection proxy not trusted sender"
        );

        for (uint256 i = 0; i < approvedCalldata.length; i++) {
            assertTrue(
                governor.whitelistedCalldatas(approvedCalldata[i]),
                "calldata not approved"
            );
        }
    }
}
