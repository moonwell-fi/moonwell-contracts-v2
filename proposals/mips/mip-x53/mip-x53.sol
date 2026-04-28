//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {ChainlinkOEVWrapper} from "@protocol/oracles/ChainlinkOEVWrapper.sol";
import {ChainlinkOEVMorphoWrapper} from "@protocol/oracles/ChainlinkOEVMorphoWrapper.sol";
import {IOEVWrapperFeed} from "@protocol/oracles/IOEVWrapperFeed.sol";
import {MToken} from "@protocol/MToken.sol";
import {IChainlinkOracle} from "@protocol/interfaces/IChainlinkOracle.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ChainlinkOracleConfigs} from "@proposals/ChainlinkOracleConfigs.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";

/// @title MIP-X53: Fix Chainlink OEV loan-feed desync (full-coverage redeploy)
/// @notice Redeploys every Core OEV-wrapped Chainlink feed enumerated in
///         `ChainlinkOracleConfigs._oracleConfigs` on Base and Optimism using
///         a fresh `ChainlinkOEVWrapper` constructor (so the loan-feed
///         dereference fix is baked in), then re-wires `ChainlinkOracle` to
///         point each market's symbol at the new wrapper. Composite-wrapped
///         feeds and raw aggregators are left untouched. On Base the
///         `ChainlinkOEVMorphoWrapper` proxy implementation is also upgraded
///         to restore round-data validation parity (no reinitializer).
///
///         Each redeployed wrapper preserves the existing wrapper's full
///         configuration (priceFeed pointer, chainlinkOracle, feeRecipient,
///         owner, liquidatorFeeBps, maxRoundDelay, maxDecrements) — read live
///         from on-chain state — so the only change observable post-upgrade
///         is the loan-feed dereferencing logic inside the new bytecode.
contract mipx53 is HybridProposal, ChainlinkOracleConfigs {
    using ProposalActions for *;
    using ChainIds for uint256;

    string public constant override name = "MIP-X53";

    /// @notice Suffix appended to each oracleName to register the new wrapper
    ///         on the Addresses contract (e.g. CHAINLINK_USDC_USD_V3).
    string internal constant V3_SUFFIX = "_V3";

    /// @notice Snapshot of pre-upgrade Morpho wrapper proxy state, captured in
    ///         afterDeploy() and asserted in validate() to prove the proxy
    ///         upgrade preserved every storage variable. Storage on a
    ///         proposal contract instance is reused across lifecycle hooks.
    uint16 internal _preUpgradeLiquidatorFeeBps;
    uint256 internal _preUpgradeMaxRoundDelay;
    uint256 internal _preUpgradeMaxDecrements;
    address internal _preUpgradeFeeRecipient;
    address internal _preUpgradeOwner;
    address internal _preUpgradePriceFeed;
    address internal _preUpgradeChainlinkOracle;
    uint256 internal _preUpgradeCachedRoundId;
    address internal _preUpgradeMorphoBlue;
    int256 internal _baseMorphoAnswerPre;
    uint256 internal _baseMorphoUpdatedAtPre;
    uint8 internal _baseMorphoDecimalsPre;

    /// @notice Per-chain, per-oracleName snapshot of the raw aggregator's
    ///         answer and updatedAt captured immediately before simulation.
    ///         Used by validate() to prove the new wrapper points at the
    ///         same raw feed as the old one (block state is unchanged across
    ///         simulate, so a diff means a different aggregator was wired).
    mapping(uint256 => mapping(string => int256)) internal _rawAnswerPre;
    mapping(uint256 => mapping(string => uint256)) internal _rawUpdatedAtPre;

    /// @notice Per-chain, per-mTokenKey snapshot of the full
    ///         `ChainlinkOracle.getUnderlyingPrice(mToken)` resolution path
    ///         captured pre-simulation. Validated within ±2% post-upgrade.
    mapping(uint256 => mapping(string => uint256)) internal _underlyingPricePre;

    /// @notice Per-chain, ordered list of unique oracleNames identified as
    ///         live OEV wrappers in deploy(). Iterated in build()/validate().
    mapping(uint256 => string[]) internal _upgradedOracleNames;

    /// @notice Per-chain, per-oracleName snapshot of the existing wrapper's
    ///         constructor parameters, captured in deploy() so validate()
    ///         can assert exact mirroring on the new wrapper.
    struct WrapperParams {
        address priceFeed;
        address owner;
        address chainlinkOracle;
        address feeRecipient;
        uint16 liquidatorFeeBps;
        uint256 maxRoundDelay;
        uint256 maxDecrements;
    }
    mapping(uint256 => mapping(string => WrapperParams))
        internal _capturedParams;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-x53/x53.md")
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

        // Base only: deploy the new ChainlinkOEVMorphoWrapper implementation.
        // The proxy upgrade itself is queued in build() and executed via
        // governance — this just deploys the impl bytecode for it to point at.
        vm.selectFork(BASE_FORK_ID);
        if (
            !addresses.isAddressSet("CHAINLINK_WELL_USD_ORACLE_PROXY_IMPL_V2")
        ) {
            vm.startBroadcast();
            ChainlinkOEVMorphoWrapper impl = new ChainlinkOEVMorphoWrapper();
            vm.stopBroadcast();
            addresses.addAddress(
                "CHAINLINK_WELL_USD_ORACLE_PROXY_IMPL_V2",
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

            // Dedupe: skip if this oracleName has already been processed in
            // this chain's loop (e.g. CHAINLINK_USDC_USD covers USDC + USDBC).
            if (
                addresses.isAddressSet(
                    string.concat(config.oracleName, V3_SUFFIX)
                )
            ) {
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
            // wrapper can mirror it exactly. Using the live wrapper as the
            // source of truth (rather than addresses.getAddress(<name>_OEV_WRAPPER))
            // is robust to historical naming inconsistencies.
            WrapperParams memory params = _captureParams(registered);
            _capturedParams[chainId][config.oracleName] = params;

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

            addresses.addAddress(
                string.concat(config.oracleName, V3_SUFFIX),
                address(newWrapper)
            );
            _upgradedOracleNames[chainId].push(config.oracleName);
        }
    }

    /// @notice Snapshot the pre-upgrade Morpho wrapper proxy state on Base so
    ///         validate() can later assert exact equality post-upgrade. Runs
    ///         AFTER deploy() and BEFORE build()/simulate(), per the proposal
    ///         lifecycle.
    function afterDeploy(Addresses addresses, address) public override {
        vm.selectFork(BASE_FORK_ID);
        ChainlinkOEVMorphoWrapper proxy = ChainlinkOEVMorphoWrapper(
            payable(addresses.getAddress("CHAINLINK_WELL_USD_ORACLE_PROXY"))
        );
        _preUpgradeLiquidatorFeeBps = proxy.liquidatorFeeBps();
        _preUpgradeMaxRoundDelay = proxy.maxRoundDelay();
        _preUpgradeMaxDecrements = proxy.maxDecrements();
        _preUpgradeFeeRecipient = proxy.feeRecipient();
        _preUpgradeOwner = proxy.owner();
        _preUpgradePriceFeed = address(proxy.priceFeed());
        _preUpgradeChainlinkOracle = address(proxy.chainlinkOracle());
        _preUpgradeCachedRoundId = proxy.cachedRoundId();
        _preUpgradeMorphoBlue = address(proxy.morphoBlue());

        vm.selectFork(primaryForkId());
    }

    /// @notice Snapshot pre-simulation state for every upgrade target so
    ///         validate() can assert price preservation across the upgrade.
    function beforeSimulationHook(Addresses addresses) public override {
        _snapshotChain(addresses, BASE_FORK_ID, BASE_CHAIN_ID);
        _snapshotChain(addresses, OPTIMISM_FORK_ID, OPTIMISM_CHAIN_ID);

        // Base Morpho: capture proxy-side raw answer and decimals.
        vm.selectFork(BASE_FORK_ID);
        {
            ChainlinkOEVMorphoWrapper morpho = ChainlinkOEVMorphoWrapper(
                payable(addresses.getAddress("CHAINLINK_WELL_USD_ORACLE_PROXY"))
            );
            (, int256 ans, , uint256 updatedAt, ) = morpho
                .priceFeed()
                .latestRoundData();
            _baseMorphoAnswerPre = ans;
            _baseMorphoUpdatedAtPre = updatedAt;
            _baseMorphoDecimalsPre = morpho.decimals();
        }

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
            if (
                !addresses.isAddressSet(
                    string.concat(config.oracleName, V3_SUFFIX)
                )
            ) {
                // Not upgraded — was either skipped (raw feed) or no symbol.
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
    ///         upgraded wrapper × every symbol that maps to it, plus the
    ///         Morpho proxy upgrade on Base.
    function build(Addresses addresses) public override {
        _buildForChain(addresses, BASE_FORK_ID, BASE_CHAIN_ID);
        _buildForChain(addresses, OPTIMISM_FORK_ID, OPTIMISM_CHAIN_ID);

        // Base only: upgrade the ChainlinkOEVMorphoWrapper proxy. No
        // reinitializer — storage layout is preserved across the swap.
        vm.selectFork(BASE_FORK_ID);
        _pushAction(
            addresses.getAddress("CHAINLINK_ORACLE_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("CHAINLINK_WELL_USD_ORACLE_PROXY"),
                addresses.getAddress("CHAINLINK_WELL_USD_ORACLE_PROXY_IMPL_V2")
            ),
            "Base: upgrade ChainlinkOEVMorphoWrapper proxy implementation (no reinit)"
        );
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
            string memory v3Name = string.concat(config.oracleName, V3_SUFFIX);
            if (!addresses.isAddressSet(v3Name)) continue;

            (bool ok, string memory symbol) = _readSymbol(addresses, config);
            if (!ok) continue;

            address newWrapper = addresses.getAddress(v3Name);
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
                    ", new ChainlinkOEVWrapper V3 for ",
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

        // Morpho proxy upgrade — Base only, strict-equality block.
        vm.selectFork(BASE_FORK_ID);
        _validateMorphoWrapperState(addresses);
        _validatePricePreserved(
            ChainlinkOEVMorphoWrapper(
                payable(addresses.getAddress("CHAINLINK_WELL_USD_ORACLE_PROXY"))
            ).priceFeed(),
            _baseMorphoAnswerPre,
            _baseMorphoUpdatedAtPre,
            "Base Morpho"
        );
        {
            ChainlinkOEVMorphoWrapper morpho = ChainlinkOEVMorphoWrapper(
                payable(addresses.getAddress("CHAINLINK_WELL_USD_ORACLE_PROXY"))
            );
            assertEq(
                morpho.decimals(),
                _baseMorphoDecimalsPre,
                "Base Morpho: wrapper decimals changed across upgrade"
            );
        }

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
        string memory v3Name = string.concat(config.oracleName, V3_SUFFIX);
        if (!addresses.isAddressSet(v3Name)) return;

        address newWrapperAddr = addresses.getAddress(v3Name);

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

        // (4) Full-resolution path within ±2%.
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

    /// @notice Strict-equality check: every Morpho wrapper proxy state value
    ///         after the implementation swap must equal the value captured in
    ///         afterDeploy() before the upgrade.
    function _validateMorphoWrapperState(Addresses addresses) internal view {
        ChainlinkOEVMorphoWrapper wrapper = ChainlinkOEVMorphoWrapper(
            payable(addresses.getAddress("CHAINLINK_WELL_USD_ORACLE_PROXY"))
        );

        assertEq(
            wrapper.liquidatorFeeBps(),
            _preUpgradeLiquidatorFeeBps,
            "Base: Morpho wrapper liquidatorFeeBps changed by upgrade"
        );
        assertEq(
            wrapper.maxRoundDelay(),
            _preUpgradeMaxRoundDelay,
            "Base: Morpho wrapper maxRoundDelay changed by upgrade"
        );
        assertEq(
            wrapper.maxDecrements(),
            _preUpgradeMaxDecrements,
            "Base: Morpho wrapper maxDecrements changed by upgrade"
        );
        assertEq(
            wrapper.feeRecipient(),
            _preUpgradeFeeRecipient,
            "Base: Morpho wrapper feeRecipient changed by upgrade"
        );
        assertEq(
            wrapper.owner(),
            _preUpgradeOwner,
            "Base: Morpho wrapper owner changed by upgrade"
        );
        assertEq(
            address(wrapper.priceFeed()),
            _preUpgradePriceFeed,
            "Base: Morpho wrapper priceFeed changed by upgrade"
        );
        assertEq(
            address(wrapper.chainlinkOracle()),
            _preUpgradeChainlinkOracle,
            "Base: Morpho wrapper chainlinkOracle changed by upgrade"
        );
        assertEq(
            wrapper.cachedRoundId(),
            _preUpgradeCachedRoundId,
            "Base: Morpho wrapper cachedRoundId changed by upgrade"
        );
        assertEq(
            address(wrapper.morphoBlue()),
            _preUpgradeMorphoBlue,
            "Base: Morpho wrapper morphoBlue changed by upgrade"
        );

        // Cross-check expected-vs-snapshot to catch a pre-existing
        // misconfiguration the snapshot would otherwise mask.
        assertEq(
            wrapper.owner(),
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            "Base: Morpho wrapper owner should be TemporalGovernor"
        );
        assertEq(
            wrapper.feeRecipient(),
            addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER"),
            "Base: Morpho wrapper feeRecipient mismatch"
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
        return (false, AggregatorV3Interface(address(0)));
    }

    /// @notice Capture the constructor-mirroring parameters of a live
    ///         `ChainlinkOEVWrapper`-shaped contract.
    function _captureParams(
        address wrapperAddr
    ) internal view returns (WrapperParams memory params) {
        ChainlinkOEVWrapper w = ChainlinkOEVWrapper(payable(wrapperAddr));
        params.priceFeed = address(w.priceFeed());
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
