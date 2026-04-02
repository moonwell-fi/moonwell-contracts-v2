pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@utils/ChainIds.sol";

abstract contract ChainlinkOracleConfigs is Test {
    struct OracleConfig {
        string oracleName; /// e.g., CHAINLINK_ETH_USD
        string symbol; /// e.g., as found in addresses
        string mTokenKey; /// e.g., MOONWELL_WETH (defaults to MOONWELL_[symbol] if not specified)
    }

    struct CompositeOracleConfig {
        string compositeOracleName; /// e.g., "CHAINLINK_WSTETH_STETH_COMPOSITE_ORACLE"
        string baseFeedName; /// e.g., "CHAINLINK_ETH_USD" (the base feed for round tracking)
        string symbol; /// e.g., "wstETH"
        string mTokenKey; /// e.g., "MOONWELL_wstETH"
    }

    struct MorphoOracleConfig {
        string proxyName; /// e.g., CHAINLINK_stkWELL_USD (used for proxy identifier)
        string priceFeedName; /// e.g., CHAINLINK_WELL_USD (the actual price feed oracle)
    }

    /// oracle configurations per chain id
    mapping(uint256 => OracleConfig[]) internal _oracleConfigs;

    /// composite oracle configurations per chain id
    mapping(uint256 => CompositeOracleConfig[])
        internal _compositeOracleConfigs;

    /// morpho market configurations per chain id
    mapping(uint256 => MorphoOracleConfig[]) internal _MorphoOracleConfigs;

    /// @dev oracles are listed in the order they are in the docs
    /// https://docs.moonwell.fi/moonwell/protocol-information/contracts#base-contract-addresses
    constructor() {
        /// Initialize oracle configurations for Base
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("DAI_ORACLE", "DAI", "MOONWELL_DAI")
        );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_USDC_USD", "USDC", "MOONWELL_USDC")
        );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_USDC_USD", "USDBC", "MOONWELL_USDBC")
        );
        // WETH already activated by MIP-X38
        // _oracleConfigs[BASE_CHAIN_ID].push(
        //     OracleConfig("CHAINLINK_ETH_USD", "WETH", "MOONWELL_WETH")
        // );
        // cbETH uses cbETH_COMPOSITE_ORACLE (reverted from cbETHETH_ORACLE in MIP-B57)
        // Now handled via _compositeOracleConfigs below
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_AERO_ORACLE", "AERO", "MOONWELL_AERO")
        );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_BTC_USD", "cbBTC", "MOONWELL_cbBTC")
        );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_EURC_USD", "EURC", "MOONWELL_EURC")
        );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_WELL_USD", "xWELL_PROXY", "MOONWELL_WELL")
        );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_USDS_USD", "USDS", "MOONWELL_USDS")
        );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_TBTC_USD", "TBTC", "MOONWELL_TBTC")
        );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_VIRTUAL_USD", "VIRTUAL", "MOONWELL_VIRTUAL")
        );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_MORPHO_USD", "MORPHO", "MOONWELL_MORPHO")
        );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_cbXRP_USD", "cbXRP", "MOONWELL_cbXRP")
        );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_MAMO_USD", "MAMO", "MOONWELL_MAMO")
        );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_VVV_USD", "VVV", "MOONWELL_VVV")
        );

        /// Initialize composite oracle configurations for Base
        _compositeOracleConfigs[BASE_CHAIN_ID].push(
            CompositeOracleConfig(
                "cbETH_COMPOSITE_ORACLE",
                "CHAINLINK_ETH_USD",
                "cbETH",
                "MOONWELL_cbETH"
            )
        );
        _compositeOracleConfigs[BASE_CHAIN_ID].push(
            CompositeOracleConfig(
                "CHAINLINK_WSTETH_STETH_COMPOSITE_ORACLE",
                "CHAINLINK_ETH_USD",
                "wstETH",
                "MOONWELL_wstETH"
            )
        );
        _compositeOracleConfigs[BASE_CHAIN_ID].push(
            CompositeOracleConfig(
                "CHAINLINK_RETH_ETH_EXCHANGE_RATE_ORACLE",
                "CHAINLINK_ETH_USD",
                "rETH",
                "MOONWELL_rETH"
            )
        );
        _compositeOracleConfigs[BASE_CHAIN_ID].push(
            CompositeOracleConfig(
                "CHAINLINK_WEETH_USD_COMPOSITE_ORACLE",
                "CHAINLINK_ETH_USD",
                "weETH",
                "MOONWELL_weETH"
            )
        );
        _compositeOracleConfigs[BASE_CHAIN_ID].push(
            CompositeOracleConfig(
                "CHAINLINK_wrsETH_COMPOSITE_ORACLE",
                "CHAINLINK_ETH_USD",
                "wrsETH",
                "MOONWELL_wrsETH"
            )
        );
        _compositeOracleConfigs[BASE_CHAIN_ID].push(
            CompositeOracleConfig(
                "CHAINLINK_LBTC_BTC_COMPOSITE_ORACLE",
                "CHAINLINK_BTC_USD",
                "LBTC",
                "MOONWELL_LBTC"
            )
        );

        /// Initialize oracle configurations for Optimism
        /// Note: CHAINLINK_WELL_USD OEV wrapper was not upgraded on Optimism
        /// (no _DEPRECATED variant exists on chain 10). See mip-x14 _getWrapperName.
        _oracleConfigs[OPTIMISM_CHAIN_ID].push(
            OracleConfig("CHAINLINK_USDC_USD", "USDC", "MOONWELL_USDC")
        );
        _oracleConfigs[OPTIMISM_CHAIN_ID].push(
            OracleConfig("CHAINLINK_USDT_USD", "USDT", "MOONWELL_USDT")
        );
        _oracleConfigs[OPTIMISM_CHAIN_ID].push(
            OracleConfig("CHAINLINK_DAI_USD", "DAI", "MOONWELL_DAI")
        );
        // WETH already activated by MIP-X38
        // _oracleConfigs[OPTIMISM_CHAIN_ID].push(
        //     OracleConfig("CHAINLINK_ETH_USD", "WETH", "MOONWELL_WETH")
        // );
        _oracleConfigs[OPTIMISM_CHAIN_ID].push(
            OracleConfig("CHAINLINK_WBTC_USD", "WBTC", "MOONWELL_WBTC")
        );
        _oracleConfigs[OPTIMISM_CHAIN_ID].push(
            OracleConfig("CHAINLINK_OP_USD", "OP", "MOONWELL_OP")
        );
        _oracleConfigs[OPTIMISM_CHAIN_ID].push(
            OracleConfig("CHAINLINK_VELO_USD", "VELO", "MOONWELL_VELO")
        );
        _oracleConfigs[OPTIMISM_CHAIN_ID].push(
            OracleConfig("CHAINLINK_USDT_USD", "USDT0", "MOONWELL_USDT0")
        );

        /// Initialize composite oracle configurations for Optimism
        _compositeOracleConfigs[OPTIMISM_CHAIN_ID].push(
            CompositeOracleConfig(
                "CHAINLINK_WSTETH_USD_COMPOSITE_ORACLE",
                "CHAINLINK_ETH_USD",
                "wstETH",
                "MOONWELL_wstETH"
            )
        );
        _compositeOracleConfigs[OPTIMISM_CHAIN_ID].push(
            CompositeOracleConfig(
                "CHAINLINK_cbETH_USD_COMPOSITE_ORACLE",
                "CHAINLINK_ETH_USD",
                "cbETH",
                "MOONWELL_cbETH"
            )
        );
        _compositeOracleConfigs[OPTIMISM_CHAIN_ID].push(
            CompositeOracleConfig(
                "CHAINLINK_RETH_ETH_EXCHANGE_RATE_ORACLE",
                "CHAINLINK_ETH_USD",
                "rETH",
                "MOONWELL_rETH"
            )
        );
        _compositeOracleConfigs[OPTIMISM_CHAIN_ID].push(
            CompositeOracleConfig(
                "CHAINLINK_WEETH_USD_COMPOSITE_ORACLE",
                "CHAINLINK_ETH_USD",
                "weETH",
                "MOONWELL_weETH"
            )
        );
        _compositeOracleConfigs[OPTIMISM_CHAIN_ID].push(
            CompositeOracleConfig(
                "CHAINLINK_wrsETH_COMPOSITE_ORACLE",
                "CHAINLINK_ETH_USD",
                "wrsETH",
                "MOONWELL_wrsETH"
            )
        );

        /// Initialize Morpho market configurations for Base
        // WELL already activated by MIP-X38
        // _MorphoOracleConfigs[BASE_CHAIN_ID].push(
        //     MorphoOracleConfig("CHAINLINK_WELL_USD", "CHAINLINK_WELL_USD")
        // );
        _MorphoOracleConfigs[BASE_CHAIN_ID].push(
            MorphoOracleConfig("CHAINLINK_MAMO_USD", "CHAINLINK_MAMO_USD")
        );
        _MorphoOracleConfigs[BASE_CHAIN_ID].push(
            MorphoOracleConfig("CHAINLINK_stkWELL_USD", "CHAINLINK_WELL_USD")
        );
    }

    function getOracleConfigurations(
        uint256 chainId
    ) public view returns (OracleConfig[] memory) {
        OracleConfig[] memory configs = new OracleConfig[](
            _oracleConfigs[chainId].length
        );

        unchecked {
            uint256 configLength = configs.length;
            for (uint256 i = 0; i < configLength; i++) {
                configs[i] = OracleConfig({
                    oracleName: _oracleConfigs[chainId][i].oracleName,
                    symbol: _oracleConfigs[chainId][i].symbol,
                    mTokenKey: _oracleConfigs[chainId][i].mTokenKey
                });
            }
        }

        return configs;
    }

    function getCompositeOracleConfigurations(
        uint256 chainId
    ) public view returns (CompositeOracleConfig[] memory) {
        CompositeOracleConfig[] memory configs = new CompositeOracleConfig[](
            _compositeOracleConfigs[chainId].length
        );

        unchecked {
            uint256 configLength = configs.length;
            for (uint256 i = 0; i < configLength; i++) {
                configs[i] = CompositeOracleConfig({
                    compositeOracleName: _compositeOracleConfigs[chainId][i]
                        .compositeOracleName,
                    baseFeedName: _compositeOracleConfigs[chainId][i]
                        .baseFeedName,
                    symbol: _compositeOracleConfigs[chainId][i].symbol,
                    mTokenKey: _compositeOracleConfigs[chainId][i].mTokenKey
                });
            }
        }

        return configs;
    }

    function getMorphoOracleConfigurations(
        uint256 chainId
    ) public view returns (MorphoOracleConfig[] memory) {
        MorphoOracleConfig[] memory configs = new MorphoOracleConfig[](
            _MorphoOracleConfigs[chainId].length
        );

        unchecked {
            uint256 configLength = configs.length;
            for (uint256 i = 0; i < configLength; i++) {
                configs[i] = MorphoOracleConfig({
                    proxyName: _MorphoOracleConfigs[chainId][i].proxyName,
                    priceFeedName: _MorphoOracleConfigs[chainId][i]
                        .priceFeedName
                });
            }
        }

        return configs;
    }
}
