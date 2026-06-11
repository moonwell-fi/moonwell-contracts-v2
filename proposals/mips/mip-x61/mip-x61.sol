// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "forge-std/console.sol";
import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {MToken} from "@protocol/MToken.sol";

import {HybridProposalV2} from "@proposals/proposalTypes/HybridProposalV2.sol";
import {ChainlinkOracleConfigs} from "@proposals/ChainlinkOracleConfigs.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {ChainlinkOEVWrapper} from "@protocol/oracles/ChainlinkOEVWrapper.sol";
import {ChainlinkOEVMorphoWrapper} from "@protocol/oracles/ChainlinkOEVMorphoWrapper.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {BASE_FORK_ID, OPTIMISM_FORK_ID, ETHEREUM_FORK_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID, ETHEREUM_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";

/// @notice MIP-X61: ship the C4 #289 fix by redeploying the non-upgradeable Core
/// ChainlinkOEVWrapper (mirroring live params, repointing feeds via setFeed) and
/// upgrading the Base Morpho wrapper proxies in place, across Ethereum/Base/Optimism.
contract mipx61 is HybridProposalV2, ChainlinkOracleConfigs {
    using ChainIds for uint256;

    string public constant override name = "MIP-X61";

    /// @notice Registry key for the fixed Morpho wrapper implementation.
    string public constant MORPHO_IMPLEMENTATION_NAME =
        "CHAINLINK_OEV_MORPHO_WRAPPER_IMPL";

    /// @notice Archive-key suffix for the pre-fix Core wrappers.
    string internal constant DEPRECATED_SUFFIX = "_DEPRECATED2";

    /// @notice Pre-upgrade Morpho wrapper storage state, snapshotted in
    /// beforeSimulationHook() so validate() can prove the logic-only upgrade reset
    /// nothing.
    struct MorphoSnapshot {
        address priceFeed;
        address morphoBlue;
        address chainlinkOracle;
        address feeRecipient;
        uint16 liquidatorFeeBps;
        uint256 maxRoundDelay;
        uint256 maxDecrements;
        uint256 cachedRoundId;
        address owner;
        bool taken;
    }

    mapping(string => MorphoSnapshot) internal _morphoSnap;

    /// @notice Pre-execution price snapshots for redeployed Core wrappers, keyed by
    /// chain id then oracleName (raw aggregator latestRoundData) and by mTokenKey
    /// (full ChainlinkOracle.getUnderlyingPrice path). The redeploy reseeds the new
    /// wrapper's cachedRoundId to the latest round, so it forwards the raw feed
    /// unchanged — validate() asserts the new wrapper's output against the raw feed.
    mapping(uint256 => mapping(string => int256)) internal _rawAnswerPre;
    mapping(uint256 => mapping(string => uint256)) internal _rawUpdatedAtPre;
    mapping(uint256 => mapping(string => uint256)) internal _underlyingPricePre;

    constructor() {
        _setProposalDescription(
            bytes(vm.readFile("./proposals/mips/mip-x61/MIP-X61.md"))
        );
    }

    function primaryForkId() public pure override returns (uint256) {
        return ETHEREUM_FORK_ID;
    }

    /// @notice Override the base run() so deploy() is NOT wrapped in a single
    /// vm.startBroadcast. This proposal deploys across the Base, Optimism, and
    /// Ethereum forks, and vm.selectFork is illegal while a broadcast is active.
    /// Each per-chain deploy helper opens its own broadcast after selecting its
    /// fork (see _deployCoreWrappers / _deployMorphoImplementation); every fork
    /// switch below happens outside any broadcast. Otherwise mirrors the base
    /// Proposal.run() (including the IPFS descriptionUri injection).
    function run() public override {
        primaryForkId().createForksAndSelect();

        Addresses addresses = new Addresses();
        vm.makePersistent(address(addresses));

        vm.selectFork(primaryForkId());

        setProposalDescriptionUri(_resolveProposalDescriptionUri(this.name()));

        initProposal(addresses);

        (, address deployerAddress, ) = vm.readCallers();

        if (DO_DEPLOY) deploy(addresses, deployerAddress);
        if (DO_AFTER_DEPLOY) afterDeploy(addresses, deployerAddress);

        if (DO_BUILD) build(addresses);
        if (DO_RUN) simulate(addresses, deployerAddress);
        if (DO_TEARDOWN) teardown(addresses, deployerAddress);
        if (DO_VALIDATE) {
            validate(addresses, deployerAddress);
        }
        if (DO_PRINT) {
            printProposalActionSteps();

            addresses.removeAllRestrictions();
            printCalldata(addresses);

            _printAddressesChanges(addresses);
        }
    }

    function deploy(Addresses addresses, address) public override {
        vm.selectFork(BASE_FORK_ID);
        _deployCoreWrappers(addresses);
        _deployMorphoImplementation(addresses);

        vm.selectFork(OPTIMISM_FORK_ID);
        _deployCoreWrappers(addresses);

        vm.selectFork(ETHEREUM_FORK_ID);
        _deployCoreWrappers(addresses);

        vm.selectFork(primaryForkId());
    }

    /// @notice Redeploy each Core OEV wrapper for the active chain, mirroring live
    /// params via getters, archiving the old wrapper and repointing the canonical name.
    function _deployCoreWrappers(Addresses addresses) internal {
        OracleConfig[] memory oracleConfigs = getOracleConfigurations(
            block.chainid
        );

        // Broadcast is opened here (after deploy() selected this chain's fork)
        // rather than around the whole deploy(), so the cross-fork vm.selectFork
        // calls in deploy() happen outside any active broadcast.
        vm.startBroadcast();
        for (uint256 i = 0; i < oracleConfigs.length; i++) {
            string memory wrapperName = string(
                abi.encodePacked(oracleConfigs[i].oracleName, "_OEV_WRAPPER")
            );
            if (!addresses.isAddressSet(wrapperName)) {
                continue;
            }

            string memory deprecatedName = string(
                abi.encodePacked(wrapperName, DEPRECATED_SUFFIX)
            );

            // Skip wrappers already redeployed this run (USDC/USDBC, USDT/USDT0 share one wrapper).
            if (addresses.isAddressSet(deprecatedName)) {
                continue;
            }

            address oldWrapper = addresses.getAddress(wrapperName);
            ChainlinkOEVWrapper old = ChainlinkOEVWrapper(payable(oldWrapper));

            ChainlinkOEVWrapper wrapper = new ChainlinkOEVWrapper(
                address(old.priceFeed()),
                old.owner(),
                address(old.chainlinkOracle()),
                old.feeRecipient(),
                old.liquidatorFeeBps(),
                old.maxRoundDelay(),
                old.maxDecrements()
            );

            addresses.addAddress(deprecatedName, oldWrapper);
            addresses.changeAddress(wrapperName, address(wrapper), true);
        }
        vm.stopBroadcast();
    }

    /// @notice Deploy the fixed Morpho wrapper implementation on Base, archiving the previous one.
    function _deployMorphoImplementation(Addresses addresses) internal {
        vm.startBroadcast();
        ChainlinkOEVMorphoWrapper impl = new ChainlinkOEVMorphoWrapper();

        if (addresses.isAddressSet(MORPHO_IMPLEMENTATION_NAME)) {
            addresses.addAddress(
                string(
                    abi.encodePacked(
                        MORPHO_IMPLEMENTATION_NAME,
                        DEPRECATED_SUFFIX
                    )
                ),
                addresses.getAddress(MORPHO_IMPLEMENTATION_NAME)
            );
            addresses.changeAddress(
                MORPHO_IMPLEMENTATION_NAME,
                address(impl),
                true
            );
        } else {
            addresses.addAddress(MORPHO_IMPLEMENTATION_NAME, address(impl));
        }
        vm.stopBroadcast();
    }

    /// @notice Snapshot pre-execution oracle prices + Morpho state on every chain so
    /// validate() can prove the redeploy/upgrade is price-neutral. Runs after build()
    /// queues the actions but before simulate() executes them — so feeds still point
    /// at the OLD wrappers and the Morpho proxies still run the OLD implementation.
    function beforeSimulationHook(Addresses addresses) public override {
        _snapshotCoreChain(addresses, BASE_FORK_ID, BASE_CHAIN_ID);
        _snapshotCoreChain(addresses, OPTIMISM_FORK_ID, OPTIMISM_CHAIN_ID);
        _snapshotCoreChain(addresses, ETHEREUM_FORK_ID, ETHEREUM_CHAIN_ID);
        _snapshotMorphoState(addresses);
        vm.selectFork(primaryForkId());
    }

    /// @notice Snapshot the raw feed answer and full getUnderlyingPrice path for
    /// every redeployed Core wrapper on a chain.
    function _snapshotCoreChain(
        Addresses addresses,
        uint256 forkId,
        uint256 chainId
    ) internal {
        vm.selectFork(forkId);

        OracleConfig[] memory oracleConfigs = getOracleConfigurations(chainId);
        ChainlinkOracle oracle = ChainlinkOracle(
            addresses.getAddress("CHAINLINK_ORACLE")
        );

        for (uint256 i = 0; i < oracleConfigs.length; i++) {
            string memory oracleName = oracleConfigs[i].oracleName;
            string memory deprecatedName = string(
                abi.encodePacked(oracleName, "_OEV_WRAPPER", DEPRECATED_SUFFIX)
            );
            // Only wrappers redeployed by this proposal (archive set in deploy()).
            if (!addresses.isAddressSet(deprecatedName)) {
                continue;
            }

            // Raw aggregator output, once per oracleName.
            if (_rawUpdatedAtPre[chainId][oracleName] == 0) {
                (, int256 rawAns, , uint256 rawUp, ) = AggregatorV3Interface(
                    addresses.getAddress(oracleName)
                ).latestRoundData();
                _rawAnswerPre[chainId][oracleName] = rawAns;
                _rawUpdatedAtPre[chainId][oracleName] = rawUp;
            }

            // Full getUnderlyingPrice path per mTokenKey (still routed via the old wrapper).
            string memory mTokenKey = oracleConfigs[i].mTokenKey;
            if (
                bytes(mTokenKey).length > 0 && addresses.isAddressSet(mTokenKey)
            ) {
                _underlyingPricePre[chainId][mTokenKey] = oracle
                    .getUnderlyingPrice(
                        MToken(addresses.getAddress(mTokenKey))
                    );
            }
        }
    }

    /// @notice Snapshot each Base Morpho wrapper's pre-upgrade storage state.
    function _snapshotMorphoState(Addresses addresses) internal {
        vm.selectFork(BASE_FORK_ID);

        MorphoOracleConfig[]
            memory morphoConfigs = getMorphoOracleConfigurations(BASE_CHAIN_ID);

        for (uint256 i = 0; i < morphoConfigs.length; i++) {
            string memory wrapperName = string(
                abi.encodePacked(morphoConfigs[i].proxyName, "_ORACLE_PROXY")
            );
            if (!addresses.isAddressSet(wrapperName)) {
                continue;
            }

            ChainlinkOEVMorphoWrapper w = ChainlinkOEVMorphoWrapper(
                addresses.getAddress(wrapperName)
            );

            _morphoSnap[wrapperName] = MorphoSnapshot({
                priceFeed: address(w.priceFeed()),
                morphoBlue: address(w.morphoBlue()),
                chainlinkOracle: address(w.chainlinkOracle()),
                feeRecipient: w.feeRecipient(),
                liquidatorFeeBps: w.liquidatorFeeBps(),
                maxRoundDelay: w.maxRoundDelay(),
                maxDecrements: w.maxDecrements(),
                cachedRoundId: w.cachedRoundId(),
                owner: w.owner(),
                taken: true
            });
        }
    }

    function build(Addresses addresses) public override {
        vm.selectFork(BASE_FORK_ID);
        _wireCoreFeeds(addresses, BASE_CHAIN_ID);
        _upgradeMorphoWrappers(addresses, BASE_CHAIN_ID);

        vm.selectFork(OPTIMISM_FORK_ID);
        _wireCoreFeeds(addresses, OPTIMISM_CHAIN_ID);

        vm.selectFork(ETHEREUM_FORK_ID);
        _wireCoreFeeds(addresses, ETHEREUM_CHAIN_ID);

        vm.selectFork(primaryForkId());
    }

    /// @notice Repoint each market's ChainlinkOracle feed at its redeployed wrapper (auto-tagged to the active fork).
    function _wireCoreFeeds(Addresses addresses, uint256 chainId) internal {
        OracleConfig[] memory oracleConfigs = getOracleConfigurations(chainId);
        address chainlinkOracle = addresses.getAddress("CHAINLINK_ORACLE");

        // No dedup here (unlike _deployCoreWrappers): shared-wrapper symbols (USDC/USDBC, USDT/USDT0) each need their own setFeed.
        for (uint256 i = 0; i < oracleConfigs.length; i++) {
            string memory wrapperName = string(
                abi.encodePacked(oracleConfigs[i].oracleName, "_OEV_WRAPPER")
            );
            if (!addresses.isAddressSet(wrapperName)) {
                continue;
            }

            string memory symbol = ERC20(
                addresses.getAddress(oracleConfigs[i].symbol)
            ).symbol();

            _pushAction(
                chainlinkOracle,
                abi.encodeWithSignature(
                    "setFeed(string,address)",
                    symbol,
                    addresses.getAddress(wrapperName)
                ),
                string.concat(
                    "Repoint ",
                    symbol,
                    " feed at redeployed OEV wrapper (C4 #289)"
                )
            );
        }
    }

    /// @notice Upgrade each Morpho wrapper proxy in place; plain upgrade since the fix is logic-only (no re-init).
    function _upgradeMorphoWrappers(
        Addresses addresses,
        uint256 chainId
    ) internal {
        MorphoOracleConfig[]
            memory morphoConfigs = getMorphoOracleConfigurations(chainId);
        if (morphoConfigs.length == 0) {
            return;
        }

        address proxyAdmin = addresses.getAddress(
            "CHAINLINK_ORACLE_PROXY_ADMIN"
        );
        address newImpl = addresses.getAddress(MORPHO_IMPLEMENTATION_NAME);

        for (uint256 i = 0; i < morphoConfigs.length; i++) {
            string memory wrapperName = string(
                abi.encodePacked(morphoConfigs[i].proxyName, "_ORACLE_PROXY")
            );
            require(
                addresses.isAddressSet(wrapperName),
                "MIP-X61: Morpho wrapper proxy not registered"
            );

            _pushAction(
                proxyAdmin,
                abi.encodeWithSignature(
                    "upgrade(address,address)",
                    addresses.getAddress(wrapperName),
                    newImpl
                ),
                string.concat(
                    "Upgrade Morpho OEV wrapper to C4 #289 fix for ",
                    morphoConfigs[i].proxyName
                )
            );
        }
    }

    function validate(Addresses addresses, address) public override {
        vm.selectFork(BASE_FORK_ID);
        _validateCoreWrappers(addresses, BASE_CHAIN_ID);
        _validateMorphoWrappers(addresses, BASE_CHAIN_ID);

        vm.selectFork(OPTIMISM_FORK_ID);
        _validateCoreWrappers(addresses, OPTIMISM_CHAIN_ID);

        vm.selectFork(ETHEREUM_FORK_ID);
        _validateCoreWrappers(addresses, ETHEREUM_CHAIN_ID);

        vm.selectFork(primaryForkId());

        console.log("Validation completed for proposal ", this.name());
    }

    /// @notice Assert each redeployed Core wrapper: feed repointed, fresh address, and all params mirror the archived wrapper.
    function _validateCoreWrappers(
        Addresses addresses,
        uint256 chainId
    ) internal view {
        OracleConfig[] memory oracleConfigs = getOracleConfigurations(chainId);
        ChainlinkOracle oracle = ChainlinkOracle(
            addresses.getAddress("CHAINLINK_ORACLE")
        );

        for (uint256 i = 0; i < oracleConfigs.length; i++) {
            string memory wrapperName = string(
                abi.encodePacked(oracleConfigs[i].oracleName, "_OEV_WRAPPER")
            );
            string memory deprecatedName = string(
                abi.encodePacked(wrapperName, DEPRECATED_SUFFIX)
            );

            // Only redeployed wrappers have an archive entry.
            if (!addresses.isAddressSet(deprecatedName)) {
                continue;
            }

            ChainlinkOEVWrapper newWrapper = ChainlinkOEVWrapper(
                payable(addresses.getAddress(wrapperName))
            );
            ChainlinkOEVWrapper oldWrapper = ChainlinkOEVWrapper(
                payable(addresses.getAddress(deprecatedName))
            );

            string memory symbol = ERC20(
                addresses.getAddress(oracleConfigs[i].symbol)
            ).symbol();
            assertEq(
                address(oracle.getFeed(symbol)),
                address(newWrapper),
                string.concat("X61: feed not repointed for ", symbol)
            );
            assertTrue(
                address(newWrapper) != address(oldWrapper),
                string.concat("X61: wrapper not redeployed for ", wrapperName)
            );
            assertEq(
                address(newWrapper.priceFeed()),
                address(oldWrapper.priceFeed()),
                string.concat("X61: priceFeed drift for ", wrapperName)
            );
            assertEq(
                newWrapper.owner(),
                oldWrapper.owner(),
                string.concat("X61: owner drift for ", wrapperName)
            );
            assertEq(
                address(newWrapper.chainlinkOracle()),
                address(oldWrapper.chainlinkOracle()),
                string.concat("X61: chainlinkOracle drift for ", wrapperName)
            );
            assertEq(
                newWrapper.feeRecipient(),
                oldWrapper.feeRecipient(),
                string.concat("X61: feeRecipient drift for ", wrapperName)
            );
            assertEq(
                newWrapper.liquidatorFeeBps(),
                oldWrapper.liquidatorFeeBps(),
                string.concat("X61: liquidatorFeeBps drift for ", wrapperName)
            );
            assertEq(
                newWrapper.maxRoundDelay(),
                oldWrapper.maxRoundDelay(),
                string.concat("X61: maxRoundDelay drift for ", wrapperName)
            );
            assertEq(
                newWrapper.maxDecrements(),
                oldWrapper.maxDecrements(),
                string.concat("X61: maxDecrements drift for ", wrapperName)
            );
            assertGt(
                newWrapper.cachedRoundId(),
                0,
                string.concat("X61: cachedRoundId unseeded for ", wrapperName)
            );

            _assertCorePricePreserved(
                addresses,
                chainId,
                oracleConfigs[i],
                newWrapper,
                wrapperName
            );
        }
    }

    /// @notice Assert the redeployed wrapper forwards the same raw feed it did pre-
    /// execution: latestRoundData() equals the raw-aggregator snapshot exactly, and
    /// getUnderlyingPrice stays within 2% — one fresh Chainlink round can shift the
    /// old wrapper's pre-snapshot (it delayed the round; the new wrapper, seeded to
    /// the latest round at deploy, forwards it).
    function _assertCorePricePreserved(
        Addresses addresses,
        uint256 chainId,
        OracleConfig memory config,
        ChainlinkOEVWrapper newWrapper,
        string memory wrapperName
    ) internal view {
        (, int256 ans, , uint256 up, ) = newWrapper.latestRoundData();
        assertEq(
            ans,
            _rawAnswerPre[chainId][config.oracleName],
            string.concat("X61: answer != raw pre-snapshot for ", wrapperName)
        );
        assertEq(
            up,
            _rawUpdatedAtPre[chainId][config.oracleName],
            string.concat(
                "X61: updatedAt != raw pre-snapshot for ",
                wrapperName
            )
        );

        if (
            bytes(config.mTokenKey).length > 0 &&
            addresses.isAddressSet(config.mTokenKey)
        ) {
            uint256 pre = _underlyingPricePre[chainId][config.mTokenKey];
            if (pre != 0) {
                uint256 post = ChainlinkOracle(
                    addresses.getAddress("CHAINLINK_ORACLE")
                ).getUnderlyingPrice(
                        MToken(addresses.getAddress(config.mTokenKey))
                    );
                assertApproxEqRel(
                    post,
                    pre,
                    0.02e18,
                    string.concat(
                        "X61: getUnderlyingPrice drifted >2% for ",
                        config.mTokenKey
                    )
                );
            }
        }
    }

    /// @notice Assert each Base Morpho proxy points at the fixed impl and the logic-only upgrade preserved all state.
    function _validateMorphoWrappers(
        Addresses addresses,
        uint256 chainId
    ) internal view {
        MorphoOracleConfig[]
            memory morphoConfigs = getMorphoOracleConfigurations(chainId);
        if (morphoConfigs.length == 0) {
            return;
        }

        address newImpl = addresses.getAddress(MORPHO_IMPLEMENTATION_NAME);
        address proxyAdmin = addresses.getAddress(
            "CHAINLINK_ORACLE_PROXY_ADMIN"
        );

        for (uint256 i = 0; i < morphoConfigs.length; i++) {
            string memory wrapperName = string(
                abi.encodePacked(morphoConfigs[i].proxyName, "_ORACLE_PROXY")
            );

            validateProxy(
                vm,
                addresses.getAddress(wrapperName),
                newImpl,
                proxyAdmin,
                string.concat("X61 morpho upgrade: ", wrapperName)
            );

            MorphoSnapshot memory snap = _morphoSnap[wrapperName];
            require(snap.taken, "MIP-X61: missing Morpho snapshot");

            ChainlinkOEVMorphoWrapper w = ChainlinkOEVMorphoWrapper(
                addresses.getAddress(wrapperName)
            );

            assertEq(
                address(w.priceFeed()),
                snap.priceFeed,
                string.concat("X61: morpho priceFeed reset for ", wrapperName)
            );
            assertEq(
                address(w.morphoBlue()),
                snap.morphoBlue,
                string.concat("X61: morpho morphoBlue reset for ", wrapperName)
            );
            assertEq(
                address(w.chainlinkOracle()),
                snap.chainlinkOracle,
                string.concat(
                    "X61: morpho chainlinkOracle reset for ",
                    wrapperName
                )
            );
            assertEq(
                w.feeRecipient(),
                snap.feeRecipient,
                string.concat(
                    "X61: morpho feeRecipient reset for ",
                    wrapperName
                )
            );
            assertEq(
                w.liquidatorFeeBps(),
                snap.liquidatorFeeBps,
                string.concat(
                    "X61: morpho liquidatorFeeBps reset for ",
                    wrapperName
                )
            );
            assertEq(
                w.maxRoundDelay(),
                snap.maxRoundDelay,
                string.concat(
                    "X61: morpho maxRoundDelay reset for ",
                    wrapperName
                )
            );
            assertEq(
                w.maxDecrements(),
                snap.maxDecrements,
                string.concat(
                    "X61: morpho maxDecrements reset for ",
                    wrapperName
                )
            );
            assertEq(
                w.cachedRoundId(),
                snap.cachedRoundId,
                string.concat(
                    "X61: morpho cachedRoundId reset for ",
                    wrapperName
                )
            );
            assertEq(
                w.owner(),
                snap.owner,
                string.concat("X61: morpho owner reset for ", wrapperName)
            );

            // Liveness: the upgraded impl still serves a valid price. Storage is
            // asserted unchanged above and latestRoundData() logic is untouched by
            // the fix, so the consumer-facing output is preserved by construction;
            // a strict pre/post output equality would be fragile because a fresh
            // round can flip the delay state across the simulate() time warp.
            (, int256 ans, , , ) = w.latestRoundData();
            assertGt(
                ans,
                0,
                string.concat("X61: morpho price invalid for ", wrapperName)
            );
        }
    }
}
