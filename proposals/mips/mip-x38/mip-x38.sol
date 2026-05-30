// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "forge-std/console.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {ChainlinkOracleConfigs} from "@proposals/ChainlinkOracleConfigs.sol";
import {BASE_FORK_ID, OPTIMISM_FORK_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {Networks} from "@proposals/utils/Networks.sol";
import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {ChainlinkOEVWrapper} from "@protocol/oracles/ChainlinkOEVWrapper.sol";
import {ChainlinkOEVMorphoWrapper} from "@protocol/oracles/ChainlinkOEVMorphoWrapper.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {OEVProtocolFeeRedeemer} from "@protocol/OEVProtocolFeeRedeemer.sol";

// this proposal should
// 1. deploy once instance of OEVProtocolFeeRedeemer (fee recipient)
// 2. deploy new non-upgradeable ChainlinkOEVWrapper contracts for core markets
// 3. upgrade existing ChainlinkOEVMorphoWrapper proxy contracts for Morpho markets => test that storage can still be accessed
// 4. call setFeed on the ChainlinkOracle for all core markets, to point to the new ChainlinkOEVWrapper contracts
contract mipx38 is HybridProposal, ChainlinkOracleConfigs, Networks {
    using ChainIds for uint256;
    string public constant override name = "MIP-X38";

    string public constant MORPHO_IMPLEMENTATION_NAME =
        "CHAINLINK_OEV_MORPHO_WRAPPER_IMPL";

    uint16 public constant FEE_MULTIPLIER = 4000; // liquidator keeps 40% of the remaining collateral seized after repay amount
    uint256 public constant MAX_ROUND_DELAY = 10;
    uint256 public constant MAX_DECREMENTS = 10;

    /// @dev description setup
    constructor() {
        _setProposalDescription(
            bytes(vm.readFile("./proposals/mips/mip-x38/x38.md"))
        );
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
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

    // Deploy new instances of ChainlinkOEVWrapper (core markets) and ensure ChainlinkOEVMorphoWrapper implementation
    // exists (Morpho). Also deploy once instance of OEVProtocolFeeRedeemer (fee recipient).
    function deploy(Addresses addresses, address) public override {
        _deployOEVProtocolFeeRedeemer(addresses);
        _deployCoreWrappers(addresses);
        _deployMorphoWrappers(addresses);

        vm.selectFork(OPTIMISM_FORK_ID);
        _deployOEVProtocolFeeRedeemer(addresses);
        _deployCoreWrappers(addresses);

        // no morpho markets on optimism

        // switch back
        vm.selectFork(BASE_FORK_ID);
    }

    // Upgrade Morpho wrappers and wire core feeds
    function build(Addresses addresses) public override {
        // Base: upgrade Morpho wrappers and wire core feeds
        _upgradeMorphoWrappers(addresses, BASE_CHAIN_ID);
        _wireCoreFeeds(addresses, BASE_CHAIN_ID);

        // Optimism: only wire core feeds
        vm.selectFork(OPTIMISM_FORK_ID);
        _wireCoreFeeds(addresses, OPTIMISM_CHAIN_ID);

        vm.selectFork(BASE_FORK_ID);
    }

    function validate(Addresses addresses, address) public override {
        // Validate Optimism
        vm.selectFork(OPTIMISM_FORK_ID);
        _validateFeedsPointToWrappers(addresses, OPTIMISM_CHAIN_ID);
        _validateCoreWrappersConstructor(addresses, OPTIMISM_CHAIN_ID);

        // Validate Base
        vm.selectFork(BASE_FORK_ID);
        _validateFeedsPointToWrappers(addresses, BASE_CHAIN_ID);
        _validateCoreWrappersConstructor(addresses, BASE_CHAIN_ID);
        _validateMorphoWrappersImplementations(addresses, BASE_CHAIN_ID);
        _validateMorphoWrappersState(addresses, BASE_CHAIN_ID);
    }

    function _upgradeMorphoWrappers(
        Addresses addresses,
        uint256 chainId
    ) internal {
        MorphoOracleConfig[]
            memory morphoConfigs = getMorphoOracleConfigurations(chainId);

        require(
            addresses.isAddressSet(MORPHO_IMPLEMENTATION_NAME),
            "Morpho implementation not deployed"
        );
        address proxyAdmin = addresses.getAddress(
            "CHAINLINK_ORACLE_PROXY_ADMIN"
        );

        for (uint256 i = 0; i < morphoConfigs.length; i++) {
            string memory wrapperName = string(
                abi.encodePacked(morphoConfigs[i].proxyName, "_ORACLE_PROXY")
            );

            require(
                addresses.isAddressSet(wrapperName),
                "Morpho wrapper not deployed"
            );

            _pushAction(
                proxyAdmin,
                abi.encodeWithSignature(
                    "upgradeAndCall(address,address,bytes)",
                    addresses.getAddress(wrapperName),
                    addresses.getAddress(MORPHO_IMPLEMENTATION_NAME),
                    abi.encodeWithSelector(
                        ChainlinkOEVMorphoWrapper.initializeV2.selector,
                        addresses.getAddress(morphoConfigs[i].priceFeedName),
                        addresses.getAddress("TEMPORAL_GOVERNOR"),
                        addresses.getAddress("MORPHO_BLUE"),
                        addresses.getAddress("CHAINLINK_ORACLE"),
                        addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER"),
                        FEE_MULTIPLIER,
                        MAX_ROUND_DELAY,
                        MAX_DECREMENTS
                    )
                ),
                string.concat(
                    "Upgrade Morpho OEV wrapper via upgradeAndCall (with initializeV2) for ",
                    morphoConfigs[i].proxyName
                )
            );
        }
    }

    function _wireCoreFeeds(Addresses addresses, uint256 chainId) internal {
        OracleConfig[] memory oracleConfigs = getOracleConfigurations(chainId);

        for (uint256 i = 0; i < oracleConfigs.length; i++) {
            OracleConfig memory config = oracleConfigs[i];
            string memory wrapperName = string(
                abi.encodePacked(config.oracleName, "_OEV_WRAPPER")
            );
            address chainlinkOracle = addresses.getAddress("CHAINLINK_ORACLE");
            string memory symbol = ERC20(addresses.getAddress(config.symbol))
                .symbol();

            address wrapperAddress = addresses.getAddress(wrapperName);

            _pushAction(
                chainlinkOracle,
                abi.encodeWithSignature(
                    "setFeed(string,address)",
                    symbol,
                    wrapperAddress
                ),
                string.concat("Set feed to OEV wrapper for ", symbol)
            );
        }
    }

    function _deployOEVProtocolFeeRedeemer(Addresses addresses) internal {
        if (addresses.isAddressSet("OEV_PROTOCOL_FEE_REDEEMER")) {
            return;
        }

        vm.startBroadcast();
        OEVProtocolFeeRedeemer feeRedeemer = new OEVProtocolFeeRedeemer(
            addresses.getAddress("MOONWELL_WETH")
        );

        // Whitelist all mTokens
        OracleConfig[] memory oracleConfigs = getOracleConfigurations(
            block.chainid
        );
        for (uint256 i = 0; i < oracleConfigs.length; i++) {
            feeRedeemer.whitelistMarket(
                addresses.getAddress(oracleConfigs[i].mTokenKey),
                true
            );
        }

        feeRedeemer.transferOwnership(
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );

        addresses.addAddress("OEV_PROTOCOL_FEE_REDEEMER", address(feeRedeemer));
        vm.stopBroadcast();
    }

    /// @dev deploy direct instances (non-upgradeable) for all core markets
    function _deployCoreWrappers(Addresses addresses) internal {
        OracleConfig[] memory oracleConfigs = getOracleConfigurations(
            block.chainid
        );

        if (oracleConfigs.length == 0) {
            console.log("No oracle configs found for chain %d", block.chainid);
            return;
        }

        vm.startBroadcast();

        for (uint256 i = 0; i < oracleConfigs.length; i++) {
            OracleConfig memory config = oracleConfigs[i];

            string memory wrapperName = string(
                abi.encodePacked(config.oracleName, "_OEV_WRAPPER")
            );

            if (addresses.isAddressSet(wrapperName)) {
                continue;
            }

            ChainlinkOEVWrapper wrapper = new ChainlinkOEVWrapper(
                addresses.getAddress(config.oracleName),
                addresses.getAddress("TEMPORAL_GOVERNOR"),
                addresses.getAddress("CHAINLINK_ORACLE"),
                addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER"),
                FEE_MULTIPLIER,
                MAX_ROUND_DELAY,
                MAX_DECREMENTS
            );

            addresses.addAddress(wrapperName, address(wrapper));
        }

        vm.stopBroadcast();
    }

    function _deployMorphoWrappers(Addresses addresses) internal {
        // Only ensure implementation exists; do not deploy new proxies. We'll upgrade existing proxies instead.
        if (!addresses.isAddressSet("MORPHO_BLUE")) {
            return;
        }

        vm.startBroadcast();

        // Ensure proxy admin exists for Morpho wrapper upgrades
        if (!addresses.isAddressSet("CHAINLINK_ORACLE_PROXY_ADMIN")) {
            ProxyAdmin proxyAdmin = new ProxyAdmin();
            addresses.addAddress(
                "CHAINLINK_ORACLE_PROXY_ADMIN",
                address(proxyAdmin)
            );
        }

        // Deploy Morpho implementation if needed
        if (!addresses.isAddressSet(MORPHO_IMPLEMENTATION_NAME)) {
            ChainlinkOEVMorphoWrapper impl = new ChainlinkOEVMorphoWrapper();
            addresses.addAddress(MORPHO_IMPLEMENTATION_NAME, address(impl));
        }

        vm.stopBroadcast();
    }

    function _validateFeedsPointToWrappers(
        Addresses addresses,
        uint256 chainId
    ) internal view {
        OracleConfig[] memory oracleConfigs = getOracleConfigurations(chainId);
        address chainlinkOracle = addresses.getAddress("CHAINLINK_ORACLE");
        for (uint256 i = 0; i < oracleConfigs.length; i++) {
            OracleConfig memory config = oracleConfigs[i];
            string memory wrapperName = string(
                abi.encodePacked(config.oracleName, "_OEV_WRAPPER")
            );
            string memory symbol = ERC20(addresses.getAddress(config.symbol))
                .symbol();
            address configured = address(
                ChainlinkOracle(chainlinkOracle).getFeed(symbol)
            );
            address expected = addresses.getAddress(wrapperName);
            assertEq(
                configured,
                expected,
                string.concat("Feed not set to wrapper for ", symbol)
            );
        }
    }

    function _validateCoreWrappersConstructor(
        Addresses addresses,
        uint256 chainId
    ) internal view {
        OracleConfig[] memory oracleConfigs = getOracleConfigurations(chainId);
        address expectedOwner = addresses.getAddress("TEMPORAL_GOVERNOR");
        address expectedChainlinkOracle = addresses.getAddress(
            "CHAINLINK_ORACLE"
        );

        for (uint256 i = 0; i < oracleConfigs.length; i++) {
            OracleConfig memory config = oracleConfigs[i];
            string memory wrapperName = string(
                abi.encodePacked(config.oracleName, "_OEV_WRAPPER")
            );

            ChainlinkOEVWrapper wrapper = ChainlinkOEVWrapper(
                payable(addresses.getAddress(wrapperName))
            );

            // Validate priceFeed
            assertEq(
                address(wrapper.priceFeed()),
                addresses.getAddress(config.oracleName),
                string.concat(
                    "Core wrapper priceFeed mismatch for ",
                    wrapperName
                )
            );

            // Validate liquidatorFeeBps
            assertEq(
                wrapper.liquidatorFeeBps(),
                FEE_MULTIPLIER,
                string.concat(
                    "Core wrapper liquidatorFeeBps mismatch for ",
                    wrapperName
                )
            );

            // Validate feeRecipient
            assertEq(
                wrapper.feeRecipient(),
                addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER"),
                string.concat(
                    "Core wrapper feeRecipient mismatch for ",
                    wrapperName
                )
            );

            // Validate cachedRoundId (should be > 0 as it's set to priceFeed.latestRound())
            assertGt(
                wrapper.cachedRoundId(),
                0,
                string.concat(
                    "Core wrapper cachedRoundId should be > 0 for ",
                    wrapperName
                )
            );

            // Validate maxRoundDelay
            assertEq(
                wrapper.maxRoundDelay(),
                MAX_ROUND_DELAY,
                string.concat(
                    "Core wrapper maxRoundDelay mismatch for ",
                    wrapperName
                )
            );

            // Validate maxDecrements
            assertEq(
                wrapper.maxDecrements(),
                MAX_DECREMENTS,
                string.concat(
                    "Core wrapper maxDecrements mismatch for ",
                    wrapperName
                )
            );

            // Validate chainlinkOracle
            assertEq(
                address(wrapper.chainlinkOracle()),
                expectedChainlinkOracle,
                string.concat(
                    "Core wrapper chainlinkOracle mismatch for ",
                    wrapperName
                )
            );

            // Validate owner
            assertEq(
                wrapper.owner(),
                expectedOwner,
                string.concat("Core wrapper owner mismatch for ", wrapperName)
            );
        }
    }

    function _validateMorphoWrappersImplementations(
        Addresses addresses,
        uint256 chainId
    ) internal view {
        MorphoOracleConfig[]
            memory morphoConfigs = getMorphoOracleConfigurations(chainId);
        if (morphoConfigs.length == 0) return;

        for (uint256 i = 0; i < morphoConfigs.length; i++) {
            string memory wrapperName = string(
                abi.encodePacked(morphoConfigs[i].proxyName, "_ORACLE_PROXY")
            );

            validateProxy(
                vm,
                addresses.getAddress(wrapperName),
                addresses.getAddress(MORPHO_IMPLEMENTATION_NAME),
                addresses.getAddress("CHAINLINK_ORACLE_PROXY_ADMIN"),
                string.concat("morpho wrapper validation: ", wrapperName)
            );
        }
    }

    function _validateMorphoWrappersState(
        Addresses addresses,
        uint256 chainId
    ) internal view {
        MorphoOracleConfig[]
            memory morphoConfigs = getMorphoOracleConfigurations(chainId);
        if (morphoConfigs.length == 0) return;

        address morphoBlue = addresses.getAddress("MORPHO_BLUE");
        address expectedOwner = addresses.getAddress("TEMPORAL_GOVERNOR");
        address expectedChainlinkOracle = addresses.getAddress(
            "CHAINLINK_ORACLE"
        );

        for (uint256 i = 0; i < morphoConfigs.length; i++) {
            string memory wrapperName = string(
                abi.encodePacked(morphoConfigs[i].proxyName, "_ORACLE_PROXY")
            );
            ChainlinkOEVMorphoWrapper wrapper = ChainlinkOEVMorphoWrapper(
                addresses.getAddress(wrapperName)
            );

            // Validate priceFeed
            assertEq(
                address(wrapper.priceFeed()),
                addresses.getAddress(morphoConfigs[i].priceFeedName),
                string.concat(
                    "Morpho wrapper priceFeed mismatch for ",
                    wrapperName
                )
            );

            // Validate morphoBlue
            assertEq(
                address(wrapper.morphoBlue()),
                morphoBlue,
                string.concat(
                    "Morpho wrapper morphoBlue mismatch for ",
                    wrapperName
                )
            );

            // Validate chainlinkOracle
            assertEq(
                address(wrapper.chainlinkOracle()),
                expectedChainlinkOracle,
                string.concat(
                    "Morpho wrapper chainlinkOracle mismatch for ",
                    wrapperName
                )
            );

            // Validate feeRecipient
            assertEq(
                wrapper.feeRecipient(),
                addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER"),
                string.concat(
                    "Morpho wrapper feeRecipient mismatch for ",
                    wrapperName
                )
            );

            // Validate liquidatorFeeBps
            assertEq(
                wrapper.liquidatorFeeBps(),
                FEE_MULTIPLIER,
                string.concat(
                    "Morpho wrapper liquidatorFeeBps mismatch for ",
                    wrapperName
                )
            );

            // Validate cachedRoundId (should be > 0 as it's set to priceFeed.latestRound())
            assertGt(
                wrapper.cachedRoundId(),
                0,
                string.concat(
                    "Morpho wrapper cachedRoundId should be > 0 for ",
                    wrapperName
                )
            );

            // Validate maxRoundDelay
            assertEq(
                wrapper.maxRoundDelay(),
                MAX_ROUND_DELAY,
                string.concat(
                    "Morpho wrapper maxRoundDelay mismatch for ",
                    wrapperName
                )
            );

            // Validate maxDecrements
            assertEq(
                wrapper.maxDecrements(),
                MAX_DECREMENTS,
                string.concat(
                    "Morpho wrapper maxDecrements mismatch for ",
                    wrapperName
                )
            );

            // Validate owner
            assertEq(
                wrapper.owner(),
                expectedOwner,
                string.concat("Morpho wrapper owner mismatch for ", wrapperName)
            );

            // Validate decimals behavior
            uint8 d = wrapper.decimals();
            assertEq(
                d,
                AggregatorV3Interface(
                    addresses.getAddress(morphoConfigs[i].priceFeedName)
                ).decimals(),
                string.concat(
                    "Morpho wrapper decimals mismatch for ",
                    wrapperName
                )
            );

            // Validate latestRoundData behavior
            (uint80 roundId, int256 answer, , uint256 updatedAt, ) = wrapper
                .latestRoundData();
            assertGt(
                uint256(roundId),
                0,
                string.concat(
                    "Morpho wrapper roundId invalid for ",
                    wrapperName
                )
            );
            assertGt(
                uint256(updatedAt),
                0,
                string.concat(
                    "Morpho wrapper updatedAt invalid for ",
                    wrapperName
                )
            );
            assertGt(
                uint256(answer),
                0,
                string.concat("Morpho wrapper answer invalid for ", wrapperName)
            );
        }
    }
}
