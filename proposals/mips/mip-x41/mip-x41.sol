//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {MultichainGovernorV2} from "@protocol/governance/multichain/MultichainGovernorV2.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {ITemporalGovernor} from "@protocol/governance/ITemporalGovernor.sol";
import {VotingPowerAggregator} from "@protocol/governance/multichain/VotingPowerAggregator.sol";
import {MultichainVoteCollectionV2} from "@protocol/governance/multichain/MultichainVoteCollectionV2.sol";
import {MultichainVoteCollectionMoonbeam} from "@protocol/governance/multichain/MultichainVoteCollectionMoonbeam.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";

import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID, ETHEREUM_FORK_ID} from "@utils/ChainIds.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {ChainIds} from "@utils/ChainIds.sol";

/// @title MIP-X41: MultichainGovernorV2 Migration to Ethereum Mainnet
/// @author Moonwell Contributors
/// @notice Proposal to:
///         1. Deploy MultichainGovernorV2 on Ethereum Mainnet
///         2. Deploy TemporalGovernor on Moonbeam
///         3. Deploy MultichainVoteCollectionMoonbeam on Moonbeam, with VotingPowerAggregator on Moonbeam, Base, and OP
///            - VotingPowerAggregator uses timestamp-based voting (no block numbers)
///            - Moonbeam: removes well/distributor sources, only uses xWell + stkWell
///            - Base/Optimism: only uses xWell + stkWell
///         4. Upgrade MultichainGovernor on Moonbeam to latest version of MultichainGovernor (with recoverETH())
///         5. Recover ETH from MultichainGovernor on Moonbeam and transfer to WELL_FOUNDATION_MULTISIG
///         6. Transfer ownership of all active & owned contracts on Moonbeam to new TemporalGovernor
///         7. Upgrade MultichainVoteCollection instance on Base and OP to MultichainVoteCollectionV2
///         8. Set MultichainGovernorV2 as trusted sender on MultichainVoteCollectionV2 on Base and OP
contract mipx41 is HybridProposal {
    using ProposalActions for *;
    using ChainIds for uint256;

    string public constant override name = "MIP-X41";

    // Governance parameters (same values as TemporalGovernor on Base)
    uint256 public constant TEMPORAL_GOVERNOR_PROPOSAL_DELAY = 86400;
    uint256 public constant TEMPORAL_GOVERNOR_PERMISSIONLESS_UNPAUSE_TIME =
        2592000;

    // MultichainGovernorV2 parameters (from MultichainGovernor on Moonbeam)
    uint256 public constant PROPOSAL_THRESHOLD = 1000000000000000000000000;
    uint256 public constant VOTING_PERIOD_SECONDS = 259200;
    uint256 public constant CROSS_CHAIN_VOTE_COLLECTION_PERIOD = 86400;
    uint256 public constant QUORUM = 100000000000000000000000000;
    uint128 public constant PAUSE_DURATION = 2592000;

    // Moonbeam contracts that should have ownership transferred to the new TemporalGovernor
    string[] private contractsToValidateOwnership;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-x41/x41.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function run() public override {
        primaryForkId().createForksAndSelect();

        Addresses addresses = new Addresses();
        vm.makePersistent(address(addresses));

        initProposal(addresses);

        (, address deployerAddress, ) = vm.readCallers();

        if (DO_DEPLOY) deploy(addresses, deployerAddress);
        if (DO_AFTER_DEPLOY) afterDeploy(addresses, deployerAddress);

        if (DO_BUILD) build(addresses);
        if (DO_RUN) run(addresses, deployerAddress);
        if (DO_TEARDOWN) teardown(addresses, deployerAddress);
        if (DO_VALIDATE) {
            validate(addresses, deployerAddress);
            console2.log("Validation completed for proposal ", this.name());
        }
        if (DO_PRINT) {
            printProposalActionSteps();

            addresses.removeAllRestrictions();
            printCalldata(addresses);

            _printAddressesChanges(addresses);
        }
    }

    function primaryForkId() public pure override returns (uint256) {
        return ETHEREUM_FORK_ID;
    }

    function deploy(Addresses addresses, address) public override {
        // ============ ETHEREUM MAINNET DEPLOYMENTS ============
        vm.selectFork(ETHEREUM_FORK_ID);

        // 1. Deploy MultichainGovernorV2 on Ethereum
        if (!addresses.isAddressSet("MULTICHAIN_GOVERNOR_V2_IMPL")) {
            vm.startBroadcast();

            address governorV2Impl = address(new MultichainGovernorV2());

            vm.stopBroadcast();

            addresses.addAddress("MULTICHAIN_GOVERNOR_V2_IMPL", governorV2Impl);
        }

        if (!addresses.isAddressSet("PROXY_ADMIN")) {
            vm.startBroadcast();

            address ethereumProxyAdmin = address(new ProxyAdmin());

            vm.stopBroadcast();

            addresses.addAddress("PROXY_ADMIN", ethereumProxyAdmin);
        }

        if (!addresses.isAddressSet("MULTICHAIN_GOVERNOR_V2_PROXY")) {
            address governorV2Impl = addresses.getAddress(
                "MULTICHAIN_GOVERNOR_V2_IMPL"
            );
            address ethereumProxyAdmin = addresses.getAddress("PROXY_ADMIN");

            vm.startBroadcast();

            address governorV2Proxy = address(
                new TransparentUpgradeableProxy(
                    governorV2Impl,
                    ethereumProxyAdmin,
                    ""
                )
            );

            vm.stopBroadcast();

            addresses.addAddress(
                "MULTICHAIN_GOVERNOR_V2_PROXY",
                governorV2Proxy
            );
        }

        // Deploy VotingPowerAggregator on Ethereum
        if (!addresses.isAddressSet("VOTING_POWER_AGGREGATOR")) {
            address ethereumProxyAdmin = addresses.getAddress("PROXY_ADMIN");
            address governorV2Proxy = addresses.getAddress(
                "MULTICHAIN_GOVERNOR_V2_PROXY"
            );
            address xWellAddress = addresses.getAddress("xWELL_PROXY");

            vm.startBroadcast();

            address votingPowerImpl = address(new VotingPowerAggregator());

            bytes memory votingPowerInitData = abi.encodeWithSignature(
                "initialize(address,address)",
                governorV2Proxy,
                xWellAddress
            );

            address votingPowerProxy = address(
                new TransparentUpgradeableProxy(
                    votingPowerImpl,
                    ethereumProxyAdmin,
                    votingPowerInitData
                )
            );

            vm.stopBroadcast();

            addresses.addAddress(
                "VOTING_POWER_AGGREGATOR_IMPL",
                votingPowerImpl
            );
            addresses.addAddress("VOTING_POWER_AGGREGATOR", votingPowerProxy);
        }

        // ============ MOONBEAM DEPLOYMENTS ============
        vm.selectFork(MOONBEAM_FORK_ID);

        // 2. Deploy TemporalGovernor on Moonbeam
        if (!addresses.isAddressSet("TEMPORAL_GOVERNOR", block.chainid)) {
            address wormholeCore = addresses.getAddress("WORMHOLE_CORE");
            address moonbeamProxyAdmin = addresses.getAddress(
                "MOONBEAM_PROXY_ADMIN"
            );

            // Get the newly deployed MultichainGovernorV2 address on Ethereum
            vm.selectFork(ETHEREUM_FORK_ID);
            address governorV2Proxy = addresses.getAddress(
                "MULTICHAIN_GOVERNOR_V2_PROXY"
            );

            vm.selectFork(MOONBEAM_FORK_ID);

            // Set up trusted sender (Ethereum MultichainGovernorV2)
            ITemporalGovernor.TrustedSender[]
                memory trustedSenders = new ITemporalGovernor.TrustedSender[](
                    1
                );
            uint16 ethereumWormholeChainId = ChainIds.toEthereumWormholeChainId(
                block.chainid
            );
            trustedSenders[0] = ITemporalGovernor.TrustedSender({
                chainId: ethereumWormholeChainId,
                addr: governorV2Proxy
            });

            vm.startBroadcast();

            address temporalGovernorImpl = address(
                new TemporalGovernor(
                    wormholeCore,
                    TEMPORAL_GOVERNOR_PROPOSAL_DELAY,
                    TEMPORAL_GOVERNOR_PERMISSIONLESS_UNPAUSE_TIME,
                    trustedSenders
                )
            );

            address temporalGovernorProxy = address(
                new TransparentUpgradeableProxy(
                    temporalGovernorImpl,
                    moonbeamProxyAdmin,
                    ""
                )
            );

            vm.stopBroadcast();

            addresses.addAddress(
                "TEMPORAL_GOVERNOR_IMPL",
                temporalGovernorImpl
            );
            addresses.addAddress("TEMPORAL_GOVERNOR", temporalGovernorProxy);
        }

        // Deploy VotingPowerAggregator on Moonbeam
        if (!addresses.isAddressSet("VOTING_POWER_AGGREGATOR", block.chainid)) {
            address xWell = addresses.getAddress("xWELL_PROXY");
            address stkWell = addresses.getAddress("STK_GOVTOKEN_PROXY");
            address temporalGovernor = addresses.getAddress(
                "TEMPORAL_GOVERNOR"
            );
            address moonbeamProxyAdmin = addresses.getAddress(
                "MOONBEAM_PROXY_ADMIN"
            );

            vm.startBroadcast();

            address votingPowerImpl = address(new VotingPowerAggregator());

            bytes memory votingPowerInitData = abi.encodeWithSignature(
                "initialize(address,address)",
                temporalGovernor,
                xWell
            );

            address votingPowerProxy = address(
                new TransparentUpgradeableProxy(
                    votingPowerImpl,
                    moonbeamProxyAdmin,
                    votingPowerInitData
                )
            );

            // Add snapshot sources for Moonbeam
            // NOTE: well and distributor removed as voting sources per governance changes
            // Most users have migrated to xWell, and distributor tokens have mostly vested
            // xWell is already handled via _getCustomVotes, so only add stkWell
            // All sources now use timestamp-based snapshots (stkWell upgraded to timestamps)
            VotingPowerAggregator(votingPowerProxy).addSnapshotSource(stkWell);

            vm.stopBroadcast();

            addresses.addAddress(
                "VOTING_POWER_AGGREGATOR_IMPL",
                votingPowerImpl
            );
            addresses.addAddress("VOTING_POWER_AGGREGATOR", votingPowerProxy);
        }

        // 3. Deploy MultichainVoteCollectionMoonbeam on Moonbeam
        if (
            !addresses.isAddressSet("VOTE_COLLECTION_V2_PROXY", block.chainid)
        ) {
            address wormholeRelayer = addresses.getAddress(
                "WORMHOLE_BRIDGE_RELAYER_PROXY"
            );
            address temporalGovernor = addresses.getAddress(
                "TEMPORAL_GOVERNOR"
            );
            address votingPowerAggregator = addresses.getAddress(
                "VOTING_POWER_AGGREGATOR"
            );
            address moonbeamProxyAdmin = addresses.getAddress(
                "MOONBEAM_PROXY_ADMIN"
            );

            vm.selectFork(ETHEREUM_FORK_ID);
            address ethereumGovernorV2 = addresses.getAddress(
                "MULTICHAIN_GOVERNOR_V2_PROXY"
            );
            uint16 ethereumWormholeChainId = ChainIds.toEthereumWormholeChainId(
                block.chainid
            );

            vm.selectFork(MOONBEAM_FORK_ID);

            // Initialize MultichainVoteCollectionMoonbeam with VotingPowerAggregator
            bytes memory initData = abi.encodeWithSignature(
                "initialize(address,address,address,uint16,address)",
                votingPowerAggregator,
                ethereumGovernorV2,
                wormholeRelayer,
                ethereumWormholeChainId,
                temporalGovernor
            );

            vm.startBroadcast();

            address voteCollectionImpl = address(
                new MultichainVoteCollectionMoonbeam()
            );

            address voteCollectionProxy = address(
                new TransparentUpgradeableProxy(
                    voteCollectionImpl,
                    moonbeamProxyAdmin,
                    initData
                )
            );

            vm.stopBroadcast();

            addresses.addAddress("VOTE_COLLECTION_V2_IMPL", voteCollectionImpl);
            addresses.addAddress(
                "VOTE_COLLECTION_V2_PROXY",
                voteCollectionProxy
            );
        }

        // ============ BASE DEPLOYMENTS ============
        vm.selectFork(BASE_FORK_ID);

        // Deploy VotingPowerAggregator on Base
        if (!addresses.isAddressSet("VOTING_POWER_AGGREGATOR", block.chainid)) {
            address xWell = addresses.getAddress("xWELL_PROXY");
            address stkWell = addresses.getAddress("STK_GOVTOKEN_PROXY");
            address baseProxyAdmin = addresses.getAddress("MRD_PROXY_ADMIN"); // TODO: correct?
            address temporalGovernor = addresses.getAddress(
                "TEMPORAL_GOVERNOR"
            );

            vm.startBroadcast();

            address votingPowerImpl = address(new VotingPowerAggregator());

            bytes memory votingPowerInitData = abi.encodeWithSignature(
                "initialize(address,address)",
                temporalGovernor,
                xWell
            );

            address votingPowerProxy = address(
                new TransparentUpgradeableProxy(
                    votingPowerImpl,
                    baseProxyAdmin,
                    votingPowerInitData
                )
            );

            // Add snapshot sources for Base
            // xWell is already handled via _getCustomVotes, so only add stkWell
            // All sources use timestamp-based snapshots
            VotingPowerAggregator(votingPowerProxy).addSnapshotSource(stkWell);

            vm.stopBroadcast();

            addresses.addAddress(
                "VOTING_POWER_AGGREGATOR_IMPL",
                votingPowerImpl
            );
            addresses.addAddress("VOTING_POWER_AGGREGATOR", votingPowerProxy);
        }

        // Deploy MultichainVoteCollectionV2 implementation on Base
        if (!addresses.isAddressSet("VOTE_COLLECTION_V2_IMPL", block.chainid)) {
            vm.startBroadcast();

            address voteCollectionV2Impl = address(
                new MultichainVoteCollectionV2()
            );

            vm.stopBroadcast();

            addresses.addAddress(
                "VOTE_COLLECTION_V2_IMPL",
                voteCollectionV2Impl
            );
        }

        // ============ OPTIMISM DEPLOYMENTS ============
        vm.selectFork(OPTIMISM_FORK_ID);

        // Deploy VotingPowerAggregator on Optimism
        if (!addresses.isAddressSet("VOTING_POWER_AGGREGATOR", block.chainid)) {
            address xWell = addresses.getAddress("xWELL_PROXY");
            address stkWell = addresses.getAddress("STK_GOVTOKEN_PROXY");
            address optimismProxyAdmin = addresses.getAddress(
                "MRD_PROXY_ADMIN"
            ); // TODO: correct?
            address temporalGovernor = addresses.getAddress(
                "TEMPORAL_GOVERNOR"
            );

            vm.startBroadcast();

            address votingPowerImpl = address(new VotingPowerAggregator());

            bytes memory votingPowerInitData = abi.encodeWithSignature(
                "initialize(address,address)",
                temporalGovernor,
                xWell
            );

            address votingPowerProxy = address(
                new TransparentUpgradeableProxy(
                    votingPowerImpl,
                    optimismProxyAdmin,
                    votingPowerInitData
                )
            );

            // Add snapshot sources for Optimism
            // xWell is already handled via _getCustomVotes, so only add stkWell
            // All sources use timestamp-based snapshots
            VotingPowerAggregator(votingPowerProxy).addSnapshotSource(stkWell);

            vm.stopBroadcast();

            addresses.addAddress(
                "VOTING_POWER_AGGREGATOR_IMPL",
                votingPowerImpl
            );
            addresses.addAddress("VOTING_POWER_AGGREGATOR", votingPowerProxy);
        }

        // Deploy MultichainVoteCollectionV2 implementation on Optimism
        if (!addresses.isAddressSet("VOTE_COLLECTION_V2_IMPL", block.chainid)) {
            vm.startBroadcast();

            address voteCollectionV2Impl = address(
                new MultichainVoteCollectionV2()
            );

            vm.stopBroadcast();

            addresses.addAddress(
                "VOTE_COLLECTION_V2_IMPL",
                voteCollectionV2Impl
            );
        }
    }

    function afterDeploy(Addresses addresses, address) public override {
        // Read proposal count from Moonbeam MultichainGovernor to continue the sequence
        vm.selectFork(MOONBEAM_FORK_ID);
        address moonbeamMultichainGovernor = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );
        uint256 startingProposalCount = MultichainGovernor(
            payable(moonbeamMultichainGovernor)
        ).proposalCount();

        console2.log(
            "Reading proposalCount from Moonbeam MultichainGovernor:",
            startingProposalCount
        );

        // Initialize MultichainGovernorV2 on Ethereum
        vm.selectFork(ETHEREUM_FORK_ID);

        address governorV2Proxy = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_V2_PROXY"
        );

        // Build InitializeData struct with proposal count from Moonbeam
        MultichainGovernorV2.InitializeData memory initData;
        initData.votingPower = addresses.getAddress("VOTING_POWER_AGGREGATOR");
        initData.proposalThreshold = PROPOSAL_THRESHOLD;
        initData.votingPeriodSeconds = VOTING_PERIOD_SECONDS;
        initData
            .crossChainVoteCollectionPeriod = CROSS_CHAIN_VOTE_COLLECTION_PERIOD;
        initData.quorum = QUORUM;
        initData.pauseDuration = PAUSE_DURATION;
        initData.startingProposalCount = uint128(startingProposalCount);
        initData.pauseGuardian = addresses.getAddress(
            "PAUSE_GUARDIAN_MULTISIG"
        );
        initData.breakGlassGuardian = addresses.getAddress(
            "BREAK_GLASS_GUARDIAN"
        );
        initData.wormholeCore = addresses.getAddress("WORMHOLE_CORE");

        // Build trusted senders array (vote collection contracts)
        WormholeTrustedSender.TrustedSender[]
            memory trustedSenders = new WormholeTrustedSender.TrustedSender[](
                3
            );

        // Moonbeam vote collection
        vm.selectFork(MOONBEAM_FORK_ID);
        address moonbeamVoteCollection = addresses.getAddress(
            "VOTE_COLLECTION_V2_PROXY"
        );
        uint16 moonbeamWormholeChainId = ChainIds.toMoonbeamWormholeChainId(
            block.chainid
        );

        trustedSenders[0] = WormholeTrustedSender.TrustedSender({
            chainId: moonbeamWormholeChainId,
            addr: moonbeamVoteCollection
        });

        // Base vote collection (existing, will be upgraded)
        vm.selectFork(BASE_FORK_ID);
        address baseVoteCollection = addresses.getAddress(
            "VOTE_COLLECTION_PROXY"
        );
        uint16 baseWormholeChainId = ChainIds.toBaseWormholeChainId(
            block.chainid
        );

        trustedSenders[1] = WormholeTrustedSender.TrustedSender({
            chainId: baseWormholeChainId,
            addr: baseVoteCollection
        });

        // Optimism vote collection (existing, will be upgraded)
        vm.selectFork(OPTIMISM_FORK_ID);
        address optimismVoteCollection = addresses.getAddress(
            "VOTE_COLLECTION_PROXY"
        );
        uint16 optimismWormholeChainId = ChainIds.toWormholeChainId(
            block.chainid
        );

        trustedSenders[2] = WormholeTrustedSender.TrustedSender({
            chainId: optimismWormholeChainId,
            addr: optimismVoteCollection
        });

        // Initialize governor on Ethereum
        vm.selectFork(ETHEREUM_FORK_ID);

        // TODO: determine whitelisted calldatas
        bytes[] memory whitelistedCalldatas = new bytes[](0);

        vm.startBroadcast();

        MultichainGovernorV2(payable(governorV2Proxy)).initialize(
            initData,
            trustedSenders,
            whitelistedCalldatas
        );

        vm.stopBroadcast();
    }

    function _buildMoonbeam(Addresses addresses) internal {
        console2.log("\n=== BUILDING MOONBEAM ACTIONS ===");
        vm.selectFork(MOONBEAM_FORK_ID);

        // 4. Upgrade MultichainGovernor on Moonbeam to latest version (with recoverETH())
        address moonbeamMultichainGovernor = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );
        address moonbeamProxyAdmin = addresses.getAddress(
            "MOONBEAM_PROXY_ADMIN"
        );

        vm.startBroadcast();
        address newMultichainGovernorImpl = address(new MultichainGovernor());
        vm.stopBroadcast();

        // NOTE: it's not v2 - it's the version with recoverETH()
        addresses.addAddress(
            "MULTICHAIN_GOVERNOR_V1_1_IMPL",
            newMultichainGovernorImpl
        );

        _pushAction(
            moonbeamProxyAdmin,
            abi.encodeWithSignature(
                "upgrade(address,address)",
                moonbeamMultichainGovernor,
                newMultichainGovernorImpl
            ),
            "Upgrade MultichainGovernor on Moonbeam to version with recoverETH()",
            ActionType.Moonbeam
        );
        console2.log(
            "[ACTION] Upgrade MultichainGovernor on Moonbeam to v1.1 (with recoverETH)"
        );

        // 5. Recover ETH from MultichainGovernor on Moonbeam
        address wellFoundationMultisig = addresses.getAddress(
            "WELL_FOUNDATION_MULTISIG"
        );

        _pushAction(
            moonbeamMultichainGovernor,
            abi.encodeWithSignature(
                "recoverETH(address)",
                payable(wellFoundationMultisig)
            ),
            "Recover ETH from MultichainGovernor on Moonbeam to WELL_FOUNDATION_MULTISIG",
            ActionType.Moonbeam
        );
        console2.log(
            "[ACTION] Recover ETH from MultichainGovernor to WELL_FOUNDATION_MULTISIG"
        );

        // 6. Transfer ownership of all contracts on Moonbeam owned by MultichainGovernor to TemporalGovernor
        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        console2.log(
            "[ACTION] Transferring ownership of Moonbeam contracts to TemporalGovernor..."
        );

        uint256 ownershipTransferCount = 0;

        // All 75 address names from 1284.json (Moonbeam)
        string[] memory moonbeamContracts = new string[](75);
        moonbeamContracts[0] = "mGLIMMER";
        moonbeamContracts[1] = "MGLIMMER_MULTISIG";
        moonbeamContracts[2] = "WELL_FOUNDATION_MULTISIG";
        moonbeamContracts[3] = "CURLY";
        moonbeamContracts[4] = "mETHwh";
        moonbeamContracts[5] = "WELL";
        moonbeamContracts[6] = "MULTICHAIN_GOVERNOR_PROXY";
        moonbeamContracts[7] = "MULTICHAIN_GOVERNOR_IMPL";
        moonbeamContracts[8] = "STELLASWAP_REWARDER";
        moonbeamContracts[9] = "DEPRECATED_MULTICHAIN_GOVERNOR_IMPL";
        moonbeamContracts[10] = "BREAK_GLASS_GUARDIAN";
        moonbeamContracts[11] = "ARTEMIS_GOVERNOR";
        moonbeamContracts[12] = "MOONBEAM_PROXY_ADMIN";
        moonbeamContracts[13] = "GOVTOKEN";
        moonbeamContracts[14] = "MOONBEAM_PAUSE_GUARDIAN_MULTISIG";
        moonbeamContracts[15] = "CHAINLINK_ORACLE";
        moonbeamContracts[16] = "MOONBEAM_TIMELOCK";
        moonbeamContracts[17] = "WORMHOLE_CORE";
        moonbeamContracts[18] = "WORMHOLE_BRIDGE_RELAYER_PROXY";
        moonbeamContracts[19] = "ECOSYSTEM_RESERVE_PROXY";
        moonbeamContracts[20] = "ECOSYSTEM_RESERVE_CONTROLLER";
        moonbeamContracts[21] = "UNITROLLER";
        moonbeamContracts[22] = "TOKENSALE";
        moonbeamContracts[23] = "MNATIVE";
        moonbeamContracts[24] = "GOVTOKEN_LP";
        moonbeamContracts[25] = "MOONWELL_VIEWS_IMPLEMENTATION";
        moonbeamContracts[26] = "MOONWELL_VIEWS_PROXY_ADMIN";
        moonbeamContracts[27] = "MOONWELL_VIEWS_PROXY";
        moonbeamContracts[28] = "xWELL_LOCKBOX";
        moonbeamContracts[29] = "WORMHOLE_BRIDGE_ADAPTER_PROXY";
        moonbeamContracts[30] = "WORMHOLE_BRIDGE_ADAPTER_LOGIC";
        moonbeamContracts[31] = "WORMHOLE_UNWRAPPER_ADAPTER";
        moonbeamContracts[32] = "xWELL_LOGIC";
        moonbeamContracts[33] = "xWELL_PROXY";
        moonbeamContracts[34] = "xWELL_ROUTER";
        moonbeamContracts[35] = "TOKEN_SALE_DISTRIBUTOR_PROXY";
        moonbeamContracts[36] = "TOKEN_SALE_DISTRIBUTOR_IMPL";
        moonbeamContracts[37] = "STK_GOVTOKEN_PROXY";
        moonbeamContracts[38] = "STK_GOVTOKEN_IMPL";
        moonbeamContracts[39] = "MOONWELL_mBUSD";
        moonbeamContracts[40] = "MOONWELL_mUSDC";
        moonbeamContracts[41] = "DEPRECATED_MOONWELL_mETH";
        moonbeamContracts[42] = "DEPRECATED_MOONWELL_mWBTC";
        moonbeamContracts[43] = "madUSDC";
        moonbeamContracts[44] = "madWETH";
        moonbeamContracts[45] = "madWBTC";
        moonbeamContracts[46] = "mxcDOT";
        moonbeamContracts[47] = "mxcUSDT";
        moonbeamContracts[48] = "JUMP_RATE_IRM_mxcUSDT";
        moonbeamContracts[49] = "mFRAX";
        moonbeamContracts[50] = "JUMP_RATE_IRM_mFRAX";
        moonbeamContracts[51] = "mxcUSDC";
        moonbeamContracts[52] = "JUMP_RATE_IRM_mxcUSDC";
        moonbeamContracts[53] = "mUSDCwh";
        moonbeamContracts[54] = "MOONWELL_mWBTC";
        moonbeamContracts[55] = "JUMP_RATE_IRM_mUSDCwh";
        moonbeamContracts[56] = "JUMP_RATE_IRM_mWBTCwh";
        moonbeamContracts[57] = "JUMP_RATE_IRM_mUSDCwh_MIP_M38";
        moonbeamContracts[58] = "JUMP_RATE_IRM_mFRAX_MIP_M38";
        moonbeamContracts[59] = "MOONWELL_mETH";
        moonbeamContracts[60] = "NOMAD_REALLOCATION_MULTISIG";
        moonbeamContracts[61] = "xcDOT";
        moonbeamContracts[62] = "xcUSDT";
        moonbeamContracts[63] = "xcUSDC";
        moonbeamContracts[64] = "MOONWELL_mFRAX";
        moonbeamContracts[65] = "MARKET_ADD_CHECKER";
        moonbeamContracts[66] = "API3_GLMR_USD_FEED";
        moonbeamContracts[67] = "API3_DOT_USD_FEED";
        moonbeamContracts[68] = "API3_FRAX_USD_FEED";
        moonbeamContracts[69] = "API3_USDT_USD_FEED";
        moonbeamContracts[70] = "API3_USDC_USD_FEED";
        moonbeamContracts[71] = "API3_ETH_USD_FEED";
        moonbeamContracts[72] = "API3_BTC_USD_FEED";
        moonbeamContracts[73] = "ANTHIAS_MULTISIG";
        moonbeamContracts[74] = "F-GLMR-DEVGRANT";

        // Loop through all contracts and transfer ownership if owned by MultichainGovernor
        for (uint256 i = 0; i < moonbeamContracts.length; i++) {
            // Check if contract address exists in addresses mapping
            if (!addresses.isAddressSet(moonbeamContracts[i])) {
                continue;
            }

            address contractAddress = addresses.getAddress(
                moonbeamContracts[i]
            );

            // Try to get the owner - if it fails, skip this contract
            try this._getOwner(contractAddress) returns (address owner) {
                // If owned by MultichainGovernor, transfer to TemporalGovernor
                if (owner == moonbeamMultichainGovernor) {
                    _pushAction(
                        contractAddress,
                        abi.encodeWithSignature(
                            "transferOwnership(address)",
                            temporalGovernor
                        ),
                        string(
                            abi.encodePacked(
                                "Transfer ",
                                moonbeamContracts[i],
                                " ownership to TemporalGovernor"
                            )
                        ),
                        ActionType.Moonbeam
                    );
                    console2.log(
                        "  [OWNERSHIP] Transfer %s ownership to TemporalGovernor",
                        moonbeamContracts[i]
                    );
                    ownershipTransferCount++;

                    // Track this contract for validation
                    contractsToValidateOwnership.push(moonbeamContracts[i]);
                }
            } catch {
                // Contract doesn't have owner() function or call failed, skip
                continue;
            }
        }

        console2.log(
            "[INFO] Queued %d ownership transfers on Moonbeam",
            ownershipTransferCount
        );
        console2.log("=== MOONBEAM ACTIONS BUILD COMPLETE ===\n");
    }

    function _buildBase(
        Addresses addresses,
        address ethereumGovernorV2
    ) internal {
        console2.log("\n=== BUILDING BASE ACTIONS ===");
        vm.selectFork(BASE_FORK_ID);

        uint16 ethereumWormholeChainId = ChainIds.toEthereumWormholeChainId(
            block.chainid
        );

        // 7. Upgrade MultichainVoteCollection to V2 on Base
        address baseVoteCollectionProxy = addresses.getAddress(
            "VOTE_COLLECTION_PROXY"
        );
        address baseVoteCollectionV2Impl = addresses.getAddress(
            "VOTE_COLLECTION_V2_IMPL"
        );
        address baseProxyAdmin = addresses.getAddress("PROXY_ADMIN");
        address baseVotingPowerAggregator = addresses.getAddress(
            "VOTING_POWER_AGGREGATOR"
        );

        _pushAction(
            baseProxyAdmin,
            abi.encodeWithSignature(
                "upgrade(address,address)",
                baseVoteCollectionProxy,
                baseVoteCollectionV2Impl
            ),
            "Upgrade MultichainVoteCollection to V2 on Base",
            ActionType.Base
        );
        console2.log("[ACTION] Upgrade MultichainVoteCollection to V2 on Base");

        // Call initializeV2 on Base VoteCollection - set VotingPowerAggregator and add new Ethereum governor
        // Old Moonbeam governor is hardcoded and will be removed automatically
        _pushAction(
            baseVoteCollectionProxy,
            abi.encodeWithSignature(
                "initializeV2(address,uint16,address)",
                baseVotingPowerAggregator,
                ethereumWormholeChainId,
                ethereumGovernorV2
            ),
            "Initialize V2: set VotingPowerAggregator, remove old Moonbeam governor, add Ethereum governor on Base VoteCollection",
            ActionType.Base
        );
        console2.log("[ACTION] Call initializeV2 on Base VoteCollection:");
        console2.log("  - Set VotingPowerAggregator");
        console2.log("  - Remove old Moonbeam governor as trusted sender");
        console2.log("  - Add Ethereum governor as trusted sender");

        // Get Base TemporalGovernor address
        address baseTemporalGovernor = addresses.getAddress(
            "TEMPORAL_GOVERNOR"
        );

        // Add new Ethereum MultichainGovernorV2 as trusted sender on Base TemporalGovernor
        ITemporalGovernor.TrustedSender[]
            memory trustedSendersToAdd = new ITemporalGovernor.TrustedSender[](
                1
            );
        trustedSendersToAdd[0] = ITemporalGovernor.TrustedSender({
            chainId: ethereumWormholeChainId,
            addr: ethereumGovernorV2
        });

        _pushAction(
            baseTemporalGovernor,
            abi.encodeWithSignature(
                "setTrustedSenders((uint16,address)[])",
                trustedSendersToAdd
            ),
            "Add Ethereum MultichainGovernorV2 as trusted sender on Base TemporalGovernor",
            ActionType.Base
        );
        console2.log(
            "[ACTION] Add Ethereum MultichainGovernorV2 as trusted sender on Base TemporalGovernor"
        );

        // Remove old Moonbeam MultichainGovernor as trusted sender from Base TemporalGovernor
        vm.selectFork(MOONBEAM_FORK_ID);
        address moonbeamMultichainGovernor = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );
        vm.selectFork(BASE_FORK_ID);
        uint16 moonbeamWormholeChainId = ChainIds.toMoonbeamWormholeChainId(
            block.chainid
        );
        ITemporalGovernor.TrustedSender[]
            memory trustedSendersToRemove = new ITemporalGovernor.TrustedSender[](
                1
            );
        trustedSendersToRemove[0] = ITemporalGovernor.TrustedSender({
            chainId: moonbeamWormholeChainId,
            addr: moonbeamMultichainGovernor
        });

        _pushAction(
            baseTemporalGovernor,
            abi.encodeWithSignature(
                "unSetTrustedSenders((uint16,address)[])",
                trustedSendersToRemove
            ),
            "Remove Moonbeam MultichainGovernor as trusted sender from Base TemporalGovernor",
            ActionType.Base
        );
        console2.log(
            "[ACTION] Remove Moonbeam MultichainGovernor as trusted sender from Base TemporalGovernor"
        );

        console2.log("=== BASE ACTIONS BUILD COMPLETE ===\n");
    }

    function _buildOptimism(
        Addresses addresses,
        address ethereumGovernorV2
    ) internal {
        console2.log("\n=== BUILDING OPTIMISM ACTIONS ===");
        vm.selectFork(OPTIMISM_FORK_ID);

        uint16 ethereumWormholeChainId = ChainIds.toEthereumWormholeChainId(
            block.chainid
        );

        // 7. Upgrade MultichainVoteCollection to V2 on Optimism
        address optimismVoteCollectionProxy = addresses.getAddress(
            "VOTE_COLLECTION_PROXY"
        );
        address optimismVoteCollectionV2Impl = addresses.getAddress(
            "VOTE_COLLECTION_V2_IMPL"
        );
        address optimismProxyAdmin = addresses.getAddress("PROXY_ADMIN");
        address optimismVotingPowerAggregator = addresses.getAddress(
            "VOTING_POWER_AGGREGATOR"
        );

        _pushAction(
            optimismProxyAdmin,
            abi.encodeWithSignature(
                "upgrade(address,address)",
                optimismVoteCollectionProxy,
                optimismVoteCollectionV2Impl
            ),
            "Upgrade MultichainVoteCollection to V2 on Optimism",
            ActionType.Optimism
        );
        console2.log(
            "[ACTION] Upgrade MultichainVoteCollection to V2 on Optimism"
        );

        // Call initializeV2 on Optimism VoteCollection - set VotingPowerAggregator and add new Ethereum governor
        // Old Moonbeam governor is hardcoded and will be removed automatically
        _pushAction(
            optimismVoteCollectionProxy,
            abi.encodeWithSignature(
                "initializeV2(address,uint16,address)",
                optimismVotingPowerAggregator,
                ethereumWormholeChainId,
                ethereumGovernorV2
            ),
            "Initialize V2: set VotingPowerAggregator, remove old Moonbeam governor, add Ethereum governor on Optimism VoteCollection",
            ActionType.Optimism
        );
        console2.log("[ACTION] Call initializeV2 on Optimism VoteCollection:");
        console2.log("  - Set VotingPowerAggregator");
        console2.log("  - Remove old Moonbeam governor as trusted sender");
        console2.log("  - Add Ethereum governor as trusted sender");

        // Get Optimism TemporalGovernor address
        address optimismTemporalGovernor = addresses.getAddress(
            "TEMPORAL_GOVERNOR"
        );

        // Add new Ethereum MultichainGovernorV2 as trusted sender on Optimism TemporalGovernor
        ITemporalGovernor.TrustedSender[]
            memory trustedSendersToAdd = new ITemporalGovernor.TrustedSender[](
                1
            );
        trustedSendersToAdd[0] = ITemporalGovernor.TrustedSender({
            chainId: ethereumWormholeChainId,
            addr: ethereumGovernorV2
        });

        _pushAction(
            optimismTemporalGovernor,
            abi.encodeWithSignature(
                "setTrustedSenders((uint16,address)[])",
                trustedSendersToAdd
            ),
            "Add Ethereum MultichainGovernorV2 as trusted sender on Optimism TemporalGovernor",
            ActionType.Optimism
        );
        console2.log(
            "[ACTION] Add Ethereum MultichainGovernorV2 as trusted sender on Optimism TemporalGovernor"
        );

        // Remove old Moonbeam MultichainGovernor as trusted sender from Optimism TemporalGovernor
        vm.selectFork(MOONBEAM_FORK_ID);
        address moonbeamMultichainGovernor = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );
        vm.selectFork(OPTIMISM_FORK_ID);
        uint16 moonbeamWormholeChainId = ChainIds.toMoonbeamWormholeChainId(
            block.chainid
        );
        ITemporalGovernor.TrustedSender[]
            memory trustedSendersToRemove = new ITemporalGovernor.TrustedSender[](
                1
            );
        trustedSendersToRemove[0] = ITemporalGovernor.TrustedSender({
            chainId: moonbeamWormholeChainId,
            addr: moonbeamMultichainGovernor
        });

        _pushAction(
            optimismTemporalGovernor,
            abi.encodeWithSignature(
                "unSetTrustedSenders((uint16,address)[])",
                trustedSendersToRemove
            ),
            "Remove Moonbeam MultichainGovernor as trusted sender from Optimism TemporalGovernor",
            ActionType.Optimism
        );
        console2.log(
            "[ACTION] Remove Moonbeam MultichainGovernor as trusted sender from Optimism TemporalGovernor"
        );

        console2.log("=== OPTIMISM ACTIONS BUILD COMPLETE ===\n");
    }

    function build(Addresses addresses) public override {
        // Build Moonbeam actions
        _buildMoonbeam(addresses);

        // Get Ethereum governor info for Base and Optimism
        vm.selectFork(ETHEREUM_FORK_ID);
        address ethereumGovernorV2 = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_V2_PROXY"
        );

        // Build Base and Optimism actions
        _buildBase(addresses, ethereumGovernorV2);
        _buildOptimism(addresses, ethereumGovernorV2);
    }

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice Helper function to get owner of a contract
    /// @param contractAddress The address of the contract to check
    /// @return owner The owner address
    function _getOwner(
        address contractAddress
    ) external view returns (address owner) {
        (bool success, bytes memory data) = contractAddress.staticcall(
            abi.encodeWithSignature("owner()")
        );
        require(success && data.length >= 32, "Failed to get owner");
        owner = abi.decode(data, (address));
    }

    /// @notice Helper function to validate all ownership transfers
    /// @param addresses The addresses contract
    /// @param temporalGovernor The temporal governor address
    /// @return success Whether all ownership transfers were validated successfully
    function _validateAllOwnershipTransfers(
        Addresses addresses,
        address temporalGovernor
    ) internal view returns (bool success) {
        console2.log(
            "[INFO] Validating ownership transfer for %d contracts...",
            contractsToValidateOwnership.length
        );

        uint256 validatedCount = 0;
        uint256 failedCount = 0;

        for (uint256 i = 0; i < contractsToValidateOwnership.length; i++) {
            string memory contractName = contractsToValidateOwnership[i];
            address contractAddress = addresses.getAddress(contractName);

            try this._getOwner(contractAddress) returns (address currentOwner) {
                if (currentOwner == temporalGovernor) {
                    console2.log(
                        "[PASS] %s ownership transferred to TemporalGovernor",
                        contractName
                    );
                    validatedCount++;
                } else {
                    console2.log(
                        "[FAIL] %s ownership NOT transferred (current owner: %s)",
                        contractName,
                        currentOwner
                    );
                    failedCount++;
                }
            } catch {
                console2.log(
                    "[ERROR] Failed to get owner for %s",
                    contractName
                );
                failedCount++;
            }
        }

        console2.log(
            "[INFO] Ownership validation complete: %d passed, %d failed",
            validatedCount,
            failedCount
        );

        // All contracts that were queued for ownership transfer MUST have been transferred
        assertEq(
            failedCount,
            0,
            "Some contracts failed ownership transfer validation"
        );
        assertEq(
            validatedCount,
            contractsToValidateOwnership.length,
            "Not all contracts had ownership transferred"
        );
        assertGt(
            validatedCount,
            0,
            "No contracts had ownership transferred to TemporalGovernor"
        );

        return true;
    }

    function _validateEthereum(Addresses addresses) internal {
        console2.log("\n=== VALIDATING ETHEREUM DEPLOYMENT ===");
        vm.selectFork(ETHEREUM_FORK_ID);

        // 1. Validate MultichainGovernorV2 proxy is deployed
        address governorV2Proxy = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_V2_PROXY"
        );
        assertGt(
            governorV2Proxy.code.length,
            0,
            "MultichainGovernorV2 proxy not deployed on Ethereum"
        );
        console2.log(
            "[PASS] MultichainGovernorV2 proxy deployed at:",
            governorV2Proxy
        );

        // 2. Validate MultichainGovernorV2 implementation is deployed
        address governorV2Impl = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_V2_IMPL"
        );
        assertGt(
            governorV2Impl.code.length,
            0,
            "MultichainGovernorV2 implementation not deployed on Ethereum"
        );
        console2.log(
            "[PASS] MultichainGovernorV2 implementation deployed at:",
            governorV2Impl
        );

        // 3. Validate VotingPowerAggregator is deployed on Ethereum
        address ethereumVotingPower = addresses.getAddress(
            "VOTING_POWER_AGGREGATOR"
        );
        assertGt(
            ethereumVotingPower.code.length,
            0,
            "VotingPowerAggregator not deployed on Ethereum"
        );
        console2.log(
            "[PASS] VotingPowerAggregator deployed at:",
            ethereumVotingPower
        );

        // 4. Validate governor is initialized correctly
        MultichainGovernorV2 governor = MultichainGovernorV2(
            payable(governorV2Proxy)
        );
        assertEq(
            address(governor.votingPower()),
            ethereumVotingPower,
            "MultichainGovernorV2 votingPower not set correctly"
        );
        console2.log("[PASS] MultichainGovernorV2 votingPower set correctly");

        // 5. Validate proposal count matches Moonbeam
        vm.selectFork(MOONBEAM_FORK_ID);
        address moonbeamMultichainGovernor = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );
        uint256 expectedProposalCount = MultichainGovernor(
            payable(moonbeamMultichainGovernor)
        ).proposalCount();

        vm.selectFork(ETHEREUM_FORK_ID);
        assertEq(
            governor.proposalCount(),
            expectedProposalCount,
            "MultichainGovernorV2 proposalCount not initialized correctly from Moonbeam"
        );
        console2.log(
            "[PASS] MultichainGovernorV2 proposalCount initialized correctly:",
            expectedProposalCount
        );

        // 6. Validate trusted senders are set correctly (Moonbeam, Base, Optimism VoteCollections)
        vm.selectFork(MOONBEAM_FORK_ID);
        address moonbeamVoteCollection = addresses.getAddress(
            "VOTE_COLLECTION_V2_PROXY"
        );
        uint16 moonbeamWormholeChainId = ChainIds.toMoonbeamWormholeChainId(
            block.chainid
        );

        vm.selectFork(BASE_FORK_ID);
        address baseVoteCollection = addresses.getAddress(
            "VOTE_COLLECTION_PROXY"
        );
        uint16 baseWormholeChainId = ChainIds.toBaseWormholeChainId(
            block.chainid
        );

        vm.selectFork(OPTIMISM_FORK_ID);
        address optimismVoteCollection = addresses.getAddress(
            "VOTE_COLLECTION_PROXY"
        );
        uint16 optimismWormholeChainId = ChainIds.toWormholeChainId(
            block.chainid
        );

        vm.selectFork(ETHEREUM_FORK_ID);
        assertTrue(
            governor.isTrustedSender(
                moonbeamWormholeChainId,
                moonbeamVoteCollection
            ),
            "Moonbeam VoteCollection not trusted sender on MultichainGovernorV2"
        );
        console2.log("[PASS] Moonbeam VoteCollection is trusted sender");

        assertTrue(
            governor.isTrustedSender(baseWormholeChainId, baseVoteCollection),
            "Base VoteCollection not trusted sender on MultichainGovernorV2"
        );
        console2.log("[PASS] Base VoteCollection is trusted sender");

        assertTrue(
            governor.isTrustedSender(
                optimismWormholeChainId,
                optimismVoteCollection
            ),
            "Optimism VoteCollection not trusted sender on MultichainGovernorV2"
        );
        console2.log("[PASS] Optimism VoteCollection is trusted sender");

        // 7. Validate governance parameters
        assertEq(
            governor.proposalThreshold(),
            PROPOSAL_THRESHOLD,
            "Proposal threshold not set correctly"
        );
        console2.log(
            "[PASS] Proposal threshold set correctly:",
            PROPOSAL_THRESHOLD
        );

        assertEq(
            governor.votingPeriod(),
            VOTING_PERIOD_SECONDS,
            "Voting period not set correctly"
        );
        console2.log(
            "[PASS] Voting period set correctly:",
            VOTING_PERIOD_SECONDS
        );

        assertEq(
            governor.crossChainVoteCollectionPeriod(),
            CROSS_CHAIN_VOTE_COLLECTION_PERIOD,
            "Cross chain vote collection period not set correctly"
        );
        console2.log(
            "[PASS] Cross chain vote collection period set correctly:",
            CROSS_CHAIN_VOTE_COLLECTION_PERIOD
        );

        assertEq(governor.quorum(), QUORUM, "Quorum not set correctly");
        console2.log("[PASS] Quorum set correctly:", QUORUM);

        console2.log("=== ETHEREUM VALIDATION COMPLETE ===\n");
    }

    function _validateMoonbeam(Addresses addresses) internal {
        console2.log("\n=== VALIDATING MOONBEAM DEPLOYMENT & ACTIONS ===");
        vm.selectFork(MOONBEAM_FORK_ID);

        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        address moonbeamMultichainGovernor = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );

        // 1. Validate TemporalGovernor is deployed
        assertGt(
            temporalGovernor.code.length,
            0,
            "TemporalGovernor not deployed on Moonbeam"
        );
        console2.log("[PASS] TemporalGovernor deployed at:", temporalGovernor);

        // 2. Validate VotingPowerAggregator is deployed on Moonbeam
        address moonbeamVotingPower = addresses.getAddress(
            "VOTING_POWER_AGGREGATOR"
        );
        assertGt(
            moonbeamVotingPower.code.length,
            0,
            "VotingPowerAggregator not deployed on Moonbeam"
        );
        console2.log(
            "[PASS] VotingPowerAggregator deployed at:",
            moonbeamVotingPower
        );

        // 3. Validate MultichainVoteCollectionMoonbeam is deployed on Moonbeam
        address moonbeamVoteCollectionV2 = addresses.getAddress(
            "VOTE_COLLECTION_V2_PROXY"
        );
        assertGt(
            moonbeamVoteCollectionV2.code.length,
            0,
            "MultichainVoteCollectionMoonbeam not deployed on Moonbeam"
        );
        console2.log(
            "[PASS] MultichainVoteCollectionMoonbeam deployed at:",
            moonbeamVoteCollectionV2
        );

        // 4. Validate MultichainVoteCollectionMoonbeam has correct votingPower
        MultichainVoteCollectionMoonbeam voteCollection = MultichainVoteCollectionMoonbeam(
                moonbeamVoteCollectionV2
            );
        assertEq(
            address(voteCollection.votingPower()),
            moonbeamVotingPower,
            "VotingPowerAggregator not set on Moonbeam VoteCollection"
        );
        console2.log(
            "[PASS] VotingPowerAggregator set correctly on VoteCollection"
        );

        // 5. Validate MultichainVoteCollectionMoonbeam has Ethereum governor as trusted sender
        vm.selectFork(ETHEREUM_FORK_ID);
        address ethereumGovernorV2 = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_V2_PROXY"
        );
        uint16 ethereumWormholeChainId = ChainIds.toEthereumWormholeChainId(
            block.chainid
        );

        vm.selectFork(MOONBEAM_FORK_ID);
        assertTrue(
            voteCollection.isTrustedSender(
                ethereumWormholeChainId,
                ethereumGovernorV2
            ),
            "Ethereum MultichainGovernorV2 not trusted sender on Moonbeam VoteCollection"
        );
        console2.log(
            "[PASS] Ethereum MultichainGovernorV2 is trusted sender on Moonbeam VoteCollection"
        );

        // 6. Validate MultichainGovernor was upgraded to v1.1 (with recoverETH)
        address newMultichainGovernorImpl = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_V1_1_IMPL"
        );
        address moonbeamProxyAdmin = addresses.getAddress(
            "MOONBEAM_PROXY_ADMIN"
        );

        address currentImpl = ProxyAdmin(moonbeamProxyAdmin)
            .getProxyImplementation(
                ITransparentUpgradeableProxy(
                    payable(moonbeamMultichainGovernor)
                )
            );
        assertEq(
            currentImpl,
            newMultichainGovernorImpl,
            "MultichainGovernor not upgraded on Moonbeam"
        );
        console2.log("[PASS] MultichainGovernor upgraded to v1.1 on Moonbeam");

        // 7. Validate ETH was recovered from MultichainGovernor
        uint256 governorBalance = moonbeamMultichainGovernor.balance;
        assertEq(
            governorBalance,
            0,
            "ETH not recovered from MultichainGovernor"
        );
        console2.log(
            "[PASS] ETH recovered from MultichainGovernor (balance = 0)"
        );

        // 8. Validate ProxyAdmin ownership transferred to TemporalGovernor
        assertEq(
            ProxyAdmin(moonbeamProxyAdmin).owner(),
            temporalGovernor,
            "MOONBEAM_PROXY_ADMIN ownership not transferred"
        );
        console2.log(
            "[PASS] MOONBEAM_PROXY_ADMIN ownership transferred to TemporalGovernor"
        );

        // 9. Validate ALL contract ownerships that were transferred to TemporalGovernor
        assertTrue(
            _validateAllOwnershipTransfers(addresses, temporalGovernor),
            "Ownership transfer validation failed"
        );

        console2.log("=== MOONBEAM VALIDATION COMPLETE ===\n");
    }

    function _validateBase(
        Addresses addresses,
        address governorV2Proxy
    ) internal {
        console2.log("\n=== VALIDATING BASE DEPLOYMENT & ACTIONS ===");
        vm.selectFork(BASE_FORK_ID);

        uint16 ethereumWormholeChainId = ChainIds.toEthereumWormholeChainId(
            block.chainid
        );

        // 1. Validate VotingPowerAggregator is deployed on Base
        address baseVotingPower = addresses.getAddress(
            "VOTING_POWER_AGGREGATOR"
        );
        assertGt(
            baseVotingPower.code.length,
            0,
            "VotingPowerAggregator not deployed on Base"
        );
        console2.log(
            "[PASS] VotingPowerAggregator deployed at:",
            baseVotingPower
        );

        // 2. Validate MultichainVoteCollectionV2 implementation is deployed on Base
        address baseVoteCollectionV2Impl = addresses.getAddress(
            "VOTE_COLLECTION_V2_IMPL"
        );
        assertGt(
            baseVoteCollectionV2Impl.code.length,
            0,
            "MultichainVoteCollectionV2 implementation not deployed on Base"
        );
        console2.log(
            "[PASS] MultichainVoteCollectionV2 implementation deployed at:",
            baseVoteCollectionV2Impl
        );

        // 3. Validate MultichainVoteCollection was upgraded to V2 on Base
        address baseVoteCollectionProxy = addresses.getAddress(
            "VOTE_COLLECTION_PROXY"
        );
        address baseProxyAdmin = addresses.getAddress("PROXY_ADMIN");

        address baseCurrentImpl = ProxyAdmin(baseProxyAdmin)
            .getProxyImplementation(
                ITransparentUpgradeableProxy(payable(baseVoteCollectionProxy))
            );
        assertEq(
            baseCurrentImpl,
            baseVoteCollectionV2Impl,
            "MultichainVoteCollection not upgraded to V2 on Base"
        );
        console2.log("[PASS] MultichainVoteCollection upgraded to V2 on Base");

        // 4. Validate VotingPowerAggregator is set on Base VoteCollection
        MultichainVoteCollectionV2 baseVoteCollection = MultichainVoteCollectionV2(
                baseVoteCollectionProxy
            );
        assertEq(
            address(baseVoteCollection.votingPower()),
            baseVotingPower,
            "VotingPowerAggregator not set on Base VoteCollection"
        );
        console2.log(
            "[PASS] VotingPowerAggregator set correctly on Base VoteCollection"
        );

        // 5. Validate Ethereum MultichainGovernorV2 is trusted sender on Base VoteCollection
        assertTrue(
            baseVoteCollection.isTrustedSender(
                ethereumWormholeChainId,
                governorV2Proxy
            ),
            "MultichainGovernorV2 not trusted sender on Base VoteCollection"
        );
        console2.log(
            "[PASS] Ethereum MultichainGovernorV2 is trusted sender on Base VoteCollection"
        );

        // 6. Validate old Moonbeam MultichainGovernor is NOT trusted sender anymore on Base VoteCollection
        vm.selectFork(MOONBEAM_FORK_ID);
        address moonbeamMultichainGovernor = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );
        uint16 moonbeamWormholeChainId = ChainIds.toMoonbeamWormholeChainId(
            block.chainid
        );

        vm.selectFork(BASE_FORK_ID);
        assertFalse(
            baseVoteCollection.isTrustedSender(
                moonbeamWormholeChainId,
                moonbeamMultichainGovernor
            ),
            "Moonbeam MultichainGovernor still trusted sender on Base VoteCollection"
        );
        console2.log(
            "[PASS] Old Moonbeam MultichainGovernor removed as trusted sender on Base VoteCollection"
        );

        // 7. Validate Ethereum MultichainGovernorV2 is trusted sender on Base TemporalGovernor
        address baseTemporalGovernor = addresses.getAddress(
            "TEMPORAL_GOVERNOR"
        );
        TemporalGovernor temporalGov = TemporalGovernor(
            payable(baseTemporalGovernor)
        );

        assertTrue(
            temporalGov.isTrustedSender(
                ethereumWormholeChainId,
                governorV2Proxy
            ),
            "Ethereum MultichainGovernorV2 not trusted sender on Base TemporalGovernor"
        );
        console2.log(
            "[PASS] Ethereum MultichainGovernorV2 is trusted sender on Base TemporalGovernor"
        );

        // 8. Validate old Moonbeam MultichainGovernor is NOT trusted sender on Base TemporalGovernor
        assertFalse(
            temporalGov.isTrustedSender(
                moonbeamWormholeChainId,
                moonbeamMultichainGovernor
            ),
            "Moonbeam MultichainGovernor still trusted sender on Base TemporalGovernor"
        );
        console2.log(
            "[PASS] Old Moonbeam MultichainGovernor removed as trusted sender on Base TemporalGovernor"
        );

        console2.log("=== BASE VALIDATION COMPLETE ===\n");
    }

    function _validateOptimism(
        Addresses addresses,
        address governorV2Proxy
    ) internal {
        console2.log("\n=== VALIDATING OPTIMISM DEPLOYMENT & ACTIONS ===");
        vm.selectFork(OPTIMISM_FORK_ID);

        uint16 ethereumWormholeChainId = ChainIds.toEthereumWormholeChainId(
            block.chainid
        );

        // 1. Validate VotingPowerAggregator is deployed on Optimism
        address optimismVotingPower = addresses.getAddress(
            "VOTING_POWER_AGGREGATOR"
        );
        assertGt(
            optimismVotingPower.code.length,
            0,
            "VotingPowerAggregator not deployed on Optimism"
        );
        console2.log(
            "[PASS] VotingPowerAggregator deployed at:",
            optimismVotingPower
        );

        // 2. Validate MultichainVoteCollectionV2 implementation is deployed on Optimism
        address optimismVoteCollectionV2Impl = addresses.getAddress(
            "VOTE_COLLECTION_V2_IMPL"
        );
        assertGt(
            optimismVoteCollectionV2Impl.code.length,
            0,
            "MultichainVoteCollectionV2 implementation not deployed on Optimism"
        );
        console2.log(
            "[PASS] MultichainVoteCollectionV2 implementation deployed at:",
            optimismVoteCollectionV2Impl
        );

        // 3. Validate MultichainVoteCollection was upgraded to V2 on Optimism
        address optimismVoteCollectionProxy = addresses.getAddress(
            "VOTE_COLLECTION_PROXY"
        );
        address optimismProxyAdmin = addresses.getAddress("PROXY_ADMIN");

        address optimismCurrentImpl = ProxyAdmin(optimismProxyAdmin)
            .getProxyImplementation(
                ITransparentUpgradeableProxy(
                    payable(optimismVoteCollectionProxy)
                )
            );
        assertEq(
            optimismCurrentImpl,
            optimismVoteCollectionV2Impl,
            "MultichainVoteCollection not upgraded to V2 on Optimism"
        );
        console2.log(
            "[PASS] MultichainVoteCollection upgraded to V2 on Optimism"
        );

        // 4. Validate VotingPowerAggregator is set on Optimism VoteCollection
        MultichainVoteCollectionV2 optimismVoteCollection = MultichainVoteCollectionV2(
                optimismVoteCollectionProxy
            );
        assertEq(
            address(optimismVoteCollection.votingPower()),
            optimismVotingPower,
            "VotingPowerAggregator not set on Optimism VoteCollection"
        );
        console2.log(
            "[PASS] VotingPowerAggregator set correctly on Optimism VoteCollection"
        );

        // 5. Validate Ethereum MultichainGovernorV2 is trusted sender on Optimism VoteCollection
        assertTrue(
            optimismVoteCollection.isTrustedSender(
                ethereumWormholeChainId,
                governorV2Proxy
            ),
            "MultichainGovernorV2 not trusted sender on Optimism VoteCollection"
        );
        console2.log(
            "[PASS] Ethereum MultichainGovernorV2 is trusted sender on Optimism VoteCollection"
        );

        // 6. Validate old Moonbeam MultichainGovernor is NOT trusted sender anymore on Optimism VoteCollection
        vm.selectFork(MOONBEAM_FORK_ID);
        address moonbeamMultichainGovernor = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );
        uint16 moonbeamWormholeChainId = ChainIds.toMoonbeamWormholeChainId(
            block.chainid
        );

        vm.selectFork(OPTIMISM_FORK_ID);
        assertFalse(
            optimismVoteCollection.isTrustedSender(
                moonbeamWormholeChainId,
                moonbeamMultichainGovernor
            ),
            "Moonbeam MultichainGovernor still trusted sender on Optimism VoteCollection"
        );
        console2.log(
            "[PASS] Old Moonbeam MultichainGovernor removed as trusted sender on Optimism VoteCollection"
        );

        // 7. Validate Ethereum MultichainGovernorV2 is trusted sender on Optimism TemporalGovernor
        address optimismTemporalGovernor = addresses.getAddress(
            "TEMPORAL_GOVERNOR"
        );
        TemporalGovernor temporalGov = TemporalGovernor(
            payable(optimismTemporalGovernor)
        );

        assertTrue(
            temporalGov.isTrustedSender(
                ethereumWormholeChainId,
                governorV2Proxy
            ),
            "Ethereum MultichainGovernorV2 not trusted sender on Optimism TemporalGovernor"
        );
        console2.log(
            "[PASS] Ethereum MultichainGovernorV2 is trusted sender on Optimism TemporalGovernor"
        );

        // 8. Validate old Moonbeam MultichainGovernor is NOT trusted sender on Optimism TemporalGovernor
        assertFalse(
            temporalGov.isTrustedSender(
                moonbeamWormholeChainId,
                moonbeamMultichainGovernor
            ),
            "Moonbeam MultichainGovernor still trusted sender on Optimism TemporalGovernor"
        );
        console2.log(
            "[PASS] Old Moonbeam MultichainGovernor removed as trusted sender on Optimism TemporalGovernor"
        );

        console2.log("=== OPTIMISM VALIDATION COMPLETE ===\n");
    }

    function validate(Addresses addresses, address) public override {
        console2.log("\n");
        console2.log(
            "================================================================================"
        );
        console2.log(
            "==================== MIP-X41 COMPREHENSIVE VALIDATION =========================="
        );
        console2.log(
            "================================================================================"
        );
        console2.log("\n");

        // Validate Ethereum deployment
        _validateEthereum(addresses);

        // Validate Moonbeam deployment and actions
        _validateMoonbeam(addresses);

        // Get Ethereum governor info for Base and Optimism validation
        vm.selectFork(ETHEREUM_FORK_ID);
        address governorV2Proxy = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_V2_PROXY"
        );

        // Validate Base deployment and actions
        _validateBase(addresses, governorV2Proxy);

        // Validate Optimism deployment and actions
        _validateOptimism(addresses, governorV2Proxy);

        console2.log("\n");
        console2.log(
            "================================================================================"
        );
        console2.log(
            "==================== ALL VALIDATIONS PASSED ===================================="
        );
        console2.log(
            "================================================================================"
        );
        console2.log("\n");
    }
}
