//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {ChainlinkOEVWrapper} from "@protocol/oracles/ChainlinkOEVWrapper.sol";
import {ChainlinkOEVMorphoWrapper} from "@protocol/oracles/ChainlinkOEVMorphoWrapper.sol";
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
                addresses.getAddress("CHAINLINK_ETH_USD"),
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
                addresses.getAddress("CHAINLINK_ETH_USD"),
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

        /// -------------------------------------------------------
        /// Optimism validation
        /// -------------------------------------------------------

        vm.selectFork(OPTIMISM_FORK_ID);
        _validateCoreWrapper(addresses, "Optimism");
        _validateFeedWired(addresses, "Optimism");

        vm.selectFork(primaryForkId());
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
            addresses.getAddress("CHAINLINK_ETH_USD"),
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
}
