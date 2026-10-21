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
import {ChainlinkCompositeOracle} from "@protocol/oracles/ChainlinkCompositeOracle.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {validateProxy, _IMPLEMENTATION_SLOT} from "@proposals/utils/ProxyUtils.sol";
import {BASE_FORK_ID, OPTIMISM_FORK_ID, ETHEREUM_FORK_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID, ETHEREUM_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";

/// @notice Chainlink EACAggregatorProxy surface used to prove two proxies share one aggregator.
interface IChainlinkAggregatorProxy {
    function aggregator() external view returns (address);
}

/// @notice MIP-X72: ship the C4 #289 fix by redeploying the non-upgradeable Core
/// ChainlinkOEVWrapper (mirroring live params, repointing feeds via setFeed) and
/// upgrading the Base Morpho wrapper proxies in place, across Ethereum/Base/Optimism.
contract mipx72 is HybridProposalV2, ChainlinkOracleConfigs {
    using ChainIds for uint256;

    string public constant override name = "MIP-X72";

    /// @notice Registry key for the fixed Morpho wrapper implementation.
    string public constant MORPHO_IMPLEMENTATION_NAME =
        "CHAINLINK_OEV_MORPHO_WRAPPER_IMPL";

    /// @notice Registry key for the implementation the Base Morpho proxies run
    /// before this proposal (registered by MIP-X56).
    string public constant MORPHO_LIVE_IMPLEMENTATION_NAME =
        "CHAINLINK_OEV_MORPHO_WRAPPER_IMPL_V2";

    /// @notice Archive-key suffix for the pre-fix Core wrappers.
    string internal constant DEPRECATED_SUFFIX = "_DEPRECATED_V4";

    /// @notice Registry suffix of a Chainlink SVR proxy replaced by its standard proxy.
    string internal constant SVR_SUFFIX = "_SVR";

    /// @notice Archive-key suffix for composite oracles rebuilt off an SVR base feed.
    string internal constant COMPOSITE_DEPRECATED_SUFFIX = "_DEPRECATED_SVR";

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
        address implementation;
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

    /// @notice Pre-execution getUnderlyingPrice for markets priced by a rebuilt composite.
    mapping(string => uint256) internal _compositePricePre;

    /// @notice Pre-execution answers of the old Core wrappers and the Morpho proxies,
    /// only for the before/after price log in validate().
    mapping(uint256 => mapping(string => int256)) internal _wrapperAnswerPre;
    mapping(string => int256) internal _morphoAnswerPre;

    constructor() {
        _setProposalDescription(
            bytes(vm.readFile("./proposals/mips/mip-x72/x72.md"))
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
        _deployCompositeOracles(addresses);
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

            address feed = _standardFeed(
                addresses,
                oracleConfigs[i].oracleName,
                address(old.priceFeed())
            );

            ChainlinkOEVWrapper wrapper = new ChainlinkOEVWrapper(
                feed,
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

    /// @notice Canonical (standard) feed for `feedName`. A live feed that differs
    /// must be the registered `<feedName>_SVR` proxy, which this proposal replaces.
    function _standardFeed(
        Addresses addresses,
        string memory feedName,
        address liveFeed
    ) internal view returns (address feed) {
        feed = addresses.getAddress(feedName);
        if (feed != liveFeed) {
            require(
                liveFeed ==
                    addresses.getAddress(string.concat(feedName, SVR_SUFFIX)),
                string.concat("MIP-X72: unexpected live feed for ", feedName)
            );
        }
    }

    /// @notice Redeploy each Base composite oracle whose base feed is an SVR proxy,
    /// swapping in the standard proxy and mirroring both multipliers.
    function _deployCompositeOracles(Addresses addresses) internal {
        CompositeOracleConfig[]
            memory configs = getCompositeOracleConfigurations(block.chainid);

        vm.startBroadcast();
        for (uint256 i = 0; i < configs.length; i++) {
            ChainlinkCompositeOracle old = ChainlinkCompositeOracle(
                addresses.getAddress(configs[i].compositeOracleName)
            );
            address base = _standardFeed(
                addresses,
                configs[i].baseFeedName,
                old.base()
            );
            if (base == old.base()) {
                continue;
            }

            ChainlinkCompositeOracle composite = new ChainlinkCompositeOracle(
                base,
                old.multiplier(),
                old.secondMultiplier()
            );

            addresses.addAddress(
                string.concat(
                    configs[i].compositeOracleName,
                    COMPOSITE_DEPRECATED_SUFFIX
                ),
                address(old)
            );
            addresses.changeAddress(
                configs[i].compositeOracleName,
                address(composite),
                true
            );
        }
        vm.stopBroadcast();
    }

    /// @notice Deploy the fixed Morpho wrapper implementation on Base, archiving the
    /// implementation the proxies actually run (read from the ERC1967 slot).
    function _deployMorphoImplementation(Addresses addresses) internal {
        address liveImpl = _liveMorphoImplementation(addresses);

        vm.startBroadcast();
        ChainlinkOEVMorphoWrapper impl = new ChainlinkOEVMorphoWrapper();

        // Archive the impl behind the proxies (== _IMPL_V2), not the unsuffixed
        // key's current value: that is the pre-MIP-X56 impl, behind no proxy, and
        // is deliberately dropped from the canonical key without an archive.
        addresses.addAddress(
            string.concat(MORPHO_IMPLEMENTATION_NAME, DEPRECATED_SUFFIX),
            liveImpl
        );

        if (addresses.isAddressSet(MORPHO_IMPLEMENTATION_NAME)) {
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

    /// @notice Read the ERC1967 implementation slot of every Base Morpho wrapper
    /// proxy; all must share one impl and it must be the registered _IMPL_V2.
    function _liveMorphoImplementation(
        Addresses addresses
    ) internal view returns (address liveImpl) {
        MorphoOracleConfig[]
            memory morphoConfigs = getMorphoOracleConfigurations(block.chainid);
        require(morphoConfigs.length > 0, "MIP-X72: no Morpho wrappers");

        for (uint256 i = 0; i < morphoConfigs.length; i++) {
            address impl = _implementationOf(
                addresses.getAddress(
                    string.concat(morphoConfigs[i].proxyName, "_ORACLE_PROXY")
                )
            );
            if (i == 0) {
                liveImpl = impl;
            } else {
                require(
                    impl == liveImpl,
                    "MIP-X72: Morpho wrapper proxies run different implementations"
                );
            }
        }

        require(
            liveImpl == addresses.getAddress(MORPHO_LIVE_IMPLEMENTATION_NAME),
            "MIP-X72: live Morpho wrapper implementation is not CHAINLINK_OEV_MORPHO_WRAPPER_IMPL_V2"
        );
    }

    /// @notice ERC1967 implementation address of a proxy.
    function _implementationOf(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, _IMPLEMENTATION_SLOT))));
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
        _snapshotComposites(addresses);
        vm.selectFork(primaryForkId());
    }

    /// @notice Snapshot getUnderlyingPrice for every market whose composite is rebuilt.
    function _snapshotComposites(Addresses addresses) internal {
        vm.selectFork(BASE_FORK_ID);

        CompositeOracleConfig[]
            memory configs = getCompositeOracleConfigurations(BASE_CHAIN_ID);
        ChainlinkOracle oracle = ChainlinkOracle(
            addresses.getAddress("CHAINLINK_ORACLE")
        );

        for (uint256 i = 0; i < configs.length; i++) {
            if (!_compositeRebuilt(addresses, configs[i])) {
                continue;
            }
            // LBTC's RedStone leg reverts when a fork is warped behind its last update.
            try
                oracle.getUnderlyingPrice(
                    MToken(addresses.getAddress(configs[i].mTokenKey))
                )
            returns (uint256 price) {
                _compositePricePre[configs[i].mTokenKey] = price;
            } catch {}
        }
    }

    function _compositeRebuilt(
        Addresses addresses,
        CompositeOracleConfig memory config
    ) internal view returns (bool) {
        return
            addresses.isAddressSet(
                string.concat(
                    config.compositeOracleName,
                    COMPOSITE_DEPRECATED_SUFFIX
                )
            );
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

                (, int256 wrapperAns, , , ) = ChainlinkOEVWrapper(
                    payable(addresses.getAddress(deprecatedName))
                ).latestRoundData();
                _wrapperAnswerPre[chainId][oracleName] = wrapperAns;
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
                implementation: _implementationOf(address(w)),
                taken: true
            });

            (, int256 ans, , , ) = w.latestRoundData();
            _morphoAnswerPre[wrapperName] = ans;
        }
    }

    function build(Addresses addresses) public override {
        vm.selectFork(BASE_FORK_ID);
        _wireCoreFeeds(addresses, BASE_CHAIN_ID);
        _wireCompositeFeeds(addresses, BASE_CHAIN_ID);
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

    /// @notice Repoint each market priced by a rebuilt composite at the new composite.
    function _wireCompositeFeeds(
        Addresses addresses,
        uint256 chainId
    ) internal {
        CompositeOracleConfig[]
            memory configs = getCompositeOracleConfigurations(chainId);
        address chainlinkOracle = addresses.getAddress("CHAINLINK_ORACLE");

        for (uint256 i = 0; i < configs.length; i++) {
            if (!_compositeRebuilt(addresses, configs[i])) {
                continue;
            }

            string memory symbol = ERC20(
                addresses.getAddress(configs[i].symbol)
            ).symbol();

            _pushAction(
                chainlinkOracle,
                abi.encodeWithSignature(
                    "setFeed(string,address)",
                    symbol,
                    addresses.getAddress(configs[i].compositeOracleName)
                ),
                string.concat(
                    "Repoint ",
                    symbol,
                    " feed at composite oracle using the standard Chainlink proxy"
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
                "MIP-X72: Morpho wrapper proxy not registered"
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
        _validateCompositeOracles(addresses, BASE_CHAIN_ID);
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
                string.concat("X72: feed not repointed for ", symbol)
            );
            assertTrue(
                address(newWrapper) != address(oldWrapper),
                string.concat("X72: wrapper not redeployed for ", wrapperName)
            );
            _assertStandardFeed(
                addresses,
                oracleConfigs[i].oracleName,
                address(newWrapper.priceFeed()),
                address(oldWrapper.priceFeed()),
                wrapperName
            );
            assertEq(
                newWrapper.owner(),
                oldWrapper.owner(),
                string.concat("X72: owner drift for ", wrapperName)
            );
            assertEq(
                address(newWrapper.chainlinkOracle()),
                address(oldWrapper.chainlinkOracle()),
                string.concat("X72: chainlinkOracle drift for ", wrapperName)
            );
            assertEq(
                newWrapper.feeRecipient(),
                oldWrapper.feeRecipient(),
                string.concat("X72: feeRecipient drift for ", wrapperName)
            );
            assertEq(
                newWrapper.liquidatorFeeBps(),
                oldWrapper.liquidatorFeeBps(),
                string.concat("X72: liquidatorFeeBps drift for ", wrapperName)
            );
            assertEq(
                newWrapper.maxRoundDelay(),
                oldWrapper.maxRoundDelay(),
                string.concat("X72: maxRoundDelay drift for ", wrapperName)
            );
            assertEq(
                newWrapper.maxDecrements(),
                oldWrapper.maxDecrements(),
                string.concat("X72: maxDecrements drift for ", wrapperName)
            );
            assertGt(
                newWrapper.cachedRoundId(),
                0,
                string.concat("X72: cachedRoundId unseeded for ", wrapperName)
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

    /// @notice New feed is the canonical one; it differs from the old feed only when
    /// the old feed was the registered SVR proxy of the same aggregator.
    function _assertStandardFeed(
        Addresses addresses,
        string memory feedName,
        address newFeed,
        address oldFeed,
        string memory label
    ) internal view {
        assertEq(
            newFeed,
            addresses.getAddress(feedName),
            string.concat("X72: feed is not the standard proxy for ", label)
        );
        if (newFeed != oldFeed) {
            assertEq(
                oldFeed,
                addresses.getAddress(string.concat(feedName, SVR_SUFFIX)),
                string.concat(
                    "X72: replaced feed is not the SVR proxy for ",
                    label
                )
            );
            assertEq(
                IChainlinkAggregatorProxy(newFeed).aggregator(),
                IChainlinkAggregatorProxy(oldFeed).aggregator(),
                string.concat(
                    "X72: standard and SVR proxies differ in aggregator for ",
                    label
                )
            );
        }
    }

    /// @notice Assert each rebuilt composite: feed repointed, standard base, multipliers
    /// mirrored, and the market price within 2% of the pre-execution snapshot.
    function _validateCompositeOracles(
        Addresses addresses,
        uint256 chainId
    ) internal view {
        CompositeOracleConfig[]
            memory configs = getCompositeOracleConfigurations(chainId);
        ChainlinkOracle oracle = ChainlinkOracle(
            addresses.getAddress("CHAINLINK_ORACLE")
        );

        for (uint256 i = 0; i < configs.length; i++) {
            string memory name_ = configs[i].compositeOracleName;
            ChainlinkCompositeOracle composite = ChainlinkCompositeOracle(
                addresses.getAddress(name_)
            );

            // Every composite must end on the standard base, rebuilt or not.
            assertEq(
                composite.base(),
                addresses.getAddress(configs[i].baseFeedName),
                string.concat("X72: composite base is not standard for ", name_)
            );

            if (!_compositeRebuilt(addresses, configs[i])) {
                console.log(
                    string.concat(
                        "[",
                        _chainLabel(chainId),
                        "] ",
                        name_,
                        ": not rebuilt"
                    )
                );
                continue;
            }

            ChainlinkCompositeOracle old = ChainlinkCompositeOracle(
                addresses.getAddress(
                    string.concat(name_, COMPOSITE_DEPRECATED_SUFFIX)
                )
            );
            string memory symbol = ERC20(
                addresses.getAddress(configs[i].symbol)
            ).symbol();

            assertEq(
                address(oracle.getFeed(symbol)),
                address(composite),
                string.concat("X72: feed not repointed for ", symbol)
            );
            _assertStandardFeed(
                addresses,
                configs[i].baseFeedName,
                composite.base(),
                old.base(),
                name_
            );
            assertEq(
                composite.multiplier(),
                old.multiplier(),
                string.concat("X72: multiplier drift for ", name_)
            );
            assertEq(
                composite.secondMultiplier(),
                old.secondMultiplier(),
                string.concat("X72: secondMultiplier drift for ", name_)
            );

            // Price neutrality follows from the shared aggregator and mirrored
            // multipliers; the live read is a best-effort cross-check.
            uint256 pre = _compositePricePre[configs[i].mTokenKey];
            if (pre == 0) {
                console.log(
                    string.concat(
                        "[",
                        _chainLabel(chainId),
                        "] ",
                        configs[i].mTokenKey,
                        " getUnderlyingPrice: no pre-execution snapshot"
                    )
                );
                continue;
            }
            try
                oracle.getUnderlyingPrice(
                    MToken(addresses.getAddress(configs[i].mTokenKey))
                )
            returns (uint256 post) {
                _logPrice(
                    chainId,
                    string.concat(configs[i].mTokenKey, " getUnderlyingPrice"),
                    int256(pre),
                    int256(post)
                );
                assertApproxEqRel(
                    post,
                    pre,
                    0.02e18,
                    string.concat(
                        "X72: getUnderlyingPrice drifted >2% for ",
                        configs[i].mTokenKey
                    )
                );
            } catch {
                console.log(
                    string.concat(
                        "[",
                        _chainLabel(chainId),
                        "] ",
                        configs[i].mTokenKey,
                        " getUnderlyingPrice | pre: ",
                        vm.toString(pre),
                        " | post: reverted"
                    )
                );
            }
        }
    }

    /// @notice Pass-through check: the wrapper must report the aggregator's own data
    /// for the round it selected, read at the same instant. Covers both branches of
    /// the round-delay logic (latest round, or an earlier one while latest is fresh).
    function _assertForwardsRawRound(
        address rawFeed,
        ChainlinkOEVWrapper newWrapper,
        string memory wrapperName
    ) internal view {
        (uint80 roundId, int256 ans, , uint256 up, ) = newWrapper
            .latestRoundData();
        (, int256 rawAns, , uint256 rawUp, ) = AggregatorV3Interface(rawFeed)
            .getRoundData(roundId);
        assertEq(
            ans,
            rawAns,
            string.concat("X72: answer != raw round for ", wrapperName)
        );
        assertEq(
            up,
            rawUp,
            string.concat("X72: updatedAt != raw round for ", wrapperName)
        );
    }

    /// @notice Price neutrality: bounded, not exact. The integration forks are
    /// unpinned, so the aggregator publishes rounds while the simulation runs.
    function _assertRawAnswerNearPre(
        uint256 chainId,
        string memory oracleName,
        ChainlinkOEVWrapper newWrapper,
        string memory wrapperName
    ) internal view {
        int256 pre = _rawAnswerPre[chainId][oracleName];
        if (pre <= 0) {
            return;
        }
        (, int256 ans, , , ) = newWrapper.latestRoundData();
        assertGt(
            ans,
            0,
            string.concat("X72: non-positive answer for ", wrapperName)
        );
        assertApproxEqRel(
            uint256(ans),
            uint256(pre),
            0.02e18,
            string.concat("X72: answer drifted >2% for ", wrapperName)
        );
    }

    /// @notice Assert the redeployed wrapper is price-neutral: exact pass-through of
    /// the raw aggregator, plus a bounded drift check against the pre-execution
    /// snapshot. getUnderlyingPrice allows 2% for the same reason.
    function _assertCorePricePreserved(
        Addresses addresses,
        uint256 chainId,
        OracleConfig memory config,
        ChainlinkOEVWrapper newWrapper,
        string memory wrapperName
    ) internal view {
        _assertForwardsRawRound(
            addresses.getAddress(config.oracleName),
            newWrapper,
            wrapperName
        );
        _assertRawAnswerNearPre(
            chainId,
            config.oracleName,
            newWrapper,
            wrapperName
        );

        (, int256 wrapperAns, , , ) = newWrapper.latestRoundData();
        _logPrice(
            chainId,
            string.concat(wrapperName, " latestRoundData"),
            _wrapperAnswerPre[chainId][config.oracleName],
            wrapperAns
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
                _logPrice(
                    chainId,
                    string.concat(config.mTokenKey, " getUnderlyingPrice"),
                    int256(pre),
                    int256(post)
                );
                assertApproxEqRel(
                    post,
                    pre,
                    0.02e18,
                    string.concat(
                        "X72: getUnderlyingPrice drifted >2% for ",
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
        address archivedImpl = addresses.getAddress(
            string.concat(MORPHO_IMPLEMENTATION_NAME, DEPRECATED_SUFFIX)
        );
        address liveImplV2 = addresses.getAddress(
            MORPHO_LIVE_IMPLEMENTATION_NAME
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
                string.concat("X72 morpho upgrade: ", wrapperName)
            );

            MorphoSnapshot memory snap = _morphoSnap[wrapperName];
            require(snap.taken, "MIP-X72: missing Morpho snapshot");

            // The archive key records the impl the proxy ran pre-upgrade, which
            // is MIP-X56's _IMPL_V2; validateProxy above proves the slot moved.
            assertEq(
                archivedImpl,
                snap.implementation,
                string.concat(
                    "X72: archived morpho impl != pre-upgrade impl for ",
                    wrapperName
                )
            );
            assertEq(
                snap.implementation,
                liveImplV2,
                string.concat(
                    "X72: pre-upgrade morpho impl != IMPL_V2 for ",
                    wrapperName
                )
            );

            ChainlinkOEVMorphoWrapper w = ChainlinkOEVMorphoWrapper(
                addresses.getAddress(wrapperName)
            );

            assertEq(
                address(w.priceFeed()),
                snap.priceFeed,
                string.concat("X72: morpho priceFeed reset for ", wrapperName)
            );
            assertEq(
                address(w.morphoBlue()),
                snap.morphoBlue,
                string.concat("X72: morpho morphoBlue reset for ", wrapperName)
            );
            assertEq(
                address(w.chainlinkOracle()),
                snap.chainlinkOracle,
                string.concat(
                    "X72: morpho chainlinkOracle reset for ",
                    wrapperName
                )
            );
            assertEq(
                w.feeRecipient(),
                snap.feeRecipient,
                string.concat(
                    "X72: morpho feeRecipient reset for ",
                    wrapperName
                )
            );
            assertEq(
                w.liquidatorFeeBps(),
                snap.liquidatorFeeBps,
                string.concat(
                    "X72: morpho liquidatorFeeBps reset for ",
                    wrapperName
                )
            );
            assertEq(
                w.maxRoundDelay(),
                snap.maxRoundDelay,
                string.concat(
                    "X72: morpho maxRoundDelay reset for ",
                    wrapperName
                )
            );
            assertEq(
                w.maxDecrements(),
                snap.maxDecrements,
                string.concat(
                    "X72: morpho maxDecrements reset for ",
                    wrapperName
                )
            );
            assertEq(
                w.cachedRoundId(),
                snap.cachedRoundId,
                string.concat(
                    "X72: morpho cachedRoundId reset for ",
                    wrapperName
                )
            );
            assertEq(
                w.owner(),
                snap.owner,
                string.concat("X72: morpho owner reset for ", wrapperName)
            );

            // Liveness: the upgraded impl still serves a valid price. Storage is
            // asserted unchanged above and latestRoundData() logic is untouched by
            // the fix, so the consumer-facing output is preserved by construction;
            // a strict pre/post output equality would be fragile because a fresh
            // round can flip the delay state across the simulate() time warp.
            (, int256 ans, , , ) = w.latestRoundData();
            _logPrice(
                chainId,
                string.concat(wrapperName, " latestRoundData"),
                _morphoAnswerPre[wrapperName],
                ans
            );
            assertGt(
                ans,
                0,
                string.concat("X72: morpho price invalid for ", wrapperName)
            );
        }
    }

    /// @notice One line per feed: pre/post price and the delta in bps.
    function _logPrice(
        uint256 chainId,
        string memory label,
        int256 pre,
        int256 post
    ) internal view {
        string memory delta = pre == 0
            ? "n/a"
            : string.concat(vm.toString(((post - pre) * 10_000) / pre), " bps");
        console.log(
            string.concat(
                "[",
                _chainLabel(chainId),
                "] ",
                label,
                " | pre: ",
                vm.toString(pre),
                " | post: ",
                vm.toString(post),
                " | delta: ",
                delta
            )
        );
    }

    function _chainLabel(
        uint256 chainId
    ) internal pure returns (string memory) {
        if (chainId == BASE_CHAIN_ID) return "Base";
        if (chainId == OPTIMISM_CHAIN_ID) return "Optimism";
        if (chainId == ETHEREUM_CHAIN_ID) return "Ethereum";
        return "unknown";
    }
}
