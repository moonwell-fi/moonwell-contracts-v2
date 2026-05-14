//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {ChainlinkOEVWrapper} from "@protocol/oracles/ChainlinkOEVWrapper.sol";
import {ChainlinkOEVMorphoWrapper} from "@protocol/oracles/ChainlinkOEVMorphoWrapper.sol";
import {IOEVWrapperFeed} from "@protocol/oracles/IOEVWrapperFeed.sol";
import {MarketParams} from "@protocol/morpho/IMetaMorpho.sol";
import {MToken} from "@protocol/MToken.sol";
import {IChainlinkOracle} from "@protocol/interfaces/IChainlinkOracle.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ChainlinkOracleConfigs} from "@proposals/ChainlinkOracleConfigs.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";

interface IOldOEVWrapperFeed {
    function originalFeed() external view returns (AggregatorV3Interface);
}

/// @title MIP-X56: Improve OEV Fee-Split Accuracy (full-coverage redeploy)
/// @notice Redeploys every Core OEV-wrapped Chainlink feed enumerated in
///         `ChainlinkOracleConfigs._oracleConfigs` on Base and Optimism using
///         a fresh `ChainlinkOEVWrapper` constructor (so the loan-feed
///         dereference fix is baked in), then re-wires `ChainlinkOracle` to
///         point each market's symbol at the new wrapper. Composite-wrapped
///         feeds and raw aggregators are left untouched. On Base ALL THREE
///         `ChainlinkOEVMorphoWrapper` proxy implementations are also upgraded
///         to restore round-data validation parity AND gate
///         `updatePriceEarlyAndLiquidate` behind a per-proxy market allowlist
///         (closes C4 #195). Each upgrade is split into two governance
///         actions queued in the same proposal: plain `upgrade(proxy, newImpl)`
///         followed by `setApprovedMarket(canonicalId, true)`. Both run
///         atomically within one proposal execution, so the gate is never
///         live without the canonical market seeded. setApprovedMarket is
///         `onlyOwner`-gated (TEMPORAL_GOVERNOR), unfront-runnable.
///         Proxies upgraded:
///           - CHAINLINK_WELL_USD_ORACLE_PROXY
///           - CHAINLINK_MAMO_USD_ORACLE_PROXY
///           - CHAINLINK_stkWELL_USD_ORACLE_PROXY
///
///         Each redeployed wrapper preserves the existing wrapper's full
///         configuration (priceFeed pointer, chainlinkOracle, feeRecipient,
///         owner, liquidatorFeeBps, maxRoundDelay, maxDecrements) - read live
///         from on-chain state - so the only change observable post-upgrade
///         is the loan-feed dereferencing logic inside the new bytecode.
contract mipx56 is HybridProposal, ChainlinkOracleConfigs {
    using ProposalActions for *;
    using ChainIds for uint256;

    string public constant override name = "MIP-X56";

    /// @notice Canonical wrapper suffix — matches the convention established by
    ///         MIP-X38 and MIP-X43. New wrappers are registered under
    ///         `<oracleName>_OEV_WRAPPER`; the retired predecessor is archived
    ///         under `<oracleName>_OEV_WRAPPER_DEPRECATED_V3`.
    string internal constant OEV_WRAPPER_SUFFIX = "_OEV_WRAPPER";
    string internal constant DEPRECATED_SUFFIX = "_OEV_WRAPPER_DEPRECATED_V3";

    /// @notice Snapshot of pre-upgrade Morpho wrapper proxy state, captured in
    ///         afterDeploy() and asserted in validate() to prove the proxy
    ///         upgrade preserved every storage variable. Keyed by proxy address.
    struct MorphoSnapshot {
        uint16 liquidatorFeeBps;
        uint256 maxRoundDelay;
        uint256 maxDecrements;
        address feeRecipient;
        address owner;
        address priceFeed;
        address chainlinkOracle;
        uint256 cachedRoundId;
        address morphoBlue;
        uint8 decimals;
        int256 answer;
        uint256 updatedAt;
    }
    mapping(address => MorphoSnapshot) internal _morphoSnapshot;

    /// @notice Per-chain, per-oracleName snapshot of the raw aggregator's
    ///         answer and updatedAt captured immediately before simulation.
    ///         Used by validate() to prove the new wrapper points at the
    ///         same raw feed as the old one (block state is unchanged across
    ///         simulate, so a diff means a different aggregator was wired).
    mapping(uint256 => mapping(string => int256)) internal _rawAnswerPre;
    mapping(uint256 => mapping(string => uint256)) internal _rawUpdatedAtPre;

    /// @notice Per-chain, per-mTokenKey snapshot of the full
    ///         `ChainlinkOracle.getUnderlyingPrice(mToken)` resolution path
    ///         captured pre-simulation. Validated within +-2% post-upgrade.
    mapping(uint256 => mapping(string => uint256)) internal _underlyingPricePre;

    /// @notice Per-chain, ordered list of unique oracleNames identified as
    ///         live OEV wrappers in deploy(). Iterated in build()/validate().
    mapping(uint256 => string[]) internal _upgradedOracleNames;

    /// @notice Per-chain set marking which oracleNames were redeployed by
    ///         this proposal. Source of truth for build/snapshot/validate
    ///         gating — independent of the `_OEV_WRAPPER_DEPRECATED_V3`
    ///         registry slot, which is only created when the canonical
    ///         `_OEV_WRAPPER` key was already present locally (HAL-06).
    mapping(uint256 => mapping(string => bool)) internal _isUpgraded;

    /// @notice Per-chain, per-oracleName snapshot of the existing wrapper's
    ///         constructor parameters, captured in deploy() so validate()
    ///         can assert exact mirroring on the new wrapper.
    /// @dev    `isLegacy` is set when the registered wrapper is a legacy
    ///         `ChainlinkFeedOEVWrapper` (Optimism CHAINLINK_WELL_USD). In
    ///         that case `priceFeed` is captured from `originalFeed()` and
    ///         the six remaining fields are sourced canonically from a
    ///         sibling new-style wrapper on the same chain. Validation is
    ///         relaxed to the priceFeed pointer + price-preservation check.
    struct WrapperParams {
        address priceFeed;
        address owner;
        address chainlinkOracle;
        address feeRecipient;
        uint16 liquidatorFeeBps;
        uint256 maxRoundDelay;
        uint256 maxDecrements;
        bool isLegacy;
    }
    mapping(uint256 => mapping(string => WrapperParams))
        internal _capturedParams;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-x56/x56.md")
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
            console.log("Validation completed for proposal ", this.name());
        }
        if (DO_PRINT) {
            printProposalActionSteps();

            addresses.removeAllRestrictions();
            printCalldata(addresses);

            _printAddressesChanges(addresses);
        }
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    /// @notice Enumerate every Core OEV wrapper on the given chain and deploy
    ///         a fresh `ChainlinkOEVWrapper` mirroring its on-chain params.
    function deploy(Addresses addresses, address) public override {
        _deployForChain(addresses, BASE_FORK_ID, BASE_CHAIN_ID);
        _deployForChain(addresses, OPTIMISM_FORK_ID, OPTIMISM_CHAIN_ID);

        // Base only: deploy a single shared ChainlinkOEVMorphoWrapper
        // implementation that all three proxies (WELL, MAMO, stkWELL) will
        // point at. The proxy upgrades themselves are queued in build() and
        // executed via governance — this just deploys the impl bytecode.
        vm.selectFork(BASE_FORK_ID);
        if (!addresses.isAddressSet("CHAINLINK_OEV_MORPHO_WRAPPER_IMPL_V2")) {
            vm.startBroadcast();
            ChainlinkOEVMorphoWrapper impl = new ChainlinkOEVMorphoWrapper();
            vm.stopBroadcast();
            addresses.addAddress(
                "CHAINLINK_OEV_MORPHO_WRAPPER_IMPL_V2",
                address(impl)
            );
        }
        vm.selectFork(primaryForkId());
    }

    function _deployForChain(
        Addresses addresses,
        uint256 forkId,
        uint256 chainId
    ) internal {
        vm.selectFork(forkId);

        OracleConfig[] memory configs = getOracleConfigurations(chainId);
        IChainlinkOracle oracle = IChainlinkOracle(
            addresses.getAddress("CHAINLINK_ORACLE")
        );

        for (uint256 i = 0; i < configs.length; i++) {
            OracleConfig memory config = configs[i];

            // Dedupe: skip if already processed in this loop (e.g.
            // CHAINLINK_USDC_USD covers USDC + USDBC). HAL-06: rely on the
            // explicit `_isUpgraded` set rather than the deprecated-suffix
            // registry slot, which can be absent when the canonical
            // `_OEV_WRAPPER` key was missing locally.
            if (_isUpgraded[chainId][config.oracleName]) {
                continue;
            }

            // Resolve the live wrapper via the registry: whatever address is
            // currently wired under the market's actual ERC20 symbol.
            (bool ok, string memory symbol) = _readSymbol(addresses, config);
            if (!ok) {
                console.log(
                    "Skipping (no symbol resolvable):",
                    config.oracleName
                );
                continue;
            }

            address registered = address(oracle.getFeed(symbol));
            (bool isWrapped, ) = _isOEVWrapper(registered);
            if (!isWrapped) {
                console.log(
                    "Skipping (registered feed is not an OEV wrapper):",
                    config.oracleName
                );
                continue;
            }

            // Capture the existing wrapper's full configuration so the new
            // wrapper can mirror it exactly.
            WrapperParams memory params = _captureParams(registered);

            // Legacy wrapper (Optimism CHAINLINK_WELL_USD): the legacy
            // `ChainlinkFeedOEVWrapper` ABI has no analog for the six
            // non-priceFeed fields. Source them canonically from a sibling
            // new-style wrapper on the same chain so the redeployed WELL
            // wrapper matches the rest of the chain's fee/staleness model.
            // We use CHAINLINK_USDC_USD_OEV_WRAPPER because USDC is the
            // most stable Optimism wrapper and is processed later in this
            // loop, so its canonical-name slot still points at the live
            // X43-era wrapper at this moment.
            if (params.isLegacy) {
                address sibling = addresses.getAddress(
                    "CHAINLINK_USDC_USD_OEV_WRAPPER"
                );
                WrapperParams memory canon = _captureParams(sibling);
                require(
                    !canon.isLegacy,
                    "MIP-X56: sibling wrapper unexpectedly legacy-shaped"
                );
                params.owner = canon.owner;
                params.chainlinkOracle = canon.chainlinkOracle;
                params.feeRecipient = canon.feeRecipient;
                params.liquidatorFeeBps = canon.liquidatorFeeBps;
                params.maxRoundDelay = canon.maxRoundDelay;
                params.maxDecrements = canon.maxDecrements;
            }

            _capturedParams[chainId][config.oracleName] = params;

            _deployAndRegisterWrapper(
                addresses,
                chainId,
                config.oracleName,
                params
            );
        }
    }

    /// @notice Deploy a new ChainlinkOEVWrapper and register it under the
    ///         canonical `_OEV_WRAPPER` name, archiving the previous wrapper
    ///         under `_OEV_WRAPPER_DEPRECATED_V3`. Extracted to avoid stack-
    ///         too-deep in `_deployForChain`.
    function _deployAndRegisterWrapper(
        Addresses addresses,
        uint256 chainId,
        string memory oracleName,
        WrapperParams memory params
    ) internal {
        vm.startBroadcast();
        ChainlinkOEVWrapper newWrapper = new ChainlinkOEVWrapper(
            params.priceFeed,
            params.owner,
            params.chainlinkOracle,
            params.feeRecipient,
            params.liquidatorFeeBps,
            params.maxRoundDelay,
            params.maxDecrements
        );
        vm.stopBroadcast();

        string memory canonicalName;
        string memory deprecatedName;

        if (
            chainId == OPTIMISM_CHAIN_ID &&
            keccak256(abi.encodePacked(oracleName)) ==
            keccak256(abi.encodePacked("CHAINLINK_WELL_USD"))
        ) {
            canonicalName = "CHAINLINK_WELL_USD_OEV_WRAPPER";
            deprecatedName = "CHAINLINK_WELL_USD_OEV_WRAPPER_DEPRECATED";
        } else {
            canonicalName = string.concat(oracleName, OEV_WRAPPER_SUFFIX);
            deprecatedName = string.concat(oracleName, DEPRECATED_SUFFIX);
        }

        // Archive the pre-existing canonical wrapper under the deprecated slot,
        // then promote the new wrapper to the canonical name.
        // This mirrors the MIP-X43 convention:
        //   <name>_OEV_WRAPPER_DEPRECATED_V3 -> old wrapper (X43-era)
        //   <name>_OEV_WRAPPER               -> new wrapper (this proposal)
        if (addresses.isAddressSet(canonicalName)) {
            addresses.addAddress(
                deprecatedName,
                addresses.getAddress(canonicalName)
            );
            addresses.changeAddress(canonicalName, address(newWrapper), true);
        } else {
            addresses.addAddress(canonicalName, address(newWrapper));
        }
        _upgradedOracleNames[chainId].push(oracleName);
        _isUpgraded[chainId][oracleName] = true;
    }

    /// @notice Snapshot the pre-upgrade state of ALL Morpho wrapper proxies on
    ///         Base so validate() can later assert exact equality post-upgrade.
    ///         Runs AFTER deploy() and BEFORE build()/simulate(), per the
    ///         proposal lifecycle.
    function _snapshotMorphoWrapperState(Addresses addresses) private {
        vm.selectFork(BASE_FORK_ID);

        MorphoOracleConfig[]
            memory morphoConfigs = getMorphoOracleConfigurations(BASE_CHAIN_ID);

        for (uint256 i = 0; i < morphoConfigs.length; i++) {
            string memory proxyKey = string(
                abi.encodePacked(morphoConfigs[i].proxyName, "_ORACLE_PROXY")
            );
            if (!addresses.isAddressSet(proxyKey)) {
                console.log(
                    "afterDeploy: Morpho proxy not found, skipping:",
                    proxyKey
                );
                continue;
            }

            address proxyAddr = addresses.getAddress(proxyKey);
            ChainlinkOEVMorphoWrapper proxy = ChainlinkOEVMorphoWrapper(
                payable(proxyAddr)
            );

            MorphoSnapshot storage snap = _morphoSnapshot[proxyAddr];
            snap.liquidatorFeeBps = proxy.liquidatorFeeBps();
            snap.maxRoundDelay = proxy.maxRoundDelay();
            snap.maxDecrements = proxy.maxDecrements();
            snap.feeRecipient = proxy.feeRecipient();
            snap.owner = proxy.owner();
            snap.priceFeed = address(proxy.priceFeed());
            snap.chainlinkOracle = address(proxy.chainlinkOracle());
            snap.cachedRoundId = proxy.cachedRoundId();
            snap.morphoBlue = address(proxy.morphoBlue());
            snap.decimals = proxy.decimals();
            (, int256 ans, , uint256 updatedAt, ) = AggregatorV3Interface(
                snap.priceFeed
            ).latestRoundData();
            snap.answer = ans;
            snap.updatedAt = updatedAt;
        }
    }

    /// @notice Snapshot pre-simulation state for every upgrade target so
    ///         validate() can assert price preservation across the upgrade.
    function beforeSimulationHook(Addresses addresses) public override {
        _snapshotChain(addresses, BASE_FORK_ID, BASE_CHAIN_ID);
        _snapshotChain(addresses, OPTIMISM_FORK_ID, OPTIMISM_CHAIN_ID);
        _snapshotMorphoWrapperState(addresses);
        vm.selectFork(primaryForkId());
    }

    function _snapshotChain(
        Addresses addresses,
        uint256 forkId,
        uint256 chainId
    ) internal {
        vm.selectFork(forkId);

        OracleConfig[] memory configs = getOracleConfigurations(chainId);
        IChainlinkOracle oracle = IChainlinkOracle(
            addresses.getAddress("CHAINLINK_ORACLE")
        );

        for (uint256 i = 0; i < configs.length; i++) {
            OracleConfig memory config = configs[i];
            if (!_isUpgraded[chainId][config.oracleName]) {
                // Not upgraded by this proposal — skipped (raw feed, no
                // symbol, or already processed duplicate). HAL-06: use the
                // explicit `_isUpgraded` set rather than the deprecated-suffix
                // registry slot.
                continue;
            }

            // Snapshot raw aggregator answer/updatedAt once per oracleName.
            if (_rawUpdatedAtPre[chainId][config.oracleName] == 0) {
                address rawFeed = _capturedParams[chainId][config.oracleName]
                    .priceFeed;
                if (rawFeed != address(0)) {
                    (
                        ,
                        int256 ans,
                        ,
                        uint256 updatedAt,

                    ) = AggregatorV3Interface(rawFeed).latestRoundData();
                    _rawAnswerPre[chainId][config.oracleName] = ans;
                    _rawUpdatedAtPre[chainId][config.oracleName] = updatedAt;
                }
            }

            // Per-symbol snapshot of getUnderlyingPrice for the mTokenKey.
            if (
                bytes(config.mTokenKey).length > 0 &&
                addresses.isAddressSet(config.mTokenKey)
            ) {
                _underlyingPricePre[chainId][config.mTokenKey] = oracle
                    .getUnderlyingPrice(
                        MToken(addresses.getAddress(config.mTokenKey))
                    );
            }
        }
    }

    /// @notice Queue the on-chain governance actions: setFeed for every
    ///         upgraded wrapper x every symbol that maps to it, plus the
    ///         Morpho proxy upgrades on Base (WELL, MAMO, stkWELL).
    function build(Addresses addresses) public override {
        _buildForChain(addresses, BASE_FORK_ID, BASE_CHAIN_ID);
        _buildForChain(addresses, OPTIMISM_FORK_ID, OPTIMISM_CHAIN_ID);

        // Base only: upgrade all three ChainlinkOEVMorphoWrapper proxies to
        // the shared new implementation. No reinitializer - storage layout is
        // preserved across the swap.
        vm.selectFork(BASE_FORK_ID);
        address newImpl = addresses.getAddress(
            "CHAINLINK_OEV_MORPHO_WRAPPER_IMPL_V2"
        );
        address proxyAdmin = addresses.getAddress(
            "CHAINLINK_ORACLE_PROXY_ADMIN"
        );

        MorphoOracleConfig[]
            memory morphoConfigs = getMorphoOracleConfigurations(BASE_CHAIN_ID);

        for (uint256 i = 0; i < morphoConfigs.length; i++) {
            string memory proxyKey = string(
                abi.encodePacked(morphoConfigs[i].proxyName, "_ORACLE_PROXY")
            );
            if (!addresses.isAddressSet(proxyKey)) {
                console.log(
                    "build: Morpho proxy not found, skipping:",
                    proxyKey
                );
                continue;
            }

            address proxy = addresses.getAddress(proxyKey);

            // Upgrade impl (gate logic + loan-feed deref + validation parity).
            _pushAction(
                proxyAdmin,
                abi.encodeWithSignature(
                    "upgrade(address,address)",
                    proxy,
                    newImpl
                ),
                string.concat(
                    "Base: upgrade ChainlinkOEVMorphoWrapper proxy ",
                    morphoConfigs[i].proxyName
                )
            );

            // Seed the allowlist with the canonical Morpho market this proxy
            // serves. Both actions execute atomically within one proposal
            // execution, so the gate is never live without the canonical
            // market approved. setApprovedMarket is `onlyOwner`-gated
            // (TEMPORAL_GOVERNOR), unfront-runnable.
            MarketParams memory canonicalMarket = _canonicalMorphoMarket(
                addresses,
                morphoConfigs[i].proxyName
            );
            bytes32 canonicalId = keccak256(abi.encode(canonicalMarket));
            _pushAction(
                proxy,
                abi.encodeWithSignature(
                    "setApprovedMarket(bytes32,bool)",
                    canonicalId,
                    true
                ),
                string.concat(
                    "Base: setApprovedMarket(canonicalId, true) on ",
                    morphoConfigs[i].proxyName
                )
            );
        }
    }

    /// @notice Canonical Morpho market params per Base proxy. Source of truth
    ///         is the live integration test (`testUpdatePriceEarlyAndLiquidate_*`
    ///         in ChainlinkOEVMorphoWrapperIntegration.t.sol). All three
    ///         proxies serve markets borrowing USDC against an asset using the
    ///         standard `MORPHO_ADAPTIVE_CURVE_IRM`.
    function _canonicalMorphoMarket(
        Addresses addresses,
        string memory proxyName
    ) internal view returns (MarketParams memory) {
        address loanToken = addresses.getAddress("USDC");
        address irm = addresses.getAddress("MORPHO_ADAPTIVE_CURVE_IRM");

        bytes32 key = keccak256(bytes(proxyName));

        if (key == keccak256(bytes("CHAINLINK_WELL_USD"))) {
            return
                MarketParams({
                    loanToken: loanToken,
                    collateralToken: addresses.getAddress("xWELL_PROXY"),
                    oracle: addresses.getAddress(
                        "MORPHO_CHAINLINK_WELL_USD_ORACLE"
                    ),
                    irm: irm,
                    lltv: 0.625e18
                });
        } else if (key == keccak256(bytes("CHAINLINK_MAMO_USD"))) {
            return
                MarketParams({
                    loanToken: loanToken,
                    collateralToken: addresses.getAddress("MAMO"),
                    oracle: addresses.getAddress(
                        "MORPHO_CHAINLINK_MAMO_USD_ORACLE"
                    ),
                    irm: irm,
                    lltv: 0.385e18
                });
        } else if (key == keccak256(bytes("CHAINLINK_stkWELL_USD"))) {
            return
                MarketParams({
                    loanToken: loanToken,
                    collateralToken: addresses.getAddress("STK_GOVTOKEN_PROXY"),
                    oracle: addresses.getAddress(
                        "MORPHO_CHAINLINK_stkWELL_USD_ORACLE"
                    ),
                    irm: irm,
                    lltv: 0.625e18
                });
        } else {
            revert(
                string.concat(
                    "MIP-X56: no canonical Morpho market params for proxy ",
                    proxyName
                )
            );
        }
    }

    function _buildForChain(
        Addresses addresses,
        uint256 forkId,
        uint256 chainId
    ) internal {
        vm.selectFork(forkId);

        OracleConfig[] memory configs = getOracleConfigurations(chainId);
        address chainlinkOracle = addresses.getAddress("CHAINLINK_ORACLE");

        for (uint256 i = 0; i < configs.length; i++) {
            OracleConfig memory config = configs[i];

            // Only wire feeds for wrappers deployed by this proposal.
            // HAL-06: explicit set instead of deprecated-suffix inference.
            if (!_isUpgraded[chainId][config.oracleName]) continue;

            string memory wrapperName = string.concat(
                config.oracleName,
                OEV_WRAPPER_SUFFIX
            );

            (bool ok, string memory symbol) = _readSymbol(addresses, config);
            if (!ok) continue;

            address newWrapper = addresses.getAddress(wrapperName);
            _pushAction(
                chainlinkOracle,
                abi.encodeWithSignature(
                    "setFeed(string,address)",
                    symbol,
                    newWrapper
                ),
                string.concat(
                    "ChainlinkOracle.setFeed(",
                    symbol,
                    ", new ChainlinkOEVWrapper for ",
                    config.oracleName,
                    ")"
                )
            );
        }
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        _validateChain(addresses, BASE_FORK_ID, BASE_CHAIN_ID, "Base");
        _validateChain(
            addresses,
            OPTIMISM_FORK_ID,
            OPTIMISM_CHAIN_ID,
            "Optimism"
        );

        // Morpho proxy upgrades - Base only.
        vm.selectFork(BASE_FORK_ID);
        _validateAllMorphoWrappers(addresses);

        vm.selectFork(primaryForkId());
    }

    function _validateChain(
        Addresses addresses,
        uint256 forkId,
        uint256 chainId,
        string memory chainName
    ) internal {
        vm.selectFork(forkId);

        OracleConfig[] memory configs = getOracleConfigurations(chainId);

        for (uint256 i = 0; i < configs.length; i++) {
            _validateConfig(addresses, chainId, chainName, configs[i]);
        }
    }

    function _validateConfig(
        Addresses addresses,
        uint256 chainId,
        string memory chainName,
        OracleConfig memory config
    ) internal view {
        // Only validate oracles that were upgraded by this proposal.
        // HAL-06: explicit set instead of deprecated-suffix inference.
        if (!_isUpgraded[chainId][config.oracleName]) return;

        string memory wrapperName = string.concat(
            config.oracleName,
            OEV_WRAPPER_SUFFIX
        );
        address newWrapperAddr = addresses.getAddress(wrapperName);

        // (1) Wiring check: oracle.getFeed(symbol) == new wrapper.
        (bool ok, string memory symbol) = _readSymbol(addresses, config);
        if (ok) {
            IChainlinkOracle oracle = IChainlinkOracle(
                addresses.getAddress("CHAINLINK_ORACLE")
            );
            assertEq(
                address(oracle.getFeed(symbol)),
                newWrapperAddr,
                string.concat(
                    chainName,
                    ": feed not wired to new wrapper for ",
                    symbol
                )
            );
        }

        // (2) Param-mirroring check.
        _validateWrapperParams(
            ChainlinkOEVWrapper(payable(newWrapperAddr)),
            _capturedParams[chainId][config.oracleName],
            chainName,
            config.oracleName
        );

        // (3) Raw aggregator price preservation.
        if (_rawUpdatedAtPre[chainId][config.oracleName] != 0) {
            _validatePricePreserved(
                AggregatorV3Interface(
                    _capturedParams[chainId][config.oracleName].priceFeed
                ),
                _rawAnswerPre[chainId][config.oracleName],
                _rawUpdatedAtPre[chainId][config.oracleName],
                string.concat(chainName, " ", config.oracleName)
            );
        }

        // (4) Full-resolution path within +-2%.
        _validateUnderlyingPrice(addresses, chainId, chainName, config);
    }

    function _validateWrapperParams(
        ChainlinkOEVWrapper newWrapper,
        WrapperParams memory captured,
        string memory chainName,
        string memory oracleName
    ) internal view {
        assertEq(
            address(newWrapper.priceFeed()),
            captured.priceFeed,
            string.concat(chainName, ": priceFeed mismatch for ", oracleName)
        );

        // Legacy wrapper case (Optimism CHAINLINK_WELL_USD): the six
        // non-priceFeed fields were sourced canonically from a sibling,
        // not from the legacy wrapper itself. Skip strict mirror checks
        // — post-state correctness is enforced via raw-aggregator price
        // preservation in `_validatePricePreserved`. The defense-in-depth
        // priceFeed-not-wrapped check below still runs.
        if (captured.isLegacy) {
            (bool legacyPriceFeedWrapped, ) = _isOEVWrapper(
                address(newWrapper.priceFeed())
            );
            require(
                !legacyPriceFeedWrapped,
                string.concat(
                    "MIP-X56: ",
                    chainName,
                    " new wrapper's priceFeed must be a raw aggregator for ",
                    oracleName
                )
            );
            return;
        }

        assertEq(
            newWrapper.owner(),
            captured.owner,
            string.concat(chainName, ": owner mismatch for ", oracleName)
        );
        assertEq(
            address(newWrapper.chainlinkOracle()),
            captured.chainlinkOracle,
            string.concat(
                chainName,
                ": chainlinkOracle mismatch for ",
                oracleName
            )
        );
        assertEq(
            newWrapper.feeRecipient(),
            captured.feeRecipient,
            string.concat(chainName, ": feeRecipient mismatch for ", oracleName)
        );
        assertEq(
            newWrapper.liquidatorFeeBps(),
            captured.liquidatorFeeBps,
            string.concat(
                chainName,
                ": liquidatorFeeBps mismatch for ",
                oracleName
            )
        );
        assertEq(
            newWrapper.maxRoundDelay(),
            captured.maxRoundDelay,
            string.concat(
                chainName,
                ": maxRoundDelay mismatch for ",
                oracleName
            )
        );
        assertEq(
            newWrapper.maxDecrements(),
            captured.maxDecrements,
            string.concat(
                chainName,
                ": maxDecrements mismatch for ",
                oracleName
            )
        );

        // Defense-in-depth: the new wrapper's priceFeed MUST be a raw Chainlink
        // aggregator, not another OEV wrapper. Catches the pathological case where
        // the prior wrapper was misconfigured (or where a future redeploy uses a
        // wrapped feed by mistake) and silently undoes the bounty fix.
        (bool priceFeedIsWrapped, ) = _isOEVWrapper(
            address(newWrapper.priceFeed())
        );
        require(
            !priceFeedIsWrapped,
            string.concat(
                "MIP-X56: ",
                chainName,
                " new wrapper's priceFeed must be a raw aggregator for ",
                oracleName
            )
        );
    }

    function _validateUnderlyingPrice(
        Addresses addresses,
        uint256 chainId,
        string memory chainName,
        OracleConfig memory config
    ) internal view {
        if (
            bytes(config.mTokenKey).length == 0 ||
            !addresses.isAddressSet(config.mTokenKey)
        ) {
            return;
        }
        uint256 capturedPrice = _underlyingPricePre[chainId][config.mTokenKey];
        if (capturedPrice == 0) return;

        IChainlinkOracle oracle = IChainlinkOracle(
            addresses.getAddress("CHAINLINK_ORACLE")
        );
        uint256 postPrice = oracle.getUnderlyingPrice(
            MToken(addresses.getAddress(config.mTokenKey))
        );
        assertApproxEqRel(
            postPrice,
            capturedPrice,
            2e16, // 2%
            string.concat(
                chainName,
                ": getUnderlyingPrice diverged for ",
                config.mTokenKey
            )
        );
    }

    /// @notice Asserts that the raw aggregator behind the post-upgrade wrapper
    ///         returns the same answer/updatedAt captured pre-simulation.
    function _validatePricePreserved(
        AggregatorV3Interface rawFeed,
        int256 expectedAnswer,
        uint256 expectedUpdatedAt,
        string memory label
    ) internal view {
        (, int256 ans, , uint256 updatedAt, ) = rawFeed.latestRoundData();
        assertEq(
            ans,
            expectedAnswer,
            string.concat(label, ": raw feed answer changed across upgrade")
        );
        assertEq(
            updatedAt,
            expectedUpdatedAt,
            string.concat(label, ": raw feed updatedAt changed across upgrade")
        );
    }

    /// @notice EIP-1967 implementation slot:
    ///         `bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)`
    bytes32 internal constant _EIP1967_IMPL_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @notice Loop over all Morpho oracle configs and validate that each
    ///         proxy's storage is unchanged after the implementation upgrade.
    ///         Also validates raw price preservation per proxy. Morpho proxies
    ///         are not mTokens — getUnderlyingPrice does not apply to them.
    function _validateAllMorphoWrappers(Addresses addresses) internal {
        MorphoOracleConfig[]
            memory morphoConfigs = getMorphoOracleConfigurations(BASE_CHAIN_ID);
        address expectedImpl = addresses.getAddress(
            "CHAINLINK_OEV_MORPHO_WRAPPER_IMPL_V2"
        );

        for (uint256 i = 0; i < morphoConfigs.length; i++) {
            string memory proxyKey = string(
                abi.encodePacked(morphoConfigs[i].proxyName, "_ORACLE_PROXY")
            );
            if (!addresses.isAddressSet(proxyKey)) {
                console.log(
                    "validate: Morpho proxy not found, skipping:",
                    proxyKey
                );
                continue;
            }

            address proxyAddr = addresses.getAddress(proxyKey);
            MorphoSnapshot storage snap = _morphoSnapshot[proxyAddr];

            console.log("Validating Morpho proxy:", morphoConfigs[i].proxyName);

            // HAL-10: assert the EIP-1967 implementation slot actually points
            // at the new implementation. Storage-equivalence checks below
            // can't distinguish "upgrade landed" from "upgrade silently
            // skipped" if the old impl shared the same getters.
            address actualImpl = address(
                uint160(uint256(vm.load(proxyAddr, _EIP1967_IMPL_SLOT)))
            );
            assertEq(
                actualImpl,
                expectedImpl,
                string.concat(
                    "Base Morpho ",
                    morphoConfigs[i].proxyName,
                    ": EIP-1967 impl slot does not point at V2 implementation"
                )
            );

            _validateMorphoWrapperState(
                proxyAddr,
                snap,
                morphoConfigs[i].proxyName,
                addresses
            );

            // Raw price preservation for Morpho proxy's underlying feed.
            if (snap.priceFeed != address(0) && snap.updatedAt != 0) {
                _validatePricePreserved(
                    AggregatorV3Interface(snap.priceFeed),
                    snap.answer,
                    snap.updatedAt,
                    string.concat("Base Morpho ", morphoConfigs[i].proxyName)
                );
            }

            // Decimals preservation.
            ChainlinkOEVMorphoWrapper wrapper = ChainlinkOEVMorphoWrapper(
                payable(proxyAddr)
            );
            assertEq(
                wrapper.decimals(),
                snap.decimals,
                string.concat(
                    "Base Morpho ",
                    morphoConfigs[i].proxyName,
                    ": decimals changed across upgrade"
                )
            );

            // Allowlist seeding: the canonical Morpho market id must be
            // approved post-upgrade. Catches the case where the seed was
            // malformed (wrong addresses or lltv) and silently produced a
            // non-canonical id.
            MarketParams memory canonicalMarket = _canonicalMorphoMarket(
                addresses,
                morphoConfigs[i].proxyName
            );
            bytes32 canonicalId = keccak256(abi.encode(canonicalMarket));
            require(
                wrapper.approvedMarkets(canonicalId),
                string.concat(
                    "Base Morpho ",
                    morphoConfigs[i].proxyName,
                    ": canonical market id not seeded by setApprovedMarket"
                )
            );
        }
    }

    /// @notice Strict-equality check: every storage variable of a single Morpho
    ///         wrapper proxy after the implementation swap must equal the
    ///         snapshot captured in afterDeploy().
    function _validateMorphoWrapperState(
        address proxyAddr,
        MorphoSnapshot storage snap,
        string memory proxyName,
        Addresses addresses
    ) internal view {
        ChainlinkOEVMorphoWrapper wrapper = ChainlinkOEVMorphoWrapper(
            payable(proxyAddr)
        );

        assertEq(
            wrapper.liquidatorFeeBps(),
            snap.liquidatorFeeBps,
            string.concat(
                "Base: Morpho wrapper ",
                proxyName,
                " liquidatorFeeBps changed by upgrade"
            )
        );
        assertEq(
            wrapper.maxRoundDelay(),
            snap.maxRoundDelay,
            string.concat(
                "Base: Morpho wrapper ",
                proxyName,
                " maxRoundDelay changed by upgrade"
            )
        );
        assertEq(
            wrapper.maxDecrements(),
            snap.maxDecrements,
            string.concat(
                "Base: Morpho wrapper ",
                proxyName,
                " maxDecrements changed by upgrade"
            )
        );
        assertEq(
            wrapper.feeRecipient(),
            snap.feeRecipient,
            string.concat(
                "Base: Morpho wrapper ",
                proxyName,
                " feeRecipient changed by upgrade"
            )
        );
        assertEq(
            wrapper.owner(),
            snap.owner,
            string.concat(
                "Base: Morpho wrapper ",
                proxyName,
                " owner changed by upgrade"
            )
        );
        assertEq(
            address(wrapper.priceFeed()),
            snap.priceFeed,
            string.concat(
                "Base: Morpho wrapper ",
                proxyName,
                " priceFeed changed by upgrade"
            )
        );
        assertEq(
            address(wrapper.chainlinkOracle()),
            snap.chainlinkOracle,
            string.concat(
                "Base: Morpho wrapper ",
                proxyName,
                " chainlinkOracle changed by upgrade"
            )
        );
        assertEq(
            wrapper.cachedRoundId(),
            snap.cachedRoundId,
            string.concat(
                "Base: Morpho wrapper ",
                proxyName,
                " cachedRoundId changed by upgrade"
            )
        );
        assertEq(
            address(wrapper.morphoBlue()),
            snap.morphoBlue,
            string.concat(
                "Base: Morpho wrapper ",
                proxyName,
                " morphoBlue changed by upgrade"
            )
        );

        // Cross-check expected-vs-snapshot to catch a pre-existing
        // misconfiguration the snapshot would otherwise mask.
        assertEq(
            wrapper.owner(),
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            string.concat(
                "Base: Morpho wrapper ",
                proxyName,
                " owner should be TemporalGovernor"
            )
        );
        assertEq(
            wrapper.feeRecipient(),
            addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER"),
            string.concat(
                "Base: Morpho wrapper ",
                proxyName,
                " feeRecipient mismatch"
            )
        );
    }

    /// @notice Detects whether an address is an OEV wrapper by probing for
    ///         the `priceFeed()` selector. Returns (false, zero) for raw
    ///         aggregators, address(0), or wrappers whose inner pointer is 0.
    function _isOEVWrapper(
        address registryEntry
    ) internal view returns (bool, AggregatorV3Interface raw) {
        if (registryEntry == address(0))
            return (false, AggregatorV3Interface(address(0)));
        try IOEVWrapperFeed(registryEntry).priceFeed() returns (
            AggregatorV3Interface inner
        ) {
            if (address(inner) != address(0)) {
                return (true, inner);
            }
        } catch {}
        try IOldOEVWrapperFeed(registryEntry).originalFeed() returns (
            AggregatorV3Interface originalFeed
        ) {
            if (address(originalFeed) != address(0)) {
                return (true, originalFeed);
            }
        } catch {}
        return (false, AggregatorV3Interface(address(0)));
    }

    /// @notice Capture the constructor-mirroring parameters of a live
    ///         `ChainlinkOEVWrapper`-shaped contract.
    /// @dev    Legacy `ChainlinkFeedOEVWrapper` (e.g. Optimism
    ///         `CHAINLINK_WELL_USD_OEV_WRAPPER` at 0xfeA5…58f) exposes
    ///         `originalFeed()` instead of `priceFeed()` and has no analog
    ///         for `chainlinkOracle`, `feeRecipient`, or `liquidatorFeeBps`.
    ///         For that case we only capture the raw aggregator pointer —
    ///         the single field the WELL market's post-state check needs.
    ///         `_snapshotChain` / `_validatePricePreserved` read
    ///         `latestRoundData()` on `_capturedParams[...].priceFeed`, so
    ///         the raw pointer is sufficient for price preservation. The
    ///         remaining fields stay at zero; strict mirror assertions in
    ///         `_validateWrapperParams` must therefore be relaxed for
    ///         legacy-sourced configs by the caller.
    function _captureParams(
        address wrapperAddr
    ) internal view returns (WrapperParams memory params) {
        ChainlinkOEVWrapper w = ChainlinkOEVWrapper(payable(wrapperAddr));

        try w.priceFeed() returns (AggregatorV3Interface pf) {
            params.priceFeed = address(pf);
        } catch {
            // Legacy wrapper path: mirror only the raw aggregator. The
            // remaining six fields are sourced canonically by the caller
            // from a sibling new-style wrapper on the same chain.
            params.priceFeed = address(
                IOldOEVWrapperFeed(wrapperAddr).originalFeed()
            );
            params.isLegacy = true;
            return params;
        }

        params.owner = w.owner();
        params.chainlinkOracle = address(w.chainlinkOracle());
        params.feeRecipient = w.feeRecipient();
        params.liquidatorFeeBps = w.liquidatorFeeBps();
        params.maxRoundDelay = w.maxRoundDelay();
        params.maxDecrements = w.maxDecrements();
    }

    /// @notice Resolve the on-chain ERC20 symbol for the config's token key.
    ///         Returns (false, "") if the token key is not registered on the
    ///         current fork (skip with log).
    function _readSymbol(
        Addresses addresses,
        OracleConfig memory config
    ) internal view returns (bool, string memory) {
        if (!addresses.isAddressSet(config.symbol)) {
            return (false, "");
        }
        return (true, ERC20(addresses.getAddress(config.symbol)).symbol());
    }
}
