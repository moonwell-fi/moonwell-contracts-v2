pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@utils/ChainIds.sol";

abstract contract ChainlinkOracleConfigs is Test {
    struct OracleConfig {
        string oracleName; /// e.g., CHAINLINK_ETH_USD
        string symbol; /// e.g., as found in addresses
        string mTokenKey; /// e.g., MOONWELL_WETH (defaults to MOONWELL_[symbol] if not specified)
    }

    struct MorphoOracleConfig {
        string proxyName; /// e.g., CHAINLINK_stkWELL_USD (used for proxy identifier)
        string priceFeedName; /// e.g., CHAINLINK_WELL_USD (the actual price feed oracle)
    }

    /// oracle configurations per chain id
    mapping(uint256 => OracleConfig[]) internal _oracleConfigs;

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
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("cbETHETH_ORACLE", "cbETH", "MOONWELL_cbETH")
        );
        // Composite oracles don't support latestRound(), deferred to follow-up
        // _oracleConfigs[BASE_CHAIN_ID].push(
        //     OracleConfig("CHAINLINK_WSTETH_STETH_COMPOSITE_ORACLE", "wstETH", "MOONWELL_wstETH")
        // );
        // _oracleConfigs[BASE_CHAIN_ID].push(
        //     OracleConfig("CHAINLINK_RETH_ETH_EXCHANGE_RATE_ORACLE", "rETH", "MOONWELL_rETH")
        // );
        // _oracleConfigs[BASE_CHAIN_ID].push(
        //     OracleConfig("CHAINLINK_WEETH_USD_COMPOSITE_ORACLE", "weETH", "MOONWELL_weETH")
        // );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_AERO_ORACLE", "AERO", "MOONWELL_AERO")
        );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_BTC_USD", "cbBTC", "MOONWELL_cbBTC")
        );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_EURC_USD", "EURC", "MOONWELL_EURC")
        );
        // _oracleConfigs[BASE_CHAIN_ID].push(
        //     OracleConfig("CHAINLINK_wrsETH_COMPOSITE_ORACLE", "wrsETH", "MOONWELL_wrsETH")
        // );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_WELL_USD", "xWELL_PROXY", "MOONWELL_WELL")
        );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_USDS_USD", "USDS", "MOONWELL_USDS")
        );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_TBTC_USD", "TBTC", "MOONWELL_TBTC")
        );
        // _oracleConfigs[BASE_CHAIN_ID].push(
        //     OracleConfig("CHAINLINK_LBTC_BTC_COMPOSITE_ORACLE", "LBTC", "MOONWELL_LBTC")
        // );
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

        /// Initialize oracle configurations for Optimism
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
        // Composite oracles don't support latestRound(), deferred to follow-up
        // _oracleConfigs[OPTIMISM_CHAIN_ID].push(
        //     OracleConfig("CHAINLINK_WSTETH_USD_COMPOSITE_ORACLE", "wstETH", "MOONWELL_wstETH")
        // );
        // _oracleConfigs[OPTIMISM_CHAIN_ID].push(
        //     OracleConfig("CHAINLINK_cbETH_USD_COMPOSITE_ORACLE", "cbETH", "MOONWELL_cbETH")
        // );
        // _oracleConfigs[OPTIMISM_CHAIN_ID].push(
        //     OracleConfig("CHAINLINK_RETH_ETH_EXCHANGE_RATE_ORACLE", "rETH", "MOONWELL_rETH")
        // );
        // _oracleConfigs[OPTIMISM_CHAIN_ID].push(
        //     OracleConfig("CHAINLINK_WEETH_USD_COMPOSITE_ORACLE", "weETH", "MOONWELL_weETH")
        // );
        _oracleConfigs[OPTIMISM_CHAIN_ID].push(
            OracleConfig("CHAINLINK_OP_USD", "OP", "MOONWELL_OP")
        );
        _oracleConfigs[OPTIMISM_CHAIN_ID].push(
            OracleConfig("CHAINLINK_VELO_USD", "VELO", "MOONWELL_VELO")
        );
        // _oracleConfigs[OPTIMISM_CHAIN_ID].push(
        //     OracleConfig("CHAINLINK_wrsETH_COMPOSITE_ORACLE", "wrsETH", "MOONWELL_wrsETH")
        // );
        _oracleConfigs[OPTIMISM_CHAIN_ID].push(
            OracleConfig("CHAINLINK_USDT_USD", "USDT0", "MOONWELL_USDT0")
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
