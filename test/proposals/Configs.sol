pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MockWeth} from "@test/mock/MockWeth.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {MockWormholeCore} from "@test/mock/MockWormholeCore.sol";
import {MockChainlinkOracle} from "@test/mock/MockChainlinkOracle.sol";
import {FaucetTokenWithPermit} from "@test/helper/FaucetToken.sol";

contract Configs {
    /// ----------------------------------------------------
    /// TODO add in interest rate model to this struct later
    /// once we get numbers around rates for each market
    /// ----------------------------------------------------
    struct CTokenConfiguration {
        uint256 collateralFactor; /// collateral factor of the asset
        uint256 reserveFactor; /// reserve factor of the asset
        uint256 seizeShare; /// fee gotten from liquidation
        uint256 supplyCap; /// supply cap
        uint256 borrowCap; /// borrow cap
        address priceFeed; /// chainlink price oracle
        address tokenAddress; /// underlying token address
        string addressesString; /// string used to set address in Addresses.sol
        string symbol; /// symbol of the mToken
        string name; /// name of the mToken
        JumpRateModelConfiguration jrm; /// jump rate model configuration information
    }

    struct JumpRateModelConfiguration {
        uint256 baseRatePerYear;
        uint256 multiplierPerYear;
        uint256 jumpMultiplierPerYear;
        uint256 kink;
    }

    mapping(uint256 => CTokenConfiguration[]) public cTokenConfigurations;

    struct EmissionConfig {
        address mToken;
        address owner;
        address emissionToken;
        uint256 supplyEmissionPerSec;
        uint256 borrowEmissionsPerSec;
        uint256 endTime;
    }

    /// mapping of all emission configs per chainid
    mapping(uint256 => EmissionConfig[]) public emissions;

    uint256 public constant _baseGoerliChainId = 84531;
    uint256 public constant localChainId = 31337;

    /// @notice initial mToken mint amount
    uint256 public constant initialMintAmount = 1 ether;

    function localInit(Addresses addresses) public {
        if (block.chainid == localChainId) {
            /// create mock wormhole core for local testing
            MockWormholeCore wormholeCore = new MockWormholeCore();

            addresses.addAddress("WORMHOLE_CORE", address(wormholeCore));
            addresses.addAddress("GUARDIAN", address(this));
        }
    }

    function deployAndMint(Addresses addresses) public {
        if (block.chainid == _baseGoerliChainId) {
            console.log("\n----- deploy and mint on base goerli -----\n");
            {
                FaucetTokenWithPermit token = new FaucetTokenWithPermit(
                    1e18,
                    "USD Coin",
                    6, /// USDC is 6 decimals
                    "USDC"
                );

                addresses.addAddress("USDC", address(token));

                token.allocateTo(
                    addresses.getAddress("TEMPORAL_GOVERNOR"),
                    initialMintAmount
                );
            }

            {
                MockWeth token = new MockWeth();
                token.mint(
                    addresses.getAddress("TEMPORAL_GOVERNOR"),
                    initialMintAmount
                );
                addresses.addAddress("WETH", address(token));
            }

            {
                FaucetTokenWithPermit token = new FaucetTokenWithPermit(
                    1e18,
                    "Wrapped BTC",
                    8, /// WBTC is 8 decimals
                    "WBTC"
                );
                token.allocateTo(
                    addresses.getAddress("TEMPORAL_GOVERNOR"),
                    initialMintAmount
                );

                addresses.addAddress("WBTC", address(token));
            }

            {
                FaucetTokenWithPermit token = new FaucetTokenWithPermit(
                    1e18,
                    "Coinbase Wrapped Staked ETH",
                    18, /// cbETH is 18 decimals
                    "cbETH"
                );
                token.allocateTo(
                    addresses.getAddress("TEMPORAL_GOVERNOR"),
                    initialMintAmount
                );

                addresses.addAddress("cbETH", address(token));
            }

            {
                FaucetTokenWithPermit token = new FaucetTokenWithPermit(
                    1e18,
                    "Wrapped liquid staked Ether 2.0",
                    18, /// wstETH is 18 decimals
                    "wstETH"
                );
                token.allocateTo(
                    addresses.getAddress("TEMPORAL_GOVERNOR"),
                    initialMintAmount
                );

                addresses.addAddress("wstETH", address(token));
            }
        }
    }

    function init(Addresses addresses) public {
        if (block.chainid == localChainId) {
            console.log("\n----- deploying locally -----\n");

            /// cToken config for WETH, WBTC and USDC on local

            {
                MockChainlinkOracle usdcOracle = new MockChainlinkOracle(
                    1e18,
                    6
                );
                MockChainlinkOracle ethOracle = new MockChainlinkOracle(
                    2_000e18,
                    18
                );
                FaucetTokenWithPermit token = new FaucetTokenWithPermit(
                    1e18,
                    "USD Coin",
                    6, /// 6 decimals
                    "USDC"
                );

                token.allocateTo(
                    addresses.getAddress("TEMPORAL_GOVERNOR"),
                    initialMintAmount
                );

                addresses.addAddress("USDC", address(token));
                addresses.addAddress("USDC_ORACLE", address(usdcOracle));
                addresses.addAddress("ETH_ORACLE", address(ethOracle));

                JumpRateModelConfiguration
                    memory jrmConfig = JumpRateModelConfiguration(
                        0.04e18, // 0.04 Base
                        0.45e18, // 0.45 Multiplier
                        0.8e18, // 0.8 Jump Multiplier
                        0.8e18 // 0.8 Kink
                    );

                CTokenConfiguration memory config = CTokenConfiguration({
                    collateralFactor: 0.9e18,
                    reserveFactor: 0.1e18,
                    seizeShare: 2.8e16, //2.8%,
                    supplyCap: 100e18,
                    borrowCap: 100e18,
                    priceFeed: address(usdcOracle),
                    tokenAddress: address(token),
                    name: "Moonwell USDC",
                    symbol: "mUSDC",
                    addressesString: "MOONWELL_USDC",
                    jrm: jrmConfig
                });

                cTokenConfigurations[localChainId].push(config);
            }

            {
                MockWeth token = new MockWeth();
                token.mint(
                    addresses.getAddress("TEMPORAL_GOVERNOR"),
                    initialMintAmount
                );
                addresses.addAddress("WETH", address(token));

                JumpRateModelConfiguration
                    memory jrmConfig = JumpRateModelConfiguration(
                        0.04e18, // 0.04 Base
                        0.45e18, // 0.45 Multiplier
                        0.8e18, // 0.8 Jump Multiplier
                        0.8e18 // 0.8 Kink
                    );

                CTokenConfiguration memory config = CTokenConfiguration({
                    collateralFactor: 0.6e18,
                    reserveFactor: 0.1e18,
                    seizeShare: 2.8e16, //2.8%,
                    supplyCap: 100e18,
                    borrowCap: 100e18,
                    priceFeed: addresses.getAddress("ETH_ORACLE"),
                    tokenAddress: address(token),
                    addressesString: "MOONWELL_ETH",
                    name: "Moonwell ETH",
                    symbol: "mETH",
                    jrm: jrmConfig
                });

                cTokenConfigurations[localChainId].push(config);
            }

            return;
        }

        if (block.chainid == _baseGoerliChainId) {
            console.log("\n----- deploying on base goerli -----\n");

            /// cToken config for WETH, WBTC, USDC, cbETH, and wstETH on base goerli testnet
            {

                address token = addresses.getAddress("USDC");

                JumpRateModelConfiguration
                    memory jrmConfigUSDC = JumpRateModelConfiguration(
                        0.00e18, // 0 Base per Gauntlet recommendation
                        0.15e18, // 0.15 Multiplier per Gauntlet recommendation 
                        3e18, // 3 Jump Multiplier per Gauntlet recommendation
                        0.6e18 // 0.6 Kink per Gauntlet recommendation
                    );

                CTokenConfiguration memory config = CTokenConfiguration({
                    collateralFactor: 0.8e18, // 80% per Gauntlet recommendation
                    reserveFactor: 0.15e18, // 15% per Gauntlet recommendation
                    seizeShare: 0.03e18, // 3% per Gauntlet recommendation
                    supplyCap: 40_000_000e18, // $40m per Gauntlet recommendation
                    borrowCap: 32_000_000e18, // $32m per Gauntlet recommendation
                    priceFeed: addresses.getAddress("USDC_ORACLE"),
                    tokenAddress: token,
                    name: "Moonwell USDC",
                    symbol: "mUSDC",
                    addressesString: "MOONWELL_USDC",
                    jrm: jrmConfigUSDC
                });

                cTokenConfigurations[_baseGoerliChainId].push(config);
            }

            {
                address token = addresses.getAddress("WETH");

                JumpRateModelConfiguration
                    memory jrmConfigWETH = JumpRateModelConfiguration(
                        0.02e18, // 0.02 Base per Gauntlet recommendation
                        0.15e18, // 0.15 Multiplier per Gauntlet recommendation
                        3e18, // 3 Jump Multiplier per Gauntlet recommendation
                        0.6e18 // 0.6 Kink per Gauntlet recommendation
                    );

                CTokenConfiguration memory config = CTokenConfiguration({
                    collateralFactor: 0.75e18, // 75% per Gauntlet recommendation
                    reserveFactor: 0.25e18, // 25% per Gauntlet recommendation
                    seizeShare: 0.03e18, // 3% per Gauntlet recommendation
                    supplyCap: 10_500e18, // 10,500 WETH per Gauntlet recommendation
                    borrowCap: 6_300e18, // 6,300 WETH per Gauntlet recommendation
                    priceFeed: addresses.getAddress("ETH_ORACLE"),
                    tokenAddress: token,
                    addressesString: "MOONWELL_WETH",
                    name: "Moonwell WETH",
                    symbol: "mWETH",
                    jrm: jrmConfigWETH
                });

                cTokenConfigurations[_baseGoerliChainId].push(config);
            }

            {
                address token = addresses.getAddress("WBTC");

                JumpRateModelConfiguration
                    memory jrmConfigWBTC = JumpRateModelConfiguration(
                        0.02e18, // 0.02 Base per Gauntlet recommendation
                        0.15e18, // 0.15 Multiplier per Gauntlet recommendation
                        3e18, // 3 Jump Multiplier per Gauntlet recommendation
                        0.6e18 // 0.6 Kink per Gauntlet recommendation
                    );

                CTokenConfiguration memory config = CTokenConfiguration({
                    collateralFactor: 0.7e18, // 70% per Gauntlet recommendation
                    reserveFactor: 0.25e18, // 25% per Gauntlet recommendation
                    seizeShare: 0.03e18, // 3% per Gauntlet recommendation
                    supplyCap: 330e18, // 330 WBTC per Gauntlet recommendation
                    borrowCap: 132e18, // 132 WBTC per Gauntlet recommendation
                    priceFeed: addresses.getAddress("WBTC_ORACLE"),
                    tokenAddress: token,
                    addressesString: "MOONWELL_WBTC",
                    name: "Moonwell WBTC",
                    symbol: "mWBTC",
                    jrm: jrmConfigWBTC
                });

                cTokenConfigurations[_baseGoerliChainId].push(config);
            }

            {
                address token = addresses.getAddress("cbETH");

                JumpRateModelConfiguration
                    memory jrmConfigCbETH = JumpRateModelConfiguration(
                        0.01e18, // 0.01 Base per Gauntlet recommendation
                        0.2e18, // 0.2 Multiplier per Gauntlet recommendation
                        3e18, // 3 Jump Multiplier per Gauntlet recommendation
                        0.45e18 // 0.45 Kink per Gauntlet recommendation
                    );

                CTokenConfiguration memory config = CTokenConfiguration({
                    collateralFactor: 0.73e18, // 73% per Gauntlet recommendation
                    reserveFactor: 0.25e18, // 25% per Gauntlet recommendation
                    seizeShare: 0.03e18, // 3% per Gauntlet recommendation
                    supplyCap: 5_000e18, // 5,000 cbETH per Gauntlet recommendation
                    borrowCap: 1_500e18, // 1,500 cbETH per Gauntlet recommendation
                    priceFeed: addresses.getAddress("cbETH_ORACLE"),
                    tokenAddress: token,
                    addressesString: "MOONWELL_cbETH",
                    name: "Moonwell cbETH",
                    symbol: "mcbETH",
                    jrm: jrmConfigCbETH
                });

                cTokenConfigurations[_baseGoerliChainId].push(config);
            }

            {
                address token = addresses.getAddress("wstETH");

                JumpRateModelConfiguration
                    memory jrmConfigWstETH = JumpRateModelConfiguration(
                        0.01e18, // 0.01 Base per Gauntlet recommendation
                        0.2e18, // 0.2 Multiplier per Gauntlet recommendation
                        3e18, // 3 Jump Multiplier per Gauntlet recommendation
                        0.45e18 // 0.45 Kink per Gauntlet recommendation
                    );

                CTokenConfiguration memory config = CTokenConfiguration({
                    collateralFactor: 0.73e18, // 73% per Gauntlet recommendation
                    reserveFactor: 0.25e18, // 25% per Gauntlet recommendation
                    seizeShare: 0.03e18, // 3% per Gauntlet recommendation
                    supplyCap: 3_700e18, // 3,700 wstETH per Gauntlet recommendation
                    borrowCap: 1_110e18, // 1,110 wstETH per Gauntlet recommendation
                    priceFeed: addresses.getAddress("wstETH_ORACLE"),
                    tokenAddress: token,
                    addressesString: "MOONWELL_wstETH",
                    name: "Moonwell wstETH",
                    symbol: "mwstETH",
                    jrm: jrmConfigWstETH
                });

                cTokenConfigurations[_baseGoerliChainId].push(config);
            }

            return;
        }
    }

    function initEmissions(Addresses addresses) public {
        if (block.chainid == localChainId) {
            {
                /// pay USDC Emissions for depositing ETH locally
                EmissionConfig memory emissionConfig = EmissionConfig({
                    mToken: addresses.getAddress("MOONWELL_ETH"),
                    owner: addresses.getAddress("GUARDIAN"),
                    emissionToken: addresses.getAddress("USDC"),
                    supplyEmissionPerSec: 1e18,
                    borrowEmissionsPerSec: 0,
                    endTime: block.timestamp + 365 days
                });

                emissions[localChainId].push(emissionConfig);
            }
        }
    }

    function getCTokenConfigurations(
        uint256 chainId
    ) public view returns (CTokenConfiguration[] memory) {
        CTokenConfiguration[] memory configs = new CTokenConfiguration[](
            cTokenConfigurations[chainId].length
        );

        unchecked {
            uint256 configLength = configs.length;
            for (uint256 i = 0; i < configLength; i++) {
                configs[i] = CTokenConfiguration({
                    collateralFactor: cTokenConfigurations[chainId][i]
                        .collateralFactor,
                    reserveFactor: cTokenConfigurations[chainId][i]
                        .reserveFactor,
                    seizeShare: cTokenConfigurations[chainId][i].seizeShare,
                    supplyCap: cTokenConfigurations[chainId][i].supplyCap,
                    borrowCap: cTokenConfigurations[chainId][i].borrowCap,
                    addressesString: cTokenConfigurations[chainId][i]
                        .addressesString,
                    priceFeed: cTokenConfigurations[chainId][i].priceFeed,
                    tokenAddress: cTokenConfigurations[chainId][i].tokenAddress,
                    symbol: cTokenConfigurations[chainId][i].symbol,
                    name: cTokenConfigurations[chainId][i].name,
                    jrm: cTokenConfigurations[chainId][i].jrm
                });
            }
        }

        return configs;
    }

    function getEmissionConfigurations(
        uint256 chainId
    ) public view returns (EmissionConfig[] memory) {
        EmissionConfig[] memory configs = new EmissionConfig[](
            emissions[chainId].length
        );

        unchecked {
            for (uint256 i = 0; i < configs.length; i++) {
                configs[i] = EmissionConfig({
                    mToken: emissions[chainId][i].mToken,
                    owner: emissions[chainId][i].owner,
                    emissionToken: emissions[chainId][i].emissionToken,
                    supplyEmissionPerSec: emissions[chainId][i]
                        .supplyEmissionPerSec,
                    borrowEmissionsPerSec: emissions[chainId][i]
                        .borrowEmissionsPerSec,
                    endTime: emissions[chainId][i].endTime
                });
            }
        }

        return configs;
    }
}
