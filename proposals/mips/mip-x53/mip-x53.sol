//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {ChainlinkOEVWrapper} from "@protocol/oracles/ChainlinkOEVWrapper.sol";
import {ChainlinkOEVMorphoWrapper} from "@protocol/oracles/ChainlinkOEVMorphoWrapper.sol";
import {MToken} from "@protocol/MToken.sol";
import {IChainlinkOracle} from "@protocol/interfaces/IChainlinkOracle.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID, ChainIds} from "@utils/ChainIds.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";

/// @title MIP-X53: Fix Chainlink OEV loan-feed desync
/// @notice Deploys new ChainlinkOEVWrapper instances on Base and Optimism for
///         WETH/ETH with loan-feed dereferencing, upgrades the Base
///         ChainlinkOEVMorphoWrapper proxy to restore round-data validation
///         parity, and re-wires the ChainlinkOracle feed for WETH to the new
///         core wrappers on both chains.
contract mipx53 is HybridProposal {
    using ProposalActions for *;
    using ChainIds for uint256;

    string public constant override name = "MIP-X53";

    /// @notice Liquidator fee split (bps). Matches MIP-X43 (70/30 split).
    uint16 public constant LIQUIDATOR_FEE_BPS = 4000;

    /// @notice Max round delay (seconds) — matches MIP-X38 parameters.
    uint256 public constant MAX_ROUND_DELAY = 10;

    /// @notice Max decrements — matches MIP-X38 parameters.
    uint256 public constant MAX_DECREMENTS = 10;

    /// @notice Snapshot of pre-upgrade Morpho wrapper state, captured in
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

    /// @notice Snapshot of the price returned by the OLD WETH feed wrapper on
    ///         each chain, captured in beforeSimulationHook() and asserted
    ///         in validate() against the price returned by the NEW wrapper.
    ///         Both wrappers must wrap the same raw aggregator, so their
    ///         underlying answer at the same block state must be identical.
    int256 internal _baseWethAnswerPre;
    uint256 internal _baseWethUpdatedAtPre;
    int256 internal _opWethAnswerPre;
    uint256 internal _opWethUpdatedAtPre;
    int256 internal _baseMorphoAnswerPre;
    uint256 internal _baseMorphoUpdatedAtPre;

    /// @notice Pre-upgrade ChainlinkOracle.getUnderlyingPrice(MOONWELL_WETH)
    ///         captures the full price-resolution path (wrapper scaling + OEV
    ///         logic) as seen by consumers. Validated post-upgrade within ±2%
    ///         to catch any decimal-scaling regression in the new wrapper.
    uint256 internal _baseGetUnderlyingPricePre;
    uint256 internal _opGetUnderlyingPricePre;

    /// @notice Pre-upgrade decimals() on the Base Morpho wrapper, used to
    ///         confirm the upgrade does not change the returned precision.
    uint8 internal _baseMorphoDecimalsPre;

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

    function deploy(Addresses addresses, address) public override {
        /// -------------------------------------------------------
        /// Base: new ChainlinkOEVWrapper for ETH/USD and new
        ///       ChainlinkOEVMorphoWrapper implementation
        /// -------------------------------------------------------

        vm.selectFork(BASE_FORK_ID);

        if (!addresses.isAddressSet("CHAINLINK_ETH_USD_OEV_WRAPPER_V3")) {
            vm.startBroadcast();
            ChainlinkOEVWrapper wrapper = new ChainlinkOEVWrapper(
                addresses.getAddress("CHAINLINK_ETH_USD_FEED"),
                addresses.getAddress("TEMPORAL_GOVERNOR"),
                addresses.getAddress("CHAINLINK_ORACLE"),
                addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER"),
                LIQUIDATOR_FEE_BPS,
                MAX_ROUND_DELAY,
                MAX_DECREMENTS
            );
            vm.stopBroadcast();
            addresses.addAddress(
                "CHAINLINK_ETH_USD_OEV_WRAPPER_V3",
                address(wrapper)
            );
        }

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

        /// -------------------------------------------------------
        /// Optimism: new ChainlinkOEVWrapper for ETH/USD
        /// -------------------------------------------------------

        vm.selectFork(OPTIMISM_FORK_ID);

        if (!addresses.isAddressSet("CHAINLINK_ETH_USD_OEV_WRAPPER_V3")) {
            vm.startBroadcast();
            ChainlinkOEVWrapper wrapper = new ChainlinkOEVWrapper(
                addresses.getAddress("CHAINLINK_ETH_USD_FEED"),
                addresses.getAddress("TEMPORAL_GOVERNOR"),
                addresses.getAddress("CHAINLINK_ORACLE"),
                addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER"),
                LIQUIDATOR_FEE_BPS,
                MAX_ROUND_DELAY,
                MAX_DECREMENTS
            );
            vm.stopBroadcast();
            addresses.addAddress(
                "CHAINLINK_ETH_USD_OEV_WRAPPER_V3",
                address(wrapper)
            );
        }

        vm.selectFork(primaryForkId());
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

    /// @notice Snapshot the raw underlying aggregator price on each chain
    ///         immediately before simulation executes the proposal actions.
    ///         The hook runs inside `simulate()` BEFORE the on-chain effects
    ///         (`setFeed` re-wire on Base/Optimism, Morpho proxy upgrade on
    ///         Base) — capturing the answer here lets `validate()` prove the
    ///         new wrapper, when read through the same underlying raw feed,
    ///         returns an identical price for the same block state.
    function beforeSimulationHook(Addresses addresses) public override {
        // Base: capture the raw feed answer through the OLD wrapper's
        // priceFeed pointer (which is the canonical raw ETH/USD aggregator).
        vm.selectFork(BASE_FORK_ID);
        {
            ChainlinkOEVWrapper oldWrapper = ChainlinkOEVWrapper(
                payable(addresses.getAddress("CHAINLINK_ETH_USD_OEV_WRAPPER"))
            );
            (, int256 ans, , uint256 updatedAt, ) = oldWrapper
                .priceFeed()
                .latestRoundData();
            _baseWethAnswerPre = ans;
            _baseWethUpdatedAtPre = updatedAt;
        }

        // Base Morpho: capture the proxy's underlying priceFeed answer and
        // the wrapper's decimals() so validate() can assert exact parity.
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

        // Base: capture the full getUnderlyingPrice path for MOONWELL_WETH.
        if (addresses.isAddressSet("MOONWELL_WETH")) {
            IChainlinkOracle oracle = IChainlinkOracle(
                addresses.getAddress("CHAINLINK_ORACLE")
            );
            _baseGetUnderlyingPricePre = oracle.getUnderlyingPrice(
                MToken(addresses.getAddress("MOONWELL_WETH"))
            );
        } else {
            console.log(
                "Base: MOONWELL_WETH not set, skipping getUnderlyingPrice snapshot"
            );
        }

        // Optimism: capture the raw feed answer and getUnderlyingPrice path.
        vm.selectFork(OPTIMISM_FORK_ID);
        {
            ChainlinkOEVWrapper oldWrapper = ChainlinkOEVWrapper(
                payable(addresses.getAddress("CHAINLINK_ETH_USD_OEV_WRAPPER"))
            );
            (, int256 ans, , uint256 updatedAt, ) = oldWrapper
                .priceFeed()
                .latestRoundData();
            _opWethAnswerPre = ans;
            _opWethUpdatedAtPre = updatedAt;
        }

        if (addresses.isAddressSet("MOONWELL_WETH")) {
            IChainlinkOracle oracle = IChainlinkOracle(
                addresses.getAddress("CHAINLINK_ORACLE")
            );
            _opGetUnderlyingPricePre = oracle.getUnderlyingPrice(
                MToken(addresses.getAddress("MOONWELL_WETH"))
            );
        } else {
            console.log(
                "Optimism: MOONWELL_WETH not set, skipping getUnderlyingPrice snapshot"
            );
        }

        vm.selectFork(primaryForkId());
    }

    function build(Addresses addresses) public override {
        /// -------------------------------------------------------
        /// Base: re-wire WETH feed + upgrade Morpho wrapper proxy
        /// -------------------------------------------------------

        vm.selectFork(BASE_FORK_ID);

        _pushAction(
            addresses.getAddress("CHAINLINK_ORACLE"),
            abi.encodeWithSignature(
                "setFeed(string,address)",
                "WETH",
                addresses.getAddress("CHAINLINK_ETH_USD_OEV_WRAPPER_V3")
            ),
            "Base: ChainlinkOracle.setFeed(WETH, new ChainlinkOEVWrapper V3)"
        );

        _pushAction(
            addresses.getAddress("CHAINLINK_ORACLE_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("CHAINLINK_WELL_USD_ORACLE_PROXY"),
                addresses.getAddress("CHAINLINK_WELL_USD_ORACLE_PROXY_IMPL_V2")
            ),
            "Base: upgrade ChainlinkOEVMorphoWrapper proxy implementation (no reinit)"
        );

        /// -------------------------------------------------------
        /// Optimism: re-wire WETH feed
        /// -------------------------------------------------------

        vm.selectFork(OPTIMISM_FORK_ID);

        _pushAction(
            addresses.getAddress("CHAINLINK_ORACLE"),
            abi.encodeWithSignature(
                "setFeed(string,address)",
                "WETH",
                addresses.getAddress("CHAINLINK_ETH_USD_OEV_WRAPPER_V3")
            ),
            "Optimism: ChainlinkOracle.setFeed(WETH, new ChainlinkOEVWrapper V3)"
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        /// -------------------------------------------------------
        /// Base validation
        /// -------------------------------------------------------

        vm.selectFork(BASE_FORK_ID);
        _validateCoreWrapper(addresses, "Base");
        _validateFeedWired(addresses, "Base");
        _validateMorphoWrapperState(addresses);
        _validatePricePreserved(
            ChainlinkOEVWrapper(
                payable(
                    addresses.getAddress("CHAINLINK_ETH_USD_OEV_WRAPPER_V3")
                )
            ).priceFeed(),
            _baseWethAnswerPre,
            _baseWethUpdatedAtPre,
            "Base WETH"
        );
        _validatePricePreserved(
            ChainlinkOEVMorphoWrapper(
                payable(addresses.getAddress("CHAINLINK_WELL_USD_ORACLE_PROXY"))
            ).priceFeed(),
            _baseMorphoAnswerPre,
            _baseMorphoUpdatedAtPre,
            "Base Morpho"
        );

        // Full price-resolution path: assert getUnderlyingPrice is within ±2%
        // of the pre-upgrade value. Catches decimal-scaling bugs in the new
        // wrapper that the raw-feed equality check above would miss.
        _validateGetUnderlyingPriceWithinTolerance(
            addresses,
            "Base",
            _baseGetUnderlyingPricePre
        );

        // Morpho wrapper decimals must be unchanged across the proxy upgrade.
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

        /// -------------------------------------------------------
        /// Optimism validation
        /// -------------------------------------------------------

        vm.selectFork(OPTIMISM_FORK_ID);
        _validateCoreWrapper(addresses, "Optimism");
        _validateFeedWired(addresses, "Optimism");
        _validatePricePreserved(
            ChainlinkOEVWrapper(
                payable(
                    addresses.getAddress("CHAINLINK_ETH_USD_OEV_WRAPPER_V3")
                )
            ).priceFeed(),
            _opWethAnswerPre,
            _opWethUpdatedAtPre,
            "Optimism WETH"
        );

        // Full price-resolution path: assert getUnderlyingPrice is within ±2%
        // of the pre-upgrade value on Optimism.
        _validateGetUnderlyingPriceWithinTolerance(
            addresses,
            "Optimism",
            _opGetUnderlyingPricePre
        );

        vm.selectFork(primaryForkId());
    }

    /// @notice Asserts that the raw aggregator behind the post-upgrade wrapper
    ///         returns the same answer/updatedAt captured pre-simulation.
    ///         Block state is unchanged across the simulation, so the raw
    ///         aggregator's `latestRoundData` is invariant — any mismatch
    ///         means the new wrapper points at a DIFFERENT raw feed than
    ///         the old wrapper did, which would silently distort liquidations.
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

    /// @notice Validate the new ChainlinkOEVWrapper constructor parameters on
    ///         the currently selected fork.
    function _validateCoreWrapper(
        Addresses addresses,
        string memory chainName
    ) internal view {
        ChainlinkOEVWrapper wrapper = ChainlinkOEVWrapper(
            payable(addresses.getAddress("CHAINLINK_ETH_USD_OEV_WRAPPER_V3"))
        );

        assertEq(
            wrapper.liquidatorFeeBps(),
            LIQUIDATOR_FEE_BPS,
            string.concat(chainName, ": liquidatorFeeBps mismatch")
        );
        assertEq(
            wrapper.maxRoundDelay(),
            MAX_ROUND_DELAY,
            string.concat(chainName, ": maxRoundDelay mismatch")
        );
        assertEq(
            wrapper.maxDecrements(),
            MAX_DECREMENTS,
            string.concat(chainName, ": maxDecrements mismatch")
        );
        assertEq(
            wrapper.owner(),
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            string.concat(chainName, ": owner should be TemporalGovernor")
        );
        assertEq(
            wrapper.feeRecipient(),
            addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER"),
            string.concat(chainName, ": feeRecipient mismatch")
        );
        assertEq(
            address(wrapper.chainlinkOracle()),
            addresses.getAddress("CHAINLINK_ORACLE"),
            string.concat(chainName, ": chainlinkOracle mismatch")
        );
        assertEq(
            address(wrapper.priceFeed()),
            addresses.getAddress("CHAINLINK_ETH_USD_FEED"),
            string.concat(chainName, ": priceFeed should be raw ETH/USD feed")
        );
    }

    /// @notice Validate that ChainlinkOracle has WETH wired to the new wrapper
    ///         on the currently selected fork.
    function _validateFeedWired(
        Addresses addresses,
        string memory chainName
    ) internal view {
        IChainlinkOracle oracle = IChainlinkOracle(
            addresses.getAddress("CHAINLINK_ORACLE")
        );
        assertEq(
            address(oracle.getFeed("WETH")),
            addresses.getAddress("CHAINLINK_ETH_USD_OEV_WRAPPER_V3"),
            string.concat(chainName, ": WETH feed not wired to new wrapper")
        );
    }

    /// @notice Strict-equality check: every Morpho wrapper proxy state value
    ///         after the implementation swap must equal the value captured in
    ///         afterDeploy() before the upgrade. Catches any subtle storage
    ///         shift or accidental reinitialization that a `> 0` sanity
    ///         check would miss.
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

        // Cross-check against current expected addresses to catch a
        // pre-existing misconfiguration that the snapshot would otherwise
        // mask (the snapshot only proves "no change", not "correct value").
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

    /// @notice Reads ChainlinkOracle.getUnderlyingPrice(MOONWELL_WETH)
    ///         post-upgrade and asserts it is within ±2% of the pre-upgrade
    ///         value captured in beforeSimulationHook(). If MOONWELL_WETH is
    ///         not registered on the current fork the check is skipped with a
    ///         log — this guards against future chain additions.
    ///
    ///         The 2% tolerance absorbs OEV-delay-cache-state differences
    ///         (different cachedRoundId values can cause walk-back vs
    ///         current-round selection on the same block) while being tight
    ///         enough to catch any decimal-scaling bug (off by ≥10x).
    function _validateGetUnderlyingPriceWithinTolerance(
        Addresses addresses,
        string memory chainName,
        uint256 capturedPrice
    ) internal view {
        if (!addresses.isAddressSet("MOONWELL_WETH")) {
            console.log(
                string.concat(
                    chainName,
                    ": MOONWELL_WETH not set, skipping getUnderlyingPrice tolerance check"
                )
            );
            return;
        }

        IChainlinkOracle oracle = IChainlinkOracle(
            addresses.getAddress("CHAINLINK_ORACLE")
        );
        uint256 postPrice = oracle.getUnderlyingPrice(
            MToken(addresses.getAddress("MOONWELL_WETH"))
        );

        assertApproxEqRel(
            postPrice,
            capturedPrice,
            2e16, // 2% — 2e16 / 1e18 = 0.02
            string.concat(chainName, ": getUnderlyingPrice diverged")
        );
    }
}
