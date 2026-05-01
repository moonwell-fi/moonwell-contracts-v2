//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {MultichainGovernorV2} from "@protocol/governance/multichain/MultichainGovernorV2.sol";
import {ProposalView} from "@protocol/views/ProposalView.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {ITemporalGovernor} from "@protocol/governance/ITemporalGovernor.sol";
import {VotingPowerAggregator} from "@protocol/governance/multichain/VotingPowerAggregator.sol";
import {MultichainVoteCollectionV2} from "@protocol/governance/multichain/MultichainVoteCollectionV2.sol";
import {MultichainVoteCollectionMoonbeam} from "@protocol/governance/multichain/MultichainVoteCollectionMoonbeam.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";

import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID, ETHEREUM_FORK_ID, ETHEREUM_WORMHOLE_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID, BASE_WORMHOLE_CHAIN_ID, OPTIMISM_WORMHOLE_CHAIN_ID} from "@utils/ChainIds.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {ChainIds} from "@utils/ChainIds.sol";

/// @title MIP-X52: MultichainGovernorV2 Migration to Ethereum Mainnet
/// @author Moonwell Contributors
/// @notice Proposal to migrate Moonwell governance from Moonbeam to Ethereum by:
///
///         DEPLOYMENT PHASE:
///         1. Deploy MultichainGovernorV2 and VotingPowerAggregator on Ethereum
///         2. Deploy TemporalGovernor, VotingPowerAggregator, and MultichainVoteCollectionMoonbeam on Moonbeam
///         3. Deploy VotingPowerAggregator and MultichainVoteCollectionV2 implementation on Base and Optimism
///
///         POST-DEPLOYMENT CONFIGURATION (by deployer):
///         4. Initialize MultichainGovernorV2 on Ethereum with proposal count from Moonbeam + 1
///         5. Configure Ethereum VotingPowerAggregator (addSnapshotSource, transfer ownership to governor)
///
///         MOONBEAM ACTIONS (executed by old MultichainGovernor):
///         6. Upgrade Moonbeam MultichainGovernor to v1.1 (adds recoverETH function)
///         7. Recover stuck ETH from MultichainGovernor to WELL_FOUNDATION_MULTISIG
///         8. Add stkWell as snapshot source to Moonbeam VotingPowerAggregator
///         9. Transfer Moonbeam VotingPowerAggregator ownership to TemporalGovernor
///         10. Transfer ownership of all contracts owned by MultichainGovernor to TemporalGovernor
///
///         BASE ACTIONS (executed by Base TemporalGovernor via cross-chain message):
///         11. Upgrade MultichainVoteCollection to V2 on Base
///         12. Initialize V2 (set VotingPowerAggregator, remove old Moonbeam governor, add Ethereum governor)
///         13. Add stkWell as snapshot source to Base VotingPowerAggregator
///         14. Add Ethereum MultichainGovernorV2 as trusted sender on Base TemporalGovernor
///         15. Remove Moonbeam MultichainGovernor as trusted sender from Base TemporalGovernor
///
///         OPTIMISM ACTIONS (executed by Optimism TemporalGovernor via cross-chain message):
///         16. Same as Base actions (11-15) but on Optimism
///
///         Note: All VotingPowerAggregators use timestamp-based voting (no block numbers)
///         and only aggregate voting power from xWell + stkWell (no well/distributor).
contract mipx52 is HybridProposal {
    using ProposalActions for *;
    using ChainIds for uint256;

    string public constant override name = "MIP-X52";

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
            vm.readFile("./proposals/mips/mip-x52/x52.md")
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
        if (DO_RUN) simulate(addresses, deployerAddress);
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

        address ethereumProxyAdmin;

        // 1. Deploy MultichainGovernorV2 on Ethereum
        if (!addresses.isAddressSet("MULTICHAIN_GOVERNOR_V2_IMPL")) {
            vm.startBroadcast();

            address governorV2Impl = address(new MultichainGovernorV2());

            vm.stopBroadcast();

            addresses.addAddress("MULTICHAIN_GOVERNOR_V2_IMPL", governorV2Impl);
        }

        if (!addresses.isAddressSet("PROXY_ADMIN")) {
            vm.startBroadcast();

            ethereumProxyAdmin = address(new ProxyAdmin());

            vm.stopBroadcast();

            addresses.addAddress("PROXY_ADMIN", ethereumProxyAdmin);
        } else {
            ethereumProxyAdmin = addresses.getAddress("PROXY_ADMIN");
        }

        // Deploy VotingPowerAggregator on Ethereum
        if (!addresses.isAddressSet("VOTING_POWER_AGGREGATOR")) {
            address xWellAddress = addresses.getAddress("xWELL_PROXY");

            vm.startBroadcast();

            address votingPowerImpl = address(new VotingPowerAggregator());

            // Initialize with deployer as owner so we can configure it in afterDeploy
            // Ownership will be transferred to MultichainGovernorV2 in afterDeploy
            (, address deployerAddress, ) = vm.readCallers();
            bytes memory votingPowerInitData = abi.encodeWithSignature(
                "initialize(address,address)",
                deployerAddress,
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

        // Pre-compute the governor proxy CREATE address so Moonbeam contracts
        // can use it as a trusted sender before the proxy itself is deployed.
        // The proxy is deployed and initialized atomically at the end of deploy().
        if (!addresses.isAddressSet("MULTICHAIN_GOVERNOR_V2_PROXY")) {
            (, address deployer, ) = vm.readCallers();
            address predictedGovernorProxy = vm.computeCreateAddress(
                deployer,
                vm.getNonce(deployer)
            );

            addresses.addAddress(
                "MULTICHAIN_GOVERNOR_V2_PROXY",
                predictedGovernorProxy
            );
            addresses.addAddress("EMISSIONS_ADMIN", predictedGovernorProxy);
        }

        // ============ MOONBEAM DEPLOYMENTS ============
        vm.selectFork(MOONBEAM_FORK_ID);

        // Deploy MultichainGovernor v1.1 (with recoverETH) on Moonbeam
        if (!addresses.isAddressSet("MULTICHAIN_GOVERNOR_V1_1_IMPL")) {
            vm.startBroadcast();
            // NOTE: it's not v2 - it's the version with recoverETH()
            address newMultichainGovernorImpl = address(
                new MultichainGovernor()
            );
            vm.stopBroadcast();

            addresses.addAddress(
                "MULTICHAIN_GOVERNOR_V1_1_IMPL",
                newMultichainGovernorImpl
            );
        }

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
            trustedSenders[0] = ITemporalGovernor.TrustedSender({
                chainId: ETHEREUM_WORMHOLE_CHAIN_ID,
                addr: governorV2Proxy
            });

            vm.startBroadcast();

            // Deploy TemporalGovernor directly (not upgradeable, no proxy needed)
            address temporalGovernor = address(
                new TemporalGovernor(
                    wormholeCore,
                    TEMPORAL_GOVERNOR_PROPOSAL_DELAY,
                    TEMPORAL_GOVERNOR_PERMISSIONLESS_UNPAUSE_TIME,
                    trustedSenders
                )
            );

            vm.stopBroadcast();

            addresses.addAddress("TEMPORAL_GOVERNOR", temporalGovernor);
        }

        // Deploy ProposalView on Moonbeam (references TemporalGovernor)
        if (!addresses.isAddressSet("PROPOSAL_VIEW", block.chainid)) {
            address temporalGovernor = addresses.getAddress(
                "TEMPORAL_GOVERNOR"
            );

            vm.startBroadcast();

            address proposalView = address(
                new ProposalView(ITemporalGovernor(temporalGovernor))
            );

            vm.stopBroadcast();

            addresses.addAddress("PROPOSAL_VIEW", proposalView);
        }

        // Deploy VotingPowerAggregator on Moonbeam
        if (!addresses.isAddressSet("VOTING_POWER_AGGREGATOR", block.chainid)) {
            address xWell = addresses.getAddress("xWELL_PROXY");
            address moonbeamMultichainGovernor = addresses.getAddress(
                "MULTICHAIN_GOVERNOR_PROXY"
            );
            address moonbeamProxyAdmin = addresses.getAddress(
                "MOONBEAM_PROXY_ADMIN"
            );

            vm.startBroadcast();

            address votingPowerImpl = address(new VotingPowerAggregator());

            // Initialize with MultichainGovernor as owner so it can execute actions
            // Ownership will be transferred to TemporalGovernor at the end of the proposal
            bytes memory votingPowerInitData = abi.encodeWithSignature(
                "initialize(address,address)",
                moonbeamMultichainGovernor,
                xWell
            );

            address votingPowerProxy = address(
                new TransparentUpgradeableProxy(
                    votingPowerImpl,
                    moonbeamProxyAdmin,
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

        // 3. Deploy MultichainVoteCollectionMoonbeam on Moonbeam
        if (
            !addresses.isAddressSet("VOTE_COLLECTION_V2_PROXY", block.chainid)
        ) {
            address wormholeCore = addresses.getAddress("WORMHOLE_CORE");
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

            vm.selectFork(MOONBEAM_FORK_ID);

            // Initialize MultichainVoteCollectionMoonbeam with VotingPowerAggregator
            bytes memory initData = abi.encodeWithSignature(
                "initialize(address,address,address,uint16,address)",
                votingPowerAggregator,
                ethereumGovernorV2,
                wormholeCore,
                ETHEREUM_WORMHOLE_CHAIN_ID,
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

        // 4. Transfer ownership of the ProxyAdmin contract to the newly deployed MultichainGovernorV2

        // ============ BASE DEPLOYMENTS ============
        vm.selectFork(BASE_FORK_ID);

        // Deploy VotingPowerAggregator on Base
        if (!addresses.isAddressSet("VOTING_POWER_AGGREGATOR", block.chainid)) {
            address xWell = addresses.getAddress("xWELL_PROXY");
            address baseProxyAdmin = addresses.getAddress("MRD_PROXY_ADMIN");
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
            address optimismProxyAdmin = addresses.getAddress(
                "MRD_PROXY_ADMIN"
            );
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

        // Deploy + initialize the Ethereum governor proxy atomically as the last
        // step of deploy(). Asserts the deployed address matches the prediction.
        _deployAndInitializeGovernorV2(addresses);
    }

    /// @notice Atomically deploy and initialize the Ethereum MultichainGovernorV2 proxy.
    /// @dev Init data is encoded for the proxy constructor so initialize() runs
    /// in the same transaction as proxy creation.
    function _deployAndInitializeGovernorV2(Addresses addresses) internal {
        address registeredProxy = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_V2_PROXY"
        );

        // Idempotent: if the proxy is already deployed, nothing to do.
        vm.selectFork(ETHEREUM_FORK_ID);
        if (registeredProxy.code.length != 0) {
            return;
        }

        // startingProposalCount = moonbeam.proposalCount + 1 keeps proposal IDs
        // sequential across the migration.
        vm.selectFork(MOONBEAM_FORK_ID);
        uint256 startingProposalCount = MultichainGovernor(
            payable(addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"))
        ).proposalCount();
        address moonbeamVoteCollection = addresses.getAddress(
            "VOTE_COLLECTION_V2_PROXY"
        );

        vm.selectFork(BASE_FORK_ID);
        address baseVoteCollection = addresses.getAddress(
            "VOTE_COLLECTION_PROXY"
        );

        vm.selectFork(OPTIMISM_FORK_ID);
        address optimismVoteCollection = addresses.getAddress(
            "VOTE_COLLECTION_PROXY"
        );

        vm.selectFork(ETHEREUM_FORK_ID);

        MultichainGovernorV2.InitializeData memory initData;
        initData.votingPower = addresses.getAddress("VOTING_POWER_AGGREGATOR");
        initData.proposalThreshold = PROPOSAL_THRESHOLD;
        initData.votingPeriodSeconds = VOTING_PERIOD_SECONDS;
        initData
            .crossChainVoteCollectionPeriod = CROSS_CHAIN_VOTE_COLLECTION_PERIOD;
        initData.quorum = QUORUM;
        initData.pauseDuration = PAUSE_DURATION;
        initData.startingProposalCount = uint128(startingProposalCount + 1);
        initData.pauseGuardian = addresses.getAddress("PAUSE_GUARDIAN");
        initData.breakGlassGuardian = addresses.getAddress(
            "BREAK_GLASS_GUARDIAN"
        );
        initData.wormholeCore = addresses.getAddress("WORMHOLE_CORE");

        WormholeTrustedSender.TrustedSender[]
            memory trustedSenders = new WormholeTrustedSender.TrustedSender[](
                3
            );
        trustedSenders[0] = WormholeTrustedSender.TrustedSender({
            chainId: MOONBEAM_WORMHOLE_CHAIN_ID,
            addr: moonbeamVoteCollection
        });
        trustedSenders[1] = WormholeTrustedSender.TrustedSender({
            chainId: BASE_WORMHOLE_CHAIN_ID,
            addr: baseVoteCollection
        });
        trustedSenders[2] = WormholeTrustedSender.TrustedSender({
            chainId: OPTIMISM_WORMHOLE_CHAIN_ID,
            addr: optimismVoteCollection
        });

        bytes[] memory whitelistedCalldatas = _buildBreakGlassCalldatas(
            addresses
        );
        // _buildBreakGlassCalldatas switches forks during construction, restore Ethereum
        vm.selectFork(ETHEREUM_FORK_ID);

        bytes memory initCallData = abi.encodeWithSelector(
            MultichainGovernorV2.initialize.selector,
            initData,
            trustedSenders,
            whitelistedCalldatas
        );

        address governorV2Impl = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_V2_IMPL"
        );
        address ethereumProxyAdmin = addresses.getAddress("PROXY_ADMIN");

        vm.startBroadcast();
        address actualProxy = address(
            new TransparentUpgradeableProxy(
                governorV2Impl,
                ethereumProxyAdmin,
                initCallData
            )
        );
        vm.stopBroadcast();

        require(
            actualProxy == registeredProxy,
            "governor proxy address mismatch; deployer nonce shifted"
        );
    }

    function afterDeploy(Addresses addresses, address) public override {
        vm.selectFork(ETHEREUM_FORK_ID);

        address governorV2Proxy = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_V2_PROXY"
        );

        // Add stkWELL snapshot source and transfer aggregator ownership to the governor.
        vm.startBroadcast();
        _configureEthereumVotingPower(addresses, governorV2Proxy);
        vm.stopBroadcast();

        // Transfer Ethereum ProxyAdmin ownership to MultichainGovernorV2 (current owner is deployer)
        vm.startBroadcast(addresses.getAddress("MOONWELL_DEPLOYER"));

        ProxyAdmin(addresses.getAddress("PROXY_ADMIN")).transferOwnership(
            governorV2Proxy
        );

        vm.stopBroadcast();
    }

    /// @notice Helper function to configure Ethereum VotingPowerAggregator
    /// @dev Separated from afterDeploy to avoid stack too deep errors
    function _configureEthereumVotingPower(
        Addresses addresses,
        address governorV2Proxy
    ) internal {
        address ethereumVotingPower = addresses.getAddress(
            "VOTING_POWER_AGGREGATOR"
        );
        address ethereumStkWell = addresses.getAddress("STK_GOVTOKEN_PROXY");

        VotingPowerAggregator votingPower = VotingPowerAggregator(
            ethereumVotingPower
        );

        // xWell is already set during initialize() in deploy(); only snapshot
        // sources and ownership remain to be configured here.

        // Add stkWell as snapshot source
        votingPower.addSnapshotSource(ethereumStkWell);

        // Transfer ownership of VotingPowerAggregator to MultichainGovernorV2
        votingPower.transferOwnership(governorV2Proxy);
    }

    /// @notice Build whitelisted calldatas for the break glass guardian
    /// @dev These calldatas are the exact bytes the break glass guardian is allowed to execute.
    ///      Modeled after BreakGlass.s.sol but adapted for V2 (Ethereum-based governor, PAUSE_GUARDIAN
    ///      as the rollback address instead of Artemis Timelock).
    ///
    ///      The break glass guardian can call executeBreakGlass(targets, calldatas) where each
    ///      calldata must be in this whitelist. This allows emergency rollback of ownership/admin
    ///      to the PAUSE_GUARDIAN multisig.
    ///
    ///      Whitelisted calldatas:
    ///        [0] publishMessage — add PAUSE_GUARDIAN as trusted sender on Base TemporalGovernor
    ///        [1] publishMessage — add PAUSE_GUARDIAN as trusted sender on Optimism TemporalGovernor
    ///        [2] publishMessage — add PAUSE_GUARDIAN as trusted sender on Moonbeam TemporalGovernor
    ///        [3] _setPendingAdmin(address) — for mToken admin transfer
    ///        [4] setAdmin(address) — for chainlink oracle admin
    ///        [5] setEmissionsManager(address) — for stkWELL emissions manager
    ///        [6] changeAdmin(address) — for stkWELL admin
    ///        [7] transferOwnership(address) — for Ownable contracts (xWELL, bridge adapter, etc.)
    function _buildBreakGlassCalldatas(
        Addresses addresses
    ) internal returns (bytes[] memory) {
        address pauseGuardian = addresses.getAddress("PAUSE_GUARDIAN");

        // 8 whitelisted calldatas: 3 publishMessage (one per satellite chain) + 5 admin functions
        bytes[] memory calldatas = new bytes[](8);

        // --- publishMessage calldatas for each satellite chain's TemporalGovernor ---
        // Each adds PAUSE_GUARDIAN as a trusted sender on the respective TemporalGovernor
        // via Wormhole publishMessage → TemporalGovernor.setTrustedSenders()

        calldatas[0] = _buildPublishMessageCalldata(
            addresses,
            BASE_FORK_ID,
            ETHEREUM_WORMHOLE_CHAIN_ID,
            pauseGuardian
        );

        calldatas[1] = _buildPublishMessageCalldata(
            addresses,
            OPTIMISM_FORK_ID,
            ETHEREUM_WORMHOLE_CHAIN_ID,
            pauseGuardian
        );

        calldatas[2] = _buildPublishMessageCalldata(
            addresses,
            MOONBEAM_FORK_ID,
            ETHEREUM_WORMHOLE_CHAIN_ID,
            pauseGuardian
        );

        // --- Standard admin transfer calldatas ---

        /// for mTokens: _setPendingAdmin(address)
        calldatas[3] = abi.encodeWithSignature(
            "_setPendingAdmin(address)",
            pauseGuardian
        );

        /// for chainlink oracle: setAdmin(address)
        calldatas[4] = abi.encodeWithSignature(
            "setAdmin(address)",
            pauseGuardian
        );

        /// for stkWELL: setEmissionsManager(address)
        calldatas[5] = abi.encodeWithSignature(
            "setEmissionsManager(address)",
            pauseGuardian
        );

        /// for stkWELL: changeAdmin(address)
        calldatas[6] = abi.encodeWithSignature(
            "changeAdmin(address)",
            pauseGuardian
        );

        /// for Ownable contracts (xWELL, bridge adapter, etc.): transferOwnership(address)
        calldatas[7] = abi.encodeWithSignature(
            "transferOwnership(address)",
            pauseGuardian
        );

        // Restore Ethereum fork since callers expect it
        vm.selectFork(ETHEREUM_FORK_ID);

        return calldatas;
    }

    /// @notice Build a publishMessage calldata that adds a trusted sender on a satellite chain's TemporalGovernor
    /// @param addresses The address registry
    /// @param satelliteForkId Fork ID of the satellite chain
    /// @param trustedSenderChainId Wormhole chain ID of the chain the trusted sender is on (Ethereum)
    /// @param trustedSenderAddr Address to add as trusted sender (PAUSE_GUARDIAN)
    function _buildPublishMessageCalldata(
        Addresses addresses,
        uint256 satelliteForkId,
        uint16 trustedSenderChainId,
        address trustedSenderAddr
    ) internal returns (bytes memory) {
        vm.selectFork(satelliteForkId);
        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");

        // Build the setTrustedSenders calldata for the TemporalGovernor
        ITemporalGovernor.TrustedSender[]
            memory trustedSenders = new ITemporalGovernor.TrustedSender[](1);
        trustedSenders[0] = ITemporalGovernor.TrustedSender({
            chainId: trustedSenderChainId,
            addr: trustedSenderAddr
        });

        bytes memory setTrustedSendersCalldata = abi.encodeWithSignature(
            "setTrustedSenders((uint16,address)[])",
            trustedSenders
        );

        // Build the Wormhole publishMessage payload
        // The payload is consumed by TemporalGovernor._executeProposal which expects:
        //   abi.encode(intendedRecipient, targets[], values[], calldatas[])
        address[] memory targets = new address[](1);
        targets[0] = temporalGovernor;

        uint256[] memory values = new uint256[](1);

        bytes[] memory innerCalldatas = new bytes[](1);
        innerCalldatas[0] = setTrustedSendersCalldata;

        return
            abi.encodeWithSignature(
                "publishMessage(uint32,bytes,uint8)",
                1000,
                abi.encode(
                    temporalGovernor, // intendedRecipient
                    targets,
                    values,
                    innerCalldatas
                ),
                1 // finalized
            );
    }

    function _buildMoonbeam(Addresses addresses) internal {
        vm.selectFork(MOONBEAM_FORK_ID);

        // 4. Upgrade MultichainGovernor on Moonbeam to latest version (with recoverETH())
        address moonbeamMultichainGovernor = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );
        address moonbeamProxyAdmin = addresses.getAddress(
            "MOONBEAM_PROXY_ADMIN"
        );

        address newMultichainGovernorImpl = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_V1_1_IMPL"
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

        // 5.5. Add stkWell as snapshot source to VotingPowerAggregator on Moonbeam
        address moonbeamVotingPower = addresses.getAddress(
            "VOTING_POWER_AGGREGATOR"
        );
        address moonbeamStkWell = addresses.getAddress("STK_GOVTOKEN_PROXY");

        _pushAction(
            moonbeamVotingPower,
            abi.encodeWithSignature(
                "addSnapshotSource(address)",
                moonbeamStkWell
            ),
            "Add stkWell as snapshot source to VotingPowerAggregator on Moonbeam",
            ActionType.Moonbeam
        );

        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");

        // 5.6. Transfer VotingPowerAggregator ownership to TemporalGovernor
        _pushAction(
            moonbeamVotingPower,
            abi.encodeWithSignature(
                "transferOwnership(address)",
                temporalGovernor
            ),
            "Transfer VotingPowerAggregator ownership to TemporalGovernor on Moonbeam",
            ActionType.Moonbeam
        );

        // Note: Ethereum MultichainGovernorV2 is already set as a trusted sender on Moonbeam TemporalGovernor
        // during deployment (see deploy() function above), so no additional action needed here.

        // 6. Transfer ownership of all contracts on Moonbeam owned by MultichainGovernor to TemporalGovernor
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

        // Track addresses already processed to avoid duplicate actions for aliases
        // (e.g., mGLIMMER/MNATIVE and mETHwh/MOONWELL_mETH point to same contract)
        address[] memory processedAddresses = new address[](
            moonbeamContracts.length
        );
        uint256 processedCount = 0;

        // Loop through all contracts and transfer ownership if owned by MultichainGovernor
        for (uint256 i = 0; i < moonbeamContracts.length; i++) {
            // Check if contract address exists in addresses mapping
            if (!addresses.isAddressSet(moonbeamContracts[i])) {
                continue;
            }

            address contractAddress = addresses.getAddress(
                moonbeamContracts[i]
            );

            // Skip if we already processed this address (alias dedup)
            bool alreadyProcessed = false;
            for (uint256 j = 0; j < processedCount; j++) {
                if (processedAddresses[j] == contractAddress) {
                    alreadyProcessed = true;
                    break;
                }
            }
            if (alreadyProcessed) continue;

            // Pattern 1: Ownable (owner() -> transferOwnership())
            try this._getOwner(contractAddress) returns (address owner) {
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
                    ownershipTransferCount++;
                    contractsToValidateOwnership.push(moonbeamContracts[i]);
                    processedAddresses[processedCount++] = contractAddress;
                    continue;
                }
            } catch {}

            // Pattern 2: admin() — mToken/Unitroller (_setPendingAdmin) or ChainlinkOracle (setAdmin)
            try this._getAdmin(contractAddress) returns (address admin) {
                if (admin == moonbeamMultichainGovernor) {
                    bool hasPending = this._hasPendingAdmin(contractAddress);
                    if (hasPending) {
                        // mToken/Unitroller pattern: 2-step via _setPendingAdmin
                        _pushAction(
                            contractAddress,
                            abi.encodeWithSignature(
                                "_setPendingAdmin(address)",
                                payable(temporalGovernor)
                            ),
                            string(
                                abi.encodePacked(
                                    "Set pending admin on ",
                                    moonbeamContracts[i],
                                    " to TemporalGovernor"
                                )
                            ),
                            ActionType.Moonbeam
                        );
                    } else {
                        // ChainlinkOracle pattern: 1-step via setAdmin
                        _pushAction(
                            contractAddress,
                            abi.encodeWithSignature(
                                "setAdmin(address)",
                                temporalGovernor
                            ),
                            string(
                                abi.encodePacked(
                                    "Set admin on ",
                                    moonbeamContracts[i],
                                    " to TemporalGovernor"
                                )
                            ),
                            ActionType.Moonbeam
                        );
                    }
                    ownershipTransferCount++;
                    contractsToValidateOwnership.push(moonbeamContracts[i]);
                    processedAddresses[processedCount++] = contractAddress;
                    continue;
                }
            } catch {}

            // Pattern 3: EMISSION_MANAGER() -> setEmissionsManager() (stkWELL)
            try this._getEmissionManager(contractAddress) returns (
                address manager
            ) {
                if (manager == moonbeamMultichainGovernor) {
                    _pushAction(
                        contractAddress,
                        abi.encodeWithSignature(
                            "setEmissionsManager(address)",
                            temporalGovernor
                        ),
                        string(
                            abi.encodePacked(
                                "Set emissions manager on ",
                                moonbeamContracts[i],
                                " to TemporalGovernor"
                            )
                        ),
                        ActionType.Moonbeam
                    );
                    ownershipTransferCount++;
                    contractsToValidateOwnership.push(moonbeamContracts[i]);
                    processedAddresses[processedCount++] = contractAddress;
                    continue;
                }
            } catch {}
        }
    }

    function _buildBase(
        Addresses addresses,
        address ethereumGovernorV2
    ) internal {
        vm.selectFork(BASE_FORK_ID);

        // 7. Upgrade MultichainVoteCollection to V2 on Base
        address baseVoteCollectionProxy = addresses.getAddress(
            "VOTE_COLLECTION_PROXY"
        );
        address baseVoteCollectionV2Impl = addresses.getAddress(
            "VOTE_COLLECTION_V2_IMPL"
        );
        address baseProxyAdmin = addresses.getAddress("MRD_PROXY_ADMIN");
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
        // Call initializeV3 on Base VoteCollection - set VotingPowerAggregator and add new Ethereum governor
        // Old Moonbeam governor is hardcoded and will be removed automatically
        _pushAction(
            baseVoteCollectionProxy,
            abi.encodeWithSignature(
                "initializeV3(address,uint16,address)",
                baseVotingPowerAggregator,
                ETHEREUM_WORMHOLE_CHAIN_ID,
                ethereumGovernorV2
            ),
            "Initialize V2: set VotingPowerAggregator, remove old Moonbeam governor, add Ethereum governor on Base VoteCollection",
            ActionType.Base
        );
        // 7.5. Add stkWell as snapshot source to VotingPowerAggregator on Base
        address baseStkWell = addresses.getAddress("STK_GOVTOKEN_PROXY");

        _pushAction(
            baseVotingPowerAggregator,
            abi.encodeWithSignature("addSnapshotSource(address)", baseStkWell),
            "Add stkWell as snapshot source to VotingPowerAggregator on Base",
            ActionType.Base
        );
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
            chainId: ETHEREUM_WORMHOLE_CHAIN_ID,
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
        // Remove old Moonbeam MultichainGovernor as trusted sender from Base TemporalGovernor
        vm.selectFork(MOONBEAM_FORK_ID);
        address moonbeamMultichainGovernor = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );
        vm.selectFork(BASE_FORK_ID);
        ITemporalGovernor.TrustedSender[]
            memory trustedSendersToRemove = new ITemporalGovernor.TrustedSender[](
                1
            );
        trustedSendersToRemove[0] = ITemporalGovernor.TrustedSender({
            chainId: MOONBEAM_WORMHOLE_CHAIN_ID,
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
    }

    function _buildOptimism(
        Addresses addresses,
        address ethereumGovernorV2
    ) internal {
        vm.selectFork(OPTIMISM_FORK_ID);

        // 7. Upgrade MultichainVoteCollection to V2 on Optimism
        address optimismVoteCollectionProxy = addresses.getAddress(
            "VOTE_COLLECTION_PROXY"
        );
        address optimismVoteCollectionV2Impl = addresses.getAddress(
            "VOTE_COLLECTION_V2_IMPL"
        );
        address optimismProxyAdmin = addresses.getAddress("MRD_PROXY_ADMIN");
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
        // Call initializeV3 on Optimism VoteCollection - set VotingPowerAggregator and add new Ethereum governor
        // Old Moonbeam governor is hardcoded and will be removed automatically
        _pushAction(
            optimismVoteCollectionProxy,
            abi.encodeWithSignature(
                "initializeV3(address,uint16,address)",
                optimismVotingPowerAggregator,
                ETHEREUM_WORMHOLE_CHAIN_ID,
                ethereumGovernorV2
            ),
            "Initialize V2: set VotingPowerAggregator, remove old Moonbeam governor, add Ethereum governor on Optimism VoteCollection",
            ActionType.Optimism
        );
        // 7.5. Add stkWell as snapshot source to VotingPowerAggregator on Optimism
        address optimismStkWell = addresses.getAddress("STK_GOVTOKEN_PROXY");

        _pushAction(
            optimismVotingPowerAggregator,
            abi.encodeWithSignature(
                "addSnapshotSource(address)",
                optimismStkWell
            ),
            "Add stkWell as snapshot source to VotingPowerAggregator on Optimism",
            ActionType.Optimism
        );
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
            chainId: ETHEREUM_WORMHOLE_CHAIN_ID,
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
        // Remove old Moonbeam MultichainGovernor as trusted sender from Optimism TemporalGovernor
        vm.selectFork(MOONBEAM_FORK_ID);
        address moonbeamMultichainGovernor = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );
        vm.selectFork(OPTIMISM_FORK_ID);
        ITemporalGovernor.TrustedSender[]
            memory trustedSendersToRemove = new ITemporalGovernor.TrustedSender[](
                1
            );
        trustedSendersToRemove[0] = ITemporalGovernor.TrustedSender({
            chainId: MOONBEAM_WORMHOLE_CHAIN_ID,
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
    }

    function build(Addresses addresses) public override {
        // NOTE: Ethereum VotingPowerAggregator configuration (addSnapshotSource) is handled
        // in afterDeploy() by the deployer before transferring ownership to MultichainGovernorV2.
        // This proposal (mip-x52) is executed by the old Moonbeam MultichainGovernor, so it cannot
        // execute actions on the Ethereum MultichainGovernorV2 which doesn't have any proposals yet.

        // initializeV3() on Base/OP removes the legacy Moonbeam governor as a
        // trusted sender; in-flight Moonbeam proposals would have their satellite
        // votes stranded. Block construction until they drain.
        _assertNoLiveMoonbeamProposals(addresses);

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

    /// @notice Reverts if the Moonbeam MultichainGovernor has any Active or
    /// CrossChainVoteCollection proposals.
    function _assertNoLiveMoonbeamProposals(Addresses addresses) internal {
        uint256 currentForkId = vm.activeFork();
        vm.selectFork(MOONBEAM_FORK_ID);

        address moonbeamGovernor = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );
        uint256[] memory live = MultichainGovernor(payable(moonbeamGovernor))
            .liveProposals();

        require(
            live.length == 0,
            "Moonbeam governor has live proposals; wait for them to drain"
        );

        vm.selectFork(currentForkId);
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

    /// @notice Helper function to get pending owner of a contract (for 2-step ownership)
    /// @param contractAddress The address of the contract to check
    /// @return pendingOwner The pending owner address (address(0) if not 2-step or no pending owner)
    function _getPendingOwner(
        address contractAddress
    ) external view returns (address pendingOwner) {
        (bool success, bytes memory data) = contractAddress.staticcall(
            abi.encodeWithSignature("pendingOwner()")
        );
        if (success && data.length >= 32) {
            pendingOwner = abi.decode(data, (address));
        }
        // Returns address(0) if contract doesn't have pendingOwner() function
    }

    /// @notice Try to get admin() of a contract (mToken/Unitroller/ChainlinkOracle pattern)
    function _getAdmin(
        address contractAddress
    ) external view returns (address admin) {
        (bool success, bytes memory data) = contractAddress.staticcall(
            abi.encodeWithSignature("admin()")
        );
        require(success && data.length >= 32, "Failed to get admin");
        admin = abi.decode(data, (address));
    }

    /// @notice Try to get EMISSION_MANAGER() of a contract (stkWELL pattern)
    function _getEmissionManager(
        address contractAddress
    ) external view returns (address manager) {
        (bool success, bytes memory data) = contractAddress.staticcall(
            abi.encodeWithSignature("EMISSION_MANAGER()")
        );
        require(success && data.length >= 32, "Failed to get emission manager");
        manager = abi.decode(data, (address));
    }

    /// @notice Check if contract supports pendingAdmin (mToken/Unitroller vs ChainlinkOracle)
    function _hasPendingAdmin(
        address contractAddress
    ) external view returns (bool) {
        (bool success, ) = contractAddress.staticcall(
            abi.encodeWithSignature("pendingAdmin()")
        );
        return success;
    }

    /// @notice Helper function to validate all ownership transfers
    /// @param addresses The addresses contract
    /// @param temporalGovernor The temporal governor address
    /// @return success Whether all ownership transfers were validated successfully
    function _validateAllOwnershipTransfers(
        Addresses addresses,
        address temporalGovernor
    ) internal view returns (bool success) {
        uint256 validatedCount = 0;
        uint256 failedCount = 0;

        for (uint256 i = 0; i < contractsToValidateOwnership.length; i++) {
            string memory contractName = contractsToValidateOwnership[i];
            address contractAddress = addresses.getAddress(contractName);
            bool validated = false;

            // Pattern 1: owner() / pendingOwner()
            try this._getOwner(contractAddress) returns (address currentOwner) {
                if (currentOwner == temporalGovernor) {
                    validatedCount++;
                    validated = true;
                } else {
                    address pendingOwner = this._getPendingOwner(
                        contractAddress
                    );
                    if (pendingOwner == temporalGovernor) {
                        validatedCount++;
                        validated = true;
                    }
                }
            } catch {}

            if (validated) continue;

            // Pattern 2: admin() / pendingAdmin()
            try this._getAdmin(contractAddress) returns (address currentAdmin) {
                if (currentAdmin == temporalGovernor) {
                    validatedCount++;
                    validated = true;
                } else if (this._hasPendingAdmin(contractAddress)) {
                    // 2-step admin: check pendingAdmin
                    (bool ok, bytes memory data) = contractAddress.staticcall(
                        abi.encodeWithSignature("pendingAdmin()")
                    );
                    if (ok && data.length >= 32) {
                        address pendingAdmin = abi.decode(data, (address));
                        if (pendingAdmin == temporalGovernor) {
                            validatedCount++;
                            validated = true;
                        }
                    }
                }
            } catch {}

            if (validated) continue;

            // Pattern 3: EMISSION_MANAGER()
            try this._getEmissionManager(contractAddress) returns (
                address manager
            ) {
                if (manager == temporalGovernor) {
                    validatedCount++;
                    validated = true;
                }
            } catch {}

            if (!validated) {
                failedCount++;
            }
        }

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

        // 2. Validate MultichainGovernorV2 implementation is deployed
        address governorV2Impl = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_V2_IMPL"
        );
        assertGt(
            governorV2Impl.code.length,
            0,
            "MultichainGovernorV2 implementation not deployed on Ethereum"
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

        // 4. Validate governor is initialized correctly
        MultichainGovernorV2 governor = MultichainGovernorV2(
            payable(governorV2Proxy)
        );
        assertEq(
            address(governor.votingPower()),
            ethereumVotingPower,
            "MultichainGovernorV2 votingPower not set correctly"
        );

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

        // 6. Validate trusted senders are set correctly (Moonbeam, Base, Optimism VoteCollections)
        vm.selectFork(MOONBEAM_FORK_ID);
        address moonbeamVoteCollection = addresses.getAddress(
            "VOTE_COLLECTION_V2_PROXY"
        );

        vm.selectFork(BASE_FORK_ID);
        address baseVoteCollection = addresses.getAddress(
            "VOTE_COLLECTION_PROXY"
        );

        vm.selectFork(OPTIMISM_FORK_ID);
        address optimismVoteCollection = addresses.getAddress(
            "VOTE_COLLECTION_PROXY"
        );

        vm.selectFork(ETHEREUM_FORK_ID);
        assertTrue(
            governor.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                moonbeamVoteCollection
            ),
            "Moonbeam VoteCollection not trusted sender on MultichainGovernorV2"
        );

        assertTrue(
            governor.isTrustedSender(
                BASE_WORMHOLE_CHAIN_ID,
                baseVoteCollection
            ),
            "Base VoteCollection not trusted sender on MultichainGovernorV2"
        );

        assertTrue(
            governor.isTrustedSender(
                OPTIMISM_WORMHOLE_CHAIN_ID,
                optimismVoteCollection
            ),
            "Optimism VoteCollection not trusted sender on MultichainGovernorV2"
        );

        // 7. Validate governance parameters
        assertEq(
            governor.proposalThreshold(),
            PROPOSAL_THRESHOLD,
            "Proposal threshold not set correctly"
        );

        assertEq(
            governor.votingPeriod(),
            VOTING_PERIOD_SECONDS,
            "Voting period not set correctly"
        );

        assertEq(
            governor.crossChainVoteCollectionPeriod(),
            CROSS_CHAIN_VOTE_COLLECTION_PERIOD,
            "Cross chain vote collection period not set correctly"
        );

        assertEq(governor.quorum(), QUORUM, "Quorum not set correctly");

        // 8. Validate breakGlassGuardian and pauseGuardian
        assertEq(
            governor.breakGlassGuardian(),
            addresses.getAddress("BREAK_GLASS_GUARDIAN"),
            "breakGlassGuardian not set correctly on MultichainGovernorV2"
        );

        assertEq(
            governor.pauseGuardian(),
            addresses.getAddress("PAUSE_GUARDIAN"),
            "pauseGuardian not set correctly on MultichainGovernorV2"
        );

        assertEq(
            governor.pauseDuration(),
            PAUSE_DURATION,
            "pauseDuration not set correctly on MultichainGovernorV2"
        );

        assertEq(
            address(governor.wormhole()),
            addresses.getAddress("WORMHOLE_CORE"),
            "wormhole not set correctly on MultichainGovernorV2"
        );

        // 8b. Validate all 8 break-glass whitelisted calldatas were stored correctly.
        // These encode publishMessage / admin-transfer payloads used for emergency
        // rollback — any ABI/chainId/target mismatch would make break glass inoperable.
        bytes[] memory expectedCalldatas = _buildBreakGlassCalldatas(addresses);
        // _buildBreakGlassCalldatas switches forks; re-select Ethereum where the governor lives
        vm.selectFork(ETHEREUM_FORK_ID);
        for (uint256 i = 0; i < expectedCalldatas.length; i++) {
            assertTrue(
                governor.isWhitelistedCalldata(expectedCalldatas[i]),
                string.concat(
                    "break glass calldata not whitelisted at index ",
                    vm.toString(i)
                )
            );
        }

        // 9. Validate Ethereum VotingPowerAggregator state (configured in afterDeploy)
        // With Ownable2Step, afterDeploy only sets pendingOwner; the governor
        // must acceptOwnership() in its first proposal to complete the transfer
        VotingPowerAggregator ethAggregator = VotingPowerAggregator(
            ethereumVotingPower
        );
        assertEq(
            ethAggregator.pendingOwner(),
            governorV2Proxy,
            "Ethereum VotingPowerAggregator pendingOwner not set to MultichainGovernorV2"
        );

        assertEq(
            address(ethAggregator.xWell()),
            addresses.getAddress("xWELL_PROXY"),
            "Ethereum VotingPowerAggregator xWell not set correctly"
        );

        assertTrue(
            ethAggregator.isSnapshotSource(
                addresses.getAddress("STK_GOVTOKEN_PROXY")
            ),
            "stkWell not added as snapshot source on Ethereum VotingPowerAggregator"
        );

        // 11. Validate Ethereum ProxyAdmin ownership transferred to MultichainGovernorV2
        address ethereumProxyAdmin = addresses.getAddress("PROXY_ADMIN");
        assertEq(
            ProxyAdmin(ethereumProxyAdmin).owner(),
            governorV2Proxy,
            "Ethereum ProxyAdmin ownership not transferred to MultichainGovernorV2"
        );
    }

    function _validateMoonbeam(Addresses addresses) internal {
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

        // 2. Validate VotingPowerAggregator is deployed on Moonbeam
        address moonbeamVotingPower = addresses.getAddress(
            "VOTING_POWER_AGGREGATOR"
        );
        assertGt(
            moonbeamVotingPower.code.length,
            0,
            "VotingPowerAggregator not deployed on Moonbeam"
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

        // 4. Validate MultichainVoteCollectionMoonbeam has correct votingPower
        MultichainVoteCollectionMoonbeam voteCollection = MultichainVoteCollectionMoonbeam(
                moonbeamVoteCollectionV2
            );
        assertEq(
            address(voteCollection.votingPower()),
            moonbeamVotingPower,
            "VotingPowerAggregator not set on Moonbeam VoteCollection"
        );

        // 5. Validate MultichainVoteCollectionMoonbeam has Ethereum governor as trusted sender
        vm.selectFork(ETHEREUM_FORK_ID);
        address ethereumGovernorV2 = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_V2_PROXY"
        );

        vm.selectFork(MOONBEAM_FORK_ID);
        assertTrue(
            voteCollection.isTrustedSender(
                ETHEREUM_WORMHOLE_CHAIN_ID,
                ethereumGovernorV2
            ),
            "Ethereum MultichainGovernorV2 not trusted sender on Moonbeam VoteCollection"
        );

        // 5.5. Validate Ethereum MultichainGovernorV2 is trusted sender on Moonbeam TemporalGovernor
        // This is set during TemporalGovernor deployment (not in proposal actions)
        TemporalGovernor moonbeamTemporalGov = TemporalGovernor(
            payable(temporalGovernor)
        );
        assertTrue(
            moonbeamTemporalGov.isTrustedSender(
                ETHEREUM_WORMHOLE_CHAIN_ID,
                ethereumGovernorV2
            ),
            "Ethereum MultichainGovernorV2 not trusted sender on Moonbeam TemporalGovernor"
        );

        // 5.6. Validate ProposalView is deployed and references TemporalGovernor
        address proposalView = addresses.getAddress("PROPOSAL_VIEW");
        assertGt(
            proposalView.code.length,
            0,
            "ProposalView not deployed on Moonbeam"
        );
        assertEq(
            address(ProposalView(proposalView).temporalGovernor()),
            temporalGovernor,
            "ProposalView does not reference correct TemporalGovernor"
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

        // 7. Validate ETH was recovered from MultichainGovernor
        uint256 governorBalance = moonbeamMultichainGovernor.balance;
        assertEq(
            governorBalance,
            0,
            "ETH not recovered from MultichainGovernor"
        );

        // 8. Validate ProxyAdmin ownership transferred to TemporalGovernor
        assertEq(
            ProxyAdmin(moonbeamProxyAdmin).owner(),
            temporalGovernor,
            "MOONBEAM_PROXY_ADMIN ownership not transferred"
        );

        // 9. Validate ALL contract ownerships that were transferred to TemporalGovernor
        assertTrue(
            _validateAllOwnershipTransfers(addresses, temporalGovernor),
            "Ownership transfer validation failed"
        );

        // 10. Validate VotingPowerAggregator pending ownership transferred to
        // TemporalGovernor. With Ownable2Step, the Moonbeam governor's proposal
        // sets pendingOwner only; TemporalGovernor must call acceptOwnership()
        // in the first Ethereum MultichainGovernorV2 follow-up proposal.
        assertEq(
            VotingPowerAggregator(moonbeamVotingPower).pendingOwner(),
            temporalGovernor,
            "Moonbeam VotingPowerAggregator pendingOwner not set to TemporalGovernor"
        );

        // 11. Validate stkWell added as snapshot source on Moonbeam VotingPowerAggregator
        assertTrue(
            VotingPowerAggregator(moonbeamVotingPower).isSnapshotSource(
                addresses.getAddress("STK_GOVTOKEN_PROXY")
            ),
            "stkWell not added as snapshot source on Moonbeam VotingPowerAggregator"
        );
    }

    function _validateBase(
        Addresses addresses,
        address governorV2Proxy
    ) internal {
        vm.selectFork(BASE_FORK_ID);

        // 1. Validate VotingPowerAggregator is deployed on Base
        address baseVotingPower = addresses.getAddress(
            "VOTING_POWER_AGGREGATOR"
        );
        assertGt(
            baseVotingPower.code.length,
            0,
            "VotingPowerAggregator not deployed on Base"
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

        // 3. Validate MultichainVoteCollection was upgraded to V2 on Base
        address baseVoteCollectionProxy = addresses.getAddress(
            "VOTE_COLLECTION_PROXY"
        );
        address baseProxyAdmin = addresses.getAddress("MRD_PROXY_ADMIN");

        address baseCurrentImpl = ProxyAdmin(baseProxyAdmin)
            .getProxyImplementation(
                ITransparentUpgradeableProxy(payable(baseVoteCollectionProxy))
            );
        assertEq(
            baseCurrentImpl,
            baseVoteCollectionV2Impl,
            "MultichainVoteCollection not upgraded to V2 on Base"
        );

        // 4. Validate VotingPowerAggregator is set on Base VoteCollection
        MultichainVoteCollectionV2 baseVoteCollection = MultichainVoteCollectionV2(
                baseVoteCollectionProxy
            );
        assertEq(
            address(baseVoteCollection.votingPower()),
            baseVotingPower,
            "VotingPowerAggregator not set on Base VoteCollection"
        );

        // 4a. Validate wormhole is set on Base VoteCollection (storage slot preserved from V1)
        assertNotEq(
            address(baseVoteCollection.wormhole()),
            address(0),
            "wormhole not set on Base VoteCollection after upgrade"
        );

        // 5. Validate Ethereum MultichainGovernorV2 is trusted sender on Base VoteCollection
        assertTrue(
            baseVoteCollection.isTrustedSender(
                ETHEREUM_WORMHOLE_CHAIN_ID,
                governorV2Proxy
            ),
            "MultichainGovernorV2 not trusted sender on Base VoteCollection"
        );

        // 6. Validate old Moonbeam MultichainGovernor is NOT trusted sender anymore on Base VoteCollection
        vm.selectFork(MOONBEAM_FORK_ID);
        address moonbeamMultichainGovernor = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );

        vm.selectFork(BASE_FORK_ID);
        assertFalse(
            baseVoteCollection.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                moonbeamMultichainGovernor
            ),
            "Moonbeam MultichainGovernor still trusted sender on Base VoteCollection"
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
                ETHEREUM_WORMHOLE_CHAIN_ID,
                governorV2Proxy
            ),
            "Ethereum MultichainGovernorV2 not trusted sender on Base TemporalGovernor"
        );

        // 8. Validate stkWell added as snapshot source on Base VotingPowerAggregator
        VotingPowerAggregator baseAggregator = VotingPowerAggregator(
            baseVotingPower
        );
        assertTrue(
            baseAggregator.isSnapshotSource(
                addresses.getAddress("STK_GOVTOKEN_PROXY")
            ),
            "stkWell not added as snapshot source on Base VotingPowerAggregator"
        );

        // 8a. Validate VotingPowerAggregator owner is TemporalGovernor on Base
        assertEq(
            baseAggregator.owner(),
            baseTemporalGovernor,
            "Base VotingPowerAggregator owner not set to TemporalGovernor"
        );

        // 8b. Validate VotingPowerAggregator xWell is set correctly on Base
        assertEq(
            address(baseAggregator.xWell()),
            addresses.getAddress("xWELL_PROXY"),
            "Base VotingPowerAggregator xWell not set correctly"
        );

        // 9. Validate old Moonbeam MultichainGovernor is NOT trusted sender on Base TemporalGovernor
        assertFalse(
            temporalGov.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                moonbeamMultichainGovernor
            ),
            "Moonbeam MultichainGovernor still trusted sender on Base TemporalGovernor"
        );
    }

    function _validateOptimism(
        Addresses addresses,
        address governorV2Proxy
    ) internal {
        vm.selectFork(OPTIMISM_FORK_ID);

        // 1. Validate VotingPowerAggregator is deployed on Optimism
        address optimismVotingPower = addresses.getAddress(
            "VOTING_POWER_AGGREGATOR"
        );
        assertGt(
            optimismVotingPower.code.length,
            0,
            "VotingPowerAggregator not deployed on Optimism"
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

        // 3. Validate MultichainVoteCollection was upgraded to V2 on Optimism
        address optimismVoteCollectionProxy = addresses.getAddress(
            "VOTE_COLLECTION_PROXY"
        );
        address optimismProxyAdmin = addresses.getAddress("MRD_PROXY_ADMIN");

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

        // 4. Validate VotingPowerAggregator is set on Optimism VoteCollection
        MultichainVoteCollectionV2 optimismVoteCollection = MultichainVoteCollectionV2(
                optimismVoteCollectionProxy
            );
        assertEq(
            address(optimismVoteCollection.votingPower()),
            optimismVotingPower,
            "VotingPowerAggregator not set on Optimism VoteCollection"
        );

        // 4a. Validate wormhole is set on Optimism VoteCollection (storage slot preserved from V1)
        assertNotEq(
            address(optimismVoteCollection.wormhole()),
            address(0),
            "wormhole not set on Optimism VoteCollection after upgrade"
        );

        // 5. Validate Ethereum MultichainGovernorV2 is trusted sender on Optimism VoteCollection
        assertTrue(
            optimismVoteCollection.isTrustedSender(
                ETHEREUM_WORMHOLE_CHAIN_ID,
                governorV2Proxy
            ),
            "MultichainGovernorV2 not trusted sender on Optimism VoteCollection"
        );

        // 6. Validate old Moonbeam MultichainGovernor is NOT trusted sender anymore on Optimism VoteCollection
        vm.selectFork(MOONBEAM_FORK_ID);
        address moonbeamMultichainGovernor = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );

        vm.selectFork(OPTIMISM_FORK_ID);
        assertFalse(
            optimismVoteCollection.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                moonbeamMultichainGovernor
            ),
            "Moonbeam MultichainGovernor still trusted sender on Optimism VoteCollection"
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
                ETHEREUM_WORMHOLE_CHAIN_ID,
                governorV2Proxy
            ),
            "Ethereum MultichainGovernorV2 not trusted sender on Optimism TemporalGovernor"
        );

        // 8. Validate stkWell added as snapshot source on Optimism VotingPowerAggregator
        VotingPowerAggregator optimismAggregator = VotingPowerAggregator(
            optimismVotingPower
        );
        assertTrue(
            optimismAggregator.isSnapshotSource(
                addresses.getAddress("STK_GOVTOKEN_PROXY")
            ),
            "stkWell not added as snapshot source on Optimism VotingPowerAggregator"
        );

        // 8a. Validate VotingPowerAggregator owner is TemporalGovernor on Optimism
        assertEq(
            optimismAggregator.owner(),
            optimismTemporalGovernor,
            "Optimism VotingPowerAggregator owner not set to TemporalGovernor"
        );

        // 8b. Validate VotingPowerAggregator xWell is set correctly on Optimism
        assertEq(
            address(optimismAggregator.xWell()),
            addresses.getAddress("xWELL_PROXY"),
            "Optimism VotingPowerAggregator xWell not set correctly"
        );

        // 9. Validate old Moonbeam MultichainGovernor is NOT trusted sender on Optimism TemporalGovernor
        assertFalse(
            temporalGov.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                moonbeamMultichainGovernor
            ),
            "Moonbeam MultichainGovernor still trusted sender on Optimism TemporalGovernor"
        );
    }

    function validate(Addresses addresses, address) public override {
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
    }
}
