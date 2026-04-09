//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@forge-std/StdJson.sol";

import {MarketAddV2} from "@proposals/templates/MarketAddV2.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ChainlinkOEVWrapper} from "@protocol/oracles/ChainlinkOEVWrapper.sol";
import {OEVProtocolFeeRedeemer} from "@protocol/OEVProtocolFeeRedeemer.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import "@protocol/utils/ChainIds.sol";

/// @title MarketAddV3: Market Add with OEV Wrapper Deployment
/// @notice Extends MarketAddV2 to deploy ChainlinkOEVWrapper for each configured
/// market and whitelist the mToken on the OEVProtocolFeeRedeemer.
/// OEV configurations are loaded from a JSON file via OEV_CONFIGURATIONS_PATH.
contract MarketAddV3 is MarketAddV2 {
    using stdJson for string;
    using ChainIds for uint256;
    using stdStorage for StdStorage;

    struct OEVConfiguration {
        uint16 feeMultiplier;
        uint256 maxDecrements;
        uint256 maxRoundDelay;
        string mTokenName;
        string underlyingFeedName;
        string wrapperName;
    }

    mapping(uint256 chainId => OEVConfiguration[]) oevConfigurations;

    /// @notice Raw Chainlink prices saved before simulation for comparison with wrappers
    mapping(string wrapperName => int256 price) public rawChainlinkPrices;

    function name() external pure override returns (string memory) {
        return "MIP Market Add V3";
    }

    function initProposal(Addresses addresses) public override {
        super.initProposal(addresses);

        for (uint256 i = 0; i < networks.length; i++) {
            _saveOEVConfigurations(networks[i].chainId);
        }
    }

    function afterDeploy(
        Addresses addresses,
        address deployer
    ) public virtual override {
        uint256 forkBefore = vm.activeFork();

        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            vm.selectFork(chainId.toForkId());

            OEVConfiguration[] memory configs = oevConfigurations[chainId];
            for (uint256 j = 0; j < configs.length; j++) {
                OEVConfiguration memory config = configs[j];

                if (!addresses.isAddressSet(config.wrapperName)) {
                    vm.startBroadcast(deployer);

                    ChainlinkOEVWrapper wrapper = new ChainlinkOEVWrapper(
                        addresses.getAddress(config.underlyingFeedName),
                        addresses.getAddress("TEMPORAL_GOVERNOR"),
                        addresses.getAddress("CHAINLINK_ORACLE"),
                        addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER"),
                        config.feeMultiplier,
                        config.maxRoundDelay,
                        config.maxDecrements
                    );

                    vm.stopBroadcast();
                    addresses.addAddress(config.wrapperName, address(wrapper));
                }
            }
        }

        if (vm.activeFork() != forkBefore) {
            vm.selectFork(forkBefore);
        }
    }

    function build(Addresses addresses) public virtual override {
        /// Build market add actions via parent
        super.build(addresses);

        /// Whitelist each OEV-configured mToken on the fee redeemer
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            vm.selectFork(chainId.toForkId());

            OEVConfiguration[] memory configs = oevConfigurations[chainId];
            for (uint256 j = 0; j < configs.length; j++) {
                OEVConfiguration memory config = configs[j];
                address feeRedeemer = addresses.getAddress(
                    "OEV_PROTOCOL_FEE_REDEEMER"
                );
                address mToken = addresses.getAddress(config.mTokenName);

                _pushAction(
                    feeRedeemer,
                    abi.encodeWithSignature(
                        "whitelistMarket(address,bool)",
                        mToken,
                        true
                    ),
                    string.concat(
                        "Whitelist ",
                        config.mTokenName,
                        " on OEV fee redeemer"
                    )
                );
            }
        }
    }

    function validate(
        Addresses addresses,
        address deployer
    ) public virtual override {
        /// Validate market add via parent
        super.validate(addresses, deployer);

        /// Validate OEV wrapper deployments and configurations
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            vm.selectFork(chainId.toForkId());

            OEVConfiguration[] memory configs = oevConfigurations[chainId];
            for (uint256 j = 0; j < configs.length; j++) {
                OEVConfiguration memory config = configs[j];

                ChainlinkOEVWrapper wrapper = ChainlinkOEVWrapper(
                    payable(addresses.getAddress(config.wrapperName))
                );

                assertEq(
                    address(wrapper.priceFeed()),
                    addresses.getAddress(config.underlyingFeedName),
                    "OEV wrapper priceFeed mismatch"
                );
                assertEq(
                    wrapper.liquidatorFeeBps(),
                    config.feeMultiplier,
                    "OEV wrapper fee mismatch"
                );
                assertEq(
                    wrapper.feeRecipient(),
                    addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER"),
                    "OEV wrapper feeRecipient mismatch"
                );
                assertEq(
                    address(wrapper.chainlinkOracle()),
                    addresses.getAddress("CHAINLINK_ORACLE"),
                    "OEV wrapper chainlinkOracle mismatch"
                );
                assertEq(
                    wrapper.owner(),
                    addresses.getAddress("TEMPORAL_GOVERNOR"),
                    "OEV wrapper owner mismatch"
                );
                assertEq(
                    wrapper.maxRoundDelay(),
                    config.maxRoundDelay,
                    "OEV wrapper maxRoundDelay mismatch"
                );
                assertEq(
                    wrapper.maxDecrements(),
                    config.maxDecrements,
                    "OEV wrapper maxDecrements mismatch"
                );
                assertGt(
                    wrapper.cachedRoundId(),
                    0,
                    "OEV wrapper cachedRoundId should be > 0"
                );

                /// Validate OEV wrapper returns same price as raw Chainlink feed
                (, int256 wrapperPrice, , , ) = wrapper.latestRoundData();
                assertEq(
                    wrapperPrice,
                    rawChainlinkPrices[config.wrapperName],
                    "OEV wrapper price does not match raw Chainlink feed price"
                );

                /// Validate mToken is whitelisted on the fee redeemer
                OEVProtocolFeeRedeemer feeRedeemer = OEVProtocolFeeRedeemer(
                    payable(addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER"))
                );
                assertTrue(
                    feeRedeemer.whitelistedMarkets(
                        addresses.getAddress(config.mTokenName)
                    ),
                    string.concat(
                        config.mTokenName,
                        " not whitelisted on OEV fee redeemer"
                    )
                );
            }
        }
    }

    function beforeSimulationHook(Addresses addresses) public virtual override {
        uint256 forkBefore = vm.activeFork();

        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            vm.selectFork(chainId.toForkId());

            /// Use stdstore for token balance setup (safer for non-standard ERC20s)
            for (uint256 j = 0; j < mTokens[chainId].length; j++) {
                MTokenConfiguration memory config = mTokens[chainId][j];

                stdstore
                    .target(addresses.getAddress(config.tokenAddressName))
                    .sig("balanceOf(address)")
                    .with_key(addresses.getAddress("TEMPORAL_GOVERNOR"))
                    .checked_write(config.initialMintAmount);
            }

            /// Save raw Chainlink prices before simulation for later comparison
            OEVConfiguration[] memory configs = oevConfigurations[chainId];
            for (uint256 j = 0; j < configs.length; j++) {
                OEVConfiguration memory config = configs[j];

                (, int256 price, , , ) = AggregatorV3Interface(
                    addresses.getAddress(config.underlyingFeedName)
                ).latestRoundData();
                require(price > 0, "Raw Chainlink price must be positive");

                rawChainlinkPrices[config.wrapperName] = price;
            }
        }

        if (vm.activeFork() != forkBefore) {
            vm.selectFork(forkBefore);
        }
    }

    function _saveOEVConfigurations(uint256 chainId) internal {
        string memory empty = "";
        string memory envPath = vm.envOr("OEV_CONFIGURATIONS_PATH", empty);

        if (abi.encodePacked(envPath).length == 0) {
            return;
        }

        string memory encodedJson = vm.readFile(envPath);
        string memory chain = string.concat(".", vm.toString(chainId));

        if (vm.keyExistsJson(encodedJson, chain)) {
            bytes memory parsedJson = vm.parseJson(encodedJson, chain);

            OEVConfiguration[] memory configs = abi.decode(
                parsedJson,
                (OEVConfiguration[])
            );

            for (uint256 i = 0; i < configs.length; i++) {
                oevConfigurations[chainId].push(configs[i]);
            }
        }
    }
}
