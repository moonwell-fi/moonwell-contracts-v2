// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "forge-std/console.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {ChainlinkOracleConfigs} from "@proposals/ChainlinkOracleConfigs.sol";
import {BASE_FORK_ID, OPTIMISM_FORK_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {Networks} from "@proposals/utils/Networks.sol";
import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {IChainlinkOracle} from "@protocol/interfaces/IChainlinkOracle.sol";
import {ChainlinkOEVWrapper} from "@protocol/oracles/ChainlinkOEVWrapper.sol";
import {ChainlinkOEVMorphoWrapper} from "@protocol/oracles/ChainlinkOEVMorphoWrapper.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {OEVProtocolFeeRedeemer} from "@protocol/OEVProtocolFeeRedeemer.sol";

/// @notice MIP-X43: Activate OEV Wrappers for All Remaining Markets
/// Expands OEV wrapper coverage from the initial 3 feeds (ETH/USD core + WELL/USD Morpho)
/// activated in MIP-X38 to all remaining core and Morpho markets on Base and Optimism.
/// Pre-existing old-style wrappers are deprecated and replaced with new ones.
contract mipx43 is HybridProposal, ChainlinkOracleConfigs, Networks {
    using ChainIds for uint256;
    string public constant override name = "MIP-X43";

    string public constant MORPHO_IMPLEMENTATION_NAME =
        "CHAINLINK_OEV_MORPHO_WRAPPER_IMPL";

    uint16 public constant FEE_MULTIPLIER = 3000;
    uint256 public constant MAX_ROUND_DELAY = 10;
    uint256 public constant MAX_DECREMENTS = 10;

    constructor() {
        _setProposalDescription(
            bytes(vm.readFile("./proposals/mips/mip-x43/x43.md"))
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

    function deploy(Addresses addresses, address) public override {
        // Deploy core wrappers on Base (handles deprecation of old wrappers)
        _deployCoreWrappers(addresses);

        // Deploy core wrappers on Optimism
        vm.selectFork(OPTIMISM_FORK_ID);
        _deployCoreWrappers(addresses);

        // Switch back to Base
        vm.selectFork(BASE_FORK_ID);
    }

    function build(Addresses addresses) public override {
        // Base: upgrade Morpho wrappers, wire core feeds, whitelist mTokens,
        // and update fee split on existing MIP-X38 wrappers
        _upgradeMorphoWrappers(addresses, BASE_CHAIN_ID);
        _wireCoreFeeds(addresses, BASE_CHAIN_ID);
        _whitelistMTokens(addresses, BASE_CHAIN_ID);
        _updateExistingWrapperFees(addresses);

        // Optimism: wire core feeds, whitelist mTokens,
        // and update fee split on existing MIP-X38 wrappers
        vm.selectFork(OPTIMISM_FORK_ID);
        _wireCoreFeeds(addresses, OPTIMISM_CHAIN_ID);
        _whitelistMTokens(addresses, OPTIMISM_CHAIN_ID);
        _updateExistingWrapperFees(addresses);

        vm.selectFork(BASE_FORK_ID);
    }

    function validate(Addresses addresses, address) public override {
        // Validate Optimism
        vm.selectFork(OPTIMISM_FORK_ID);
        _validateFeedsPointToWrappers(addresses, OPTIMISM_CHAIN_ID);
        _validateCoreWrappersConstructor(addresses, OPTIMISM_CHAIN_ID);
        _validateDeprecatedWrappers(addresses, OPTIMISM_CHAIN_ID);
        _validateMTokensWhitelisted(addresses, OPTIMISM_CHAIN_ID);
        _validateExistingWrapperFees(addresses);

        // Validate Base
        vm.selectFork(BASE_FORK_ID);
        _validateFeedsPointToWrappers(addresses, BASE_CHAIN_ID);
        _validateCoreWrappersConstructor(addresses, BASE_CHAIN_ID);
        _validateDeprecatedWrappers(addresses, BASE_CHAIN_ID);
        _validateMTokensWhitelisted(addresses, BASE_CHAIN_ID);
        _validateExistingWrapperFees(addresses);
        _validateMorphoWrappersImplementations(addresses, BASE_CHAIN_ID);
        _validateMorphoWrappersState(addresses, BASE_CHAIN_ID);
    }

    // ──────────────────────────────────────────────────────────────
    //                         DEPLOY
    // ──────────────────────────────────────────────────────────────

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

            // If a wrapper already exists for this oracle, check if it needs
            // deprecation or if it was already handled by a previous config
            // (e.g. USDC/USDBC both reference CHAINLINK_USDC_USD)
            if (addresses.isAddressSet(wrapperName)) {
                string memory deprecatedName = string(
                    abi.encodePacked(wrapperName, "_DEPRECATED")
                );

                // Skip if already deprecated by a previous iteration
                if (addresses.isAddressSet(deprecatedName)) {
                    continue;
                }

                // Skip if the existing wrapper is a new-style one deployed by
                // a previous iteration in this loop. Old-style wrappers
                // (ChainlinkFeedOEVWrapper) lack the chainlinkOracle() field.
                try
                    ChainlinkOEVWrapper(
                        payable(addresses.getAddress(wrapperName))
                    ).chainlinkOracle()
                returns (IChainlinkOracle) {
                    continue;
                } catch {}

                address oldWrapper = addresses.getAddress(wrapperName);
                addresses.addAddress(deprecatedName, oldWrapper);

                ChainlinkOEVWrapper wrapper = new ChainlinkOEVWrapper(
                    addresses.getAddress(config.oracleName),
                    addresses.getAddress("TEMPORAL_GOVERNOR"),
                    addresses.getAddress("CHAINLINK_ORACLE"),
                    addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER"),
                    FEE_MULTIPLIER,
                    MAX_ROUND_DELAY,
                    MAX_DECREMENTS
                );

                addresses.changeAddress(wrapperName, address(wrapper), true);
            } else {
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
        }

        vm.stopBroadcast();
    }

    // ──────────────────────────────────────────────────────────────
    //                         BUILD
    // ──────────────────────────────────────────────────────────────

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

    function _whitelistMTokens(Addresses addresses, uint256 chainId) internal {
        OracleConfig[] memory oracleConfigs = getOracleConfigurations(chainId);
        address feeRedeemer = addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER");

        for (uint256 i = 0; i < oracleConfigs.length; i++) {
            address mToken = addresses.getAddress(oracleConfigs[i].mTokenKey);

            _pushAction(
                feeRedeemer,
                abi.encodeWithSignature(
                    "whitelistMarket(address,bool)",
                    mToken,
                    true
                ),
                string.concat(
                    "Whitelist mToken on OEV fee redeemer for ",
                    oracleConfigs[i].mTokenKey
                )
            );
        }
    }

    /// @dev Update liquidatorFeeBps from 4000 (60/40) to 3000 (70/30) on
    /// existing MIP-X38 wrappers. On Base this covers the ETH core wrapper and
    /// the WELL Morpho wrapper. On Optimism only the ETH core wrapper.
    function _updateExistingWrapperFees(Addresses addresses) internal {
        // Update ETH/USD core wrapper (deployed by MIP-X38 on both chains)
        address ethWrapper = addresses.getAddress(
            "CHAINLINK_ETH_USD_OEV_WRAPPER"
        );
        _pushAction(
            ethWrapper,
            abi.encodeWithSignature(
                "setLiquidatorFeeBps(uint16)",
                FEE_MULTIPLIER
            ),
            "Update ETH/USD OEV wrapper fee split to 70/30"
        );

        // Update WELL Morpho wrapper (only on Base, not Optimism)
        if (addresses.isAddressSet("CHAINLINK_WELL_USD_ORACLE_PROXY")) {
            address wellMorphoWrapper = addresses.getAddress(
                "CHAINLINK_WELL_USD_ORACLE_PROXY"
            );
            _pushAction(
                wellMorphoWrapper,
                abi.encodeWithSignature(
                    "setLiquidatorFeeBps(uint16)",
                    FEE_MULTIPLIER
                ),
                "Update WELL/USD Morpho OEV wrapper fee split to 70/30"
            );
        }
    }

    // ──────────────────────────────────────────────────────────────
    //                        VALIDATE
    // ──────────────────────────────────────────────────────────────

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

            assertEq(
                address(wrapper.priceFeed()),
                addresses.getAddress(config.oracleName),
                string.concat(
                    "Core wrapper priceFeed mismatch for ",
                    wrapperName
                )
            );

            assertEq(
                wrapper.liquidatorFeeBps(),
                FEE_MULTIPLIER,
                string.concat(
                    "Core wrapper liquidatorFeeBps mismatch for ",
                    wrapperName
                )
            );

            assertEq(
                wrapper.feeRecipient(),
                addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER"),
                string.concat(
                    "Core wrapper feeRecipient mismatch for ",
                    wrapperName
                )
            );

            assertGt(
                wrapper.cachedRoundId(),
                0,
                string.concat(
                    "Core wrapper cachedRoundId should be > 0 for ",
                    wrapperName
                )
            );

            assertEq(
                wrapper.maxRoundDelay(),
                MAX_ROUND_DELAY,
                string.concat(
                    "Core wrapper maxRoundDelay mismatch for ",
                    wrapperName
                )
            );

            assertEq(
                wrapper.maxDecrements(),
                MAX_DECREMENTS,
                string.concat(
                    "Core wrapper maxDecrements mismatch for ",
                    wrapperName
                )
            );

            assertEq(
                address(wrapper.chainlinkOracle()),
                expectedChainlinkOracle,
                string.concat(
                    "Core wrapper chainlinkOracle mismatch for ",
                    wrapperName
                )
            );

            assertEq(
                wrapper.owner(),
                expectedOwner,
                string.concat("Core wrapper owner mismatch for ", wrapperName)
            );
        }
    }

    function _validateDeprecatedWrappers(
        Addresses addresses,
        uint256 chainId
    ) internal view {
        OracleConfig[] memory oracleConfigs = getOracleConfigurations(chainId);

        for (uint256 i = 0; i < oracleConfigs.length; i++) {
            string memory wrapperName = string(
                abi.encodePacked(oracleConfigs[i].oracleName, "_OEV_WRAPPER")
            );
            string memory deprecatedName = string(
                abi.encodePacked(wrapperName, "_DEPRECATED")
            );

            // Only validate if a deprecated address was saved (meaning old wrapper existed)
            if (addresses.isAddressSet(deprecatedName)) {
                address deprecated = addresses.getAddress(deprecatedName);
                address current = addresses.getAddress(wrapperName);

                assertTrue(
                    deprecated != current,
                    string.concat(
                        "Deprecated wrapper should differ from current for ",
                        wrapperName
                    )
                );

                assertTrue(
                    deprecated != address(0),
                    string.concat(
                        "Deprecated wrapper should not be zero for ",
                        wrapperName
                    )
                );
            }
        }
    }

    function _validateMTokensWhitelisted(
        Addresses addresses,
        uint256 chainId
    ) internal view {
        OracleConfig[] memory oracleConfigs = getOracleConfigurations(chainId);
        OEVProtocolFeeRedeemer feeRedeemer = OEVProtocolFeeRedeemer(
            payable(addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER"))
        );

        for (uint256 i = 0; i < oracleConfigs.length; i++) {
            address mToken = addresses.getAddress(oracleConfigs[i].mTokenKey);
            assertTrue(
                feeRedeemer.whitelistedMarkets(mToken),
                string.concat(
                    "mToken not whitelisted on fee redeemer for ",
                    oracleConfigs[i].mTokenKey
                )
            );
        }
    }

    function _validateExistingWrapperFees(Addresses addresses) internal view {
        // Validate ETH/USD core wrapper fee was updated
        ChainlinkOEVWrapper ethWrapper = ChainlinkOEVWrapper(
            payable(addresses.getAddress("CHAINLINK_ETH_USD_OEV_WRAPPER"))
        );
        assertEq(
            ethWrapper.liquidatorFeeBps(),
            FEE_MULTIPLIER,
            "ETH/USD OEV wrapper fee not updated to 70/30"
        );

        // Validate WELL Morpho wrapper fee was updated (only on Base)
        if (addresses.isAddressSet("CHAINLINK_WELL_USD_ORACLE_PROXY")) {
            ChainlinkOEVMorphoWrapper wellWrapper = ChainlinkOEVMorphoWrapper(
                addresses.getAddress("CHAINLINK_WELL_USD_ORACLE_PROXY")
            );
            assertEq(
                wellWrapper.liquidatorFeeBps(),
                FEE_MULTIPLIER,
                "WELL/USD Morpho OEV wrapper fee not updated to 70/30"
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

            assertEq(
                address(wrapper.priceFeed()),
                addresses.getAddress(morphoConfigs[i].priceFeedName),
                string.concat(
                    "Morpho wrapper priceFeed mismatch for ",
                    wrapperName
                )
            );

            assertEq(
                address(wrapper.morphoBlue()),
                morphoBlue,
                string.concat(
                    "Morpho wrapper morphoBlue mismatch for ",
                    wrapperName
                )
            );

            assertEq(
                address(wrapper.chainlinkOracle()),
                expectedChainlinkOracle,
                string.concat(
                    "Morpho wrapper chainlinkOracle mismatch for ",
                    wrapperName
                )
            );

            assertEq(
                wrapper.feeRecipient(),
                addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER"),
                string.concat(
                    "Morpho wrapper feeRecipient mismatch for ",
                    wrapperName
                )
            );

            assertEq(
                wrapper.liquidatorFeeBps(),
                FEE_MULTIPLIER,
                string.concat(
                    "Morpho wrapper liquidatorFeeBps mismatch for ",
                    wrapperName
                )
            );

            assertGt(
                wrapper.cachedRoundId(),
                0,
                string.concat(
                    "Morpho wrapper cachedRoundId should be > 0 for ",
                    wrapperName
                )
            );

            assertEq(
                wrapper.maxRoundDelay(),
                MAX_ROUND_DELAY,
                string.concat(
                    "Morpho wrapper maxRoundDelay mismatch for ",
                    wrapperName
                )
            );

            assertEq(
                wrapper.maxDecrements(),
                MAX_DECREMENTS,
                string.concat(
                    "Morpho wrapper maxDecrements mismatch for ",
                    wrapperName
                )
            );

            assertEq(
                wrapper.owner(),
                expectedOwner,
                string.concat("Morpho wrapper owner mismatch for ", wrapperName)
            );

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
            assertTrue(
                answer > 0,
                string.concat("Morpho wrapper answer invalid for ", wrapperName)
            );
        }
    }
}
