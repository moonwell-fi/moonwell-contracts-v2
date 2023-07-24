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
                    6, /// 6 decimals
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
                    "Wrapped Bitcoin",
                    18, /// 6 decimals
                    "WBTC"
                );
                token.allocateTo(
                    addresses.getAddress("TEMPORAL_GOVERNOR"),
                    initialMintAmount
                );

                addresses.addAddress("WBTC", address(token));
            }
        }
    }

    function init(Addresses addresses) public {
        if (block.chainid == localChainId) {
            console.log("\n----- deploying locally -----\n");

            /// cToken config for WETH, WBTC and USDC on base goerli testnet

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
                        0.04e18,
                        0.45e18,
                        0.8e18,
                        0.8e18
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
                        0.04e18,
                        0.45e18,
                        0.8e18,
                        0.8e18
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

            /// cToken config for WETH, WBTC and USDC on base goerli testnet
            {

                address token = addresses.getAddress("USDC");

                JumpRateModelConfiguration
                    memory jrmConfig = JumpRateModelConfiguration(
                        0.04e18,
                        0.45e18,
                        0.8e18,
                        0.8e18
                    );

                CTokenConfiguration memory config = CTokenConfiguration({
                    collateralFactor: 0.9e18,
                    reserveFactor: 0.1e18,
                    seizeShare: 2.8e16, //2.8%,
                    supplyCap: 100e18,
                    borrowCap: 100e18,
                    priceFeed: addresses.getAddress("USDC_ORACLE"),
                    tokenAddress: token,
                    name: "Moonwell USDC",
                    symbol: "mUSDC",
                    addressesString: "MOONWELL_USDC",
                    jrm: jrmConfig
                });

                cTokenConfigurations[_baseGoerliChainId].push(config);
            }

            {
                address token = addresses.getAddress("WETH");

                JumpRateModelConfiguration
                    memory jrmConfig = JumpRateModelConfiguration(
                        0.04e18,
                        0.45e18,
                        0.8e18,
                        0.8e18
                    );

                CTokenConfiguration memory config = CTokenConfiguration({
                    collateralFactor: 0.6e18,
                    reserveFactor: 0.1e18,
                    seizeShare: 2.8e16, //2.8%,
                    supplyCap: 100e18,
                    borrowCap: 100e18,
                    priceFeed: addresses.getAddress("ETH_ORACLE"),
                    tokenAddress: token,
                    addressesString: "MOONWELL_ETH",
                    name: "Moonwell ETH",
                    symbol: "mETH",
                    jrm: jrmConfig
                });

                cTokenConfigurations[_baseGoerliChainId].push(config);
            }

            {
                address token = addresses.getAddress("WBTC");

                JumpRateModelConfiguration
                    memory jrmConfig = JumpRateModelConfiguration(
                        0.04e18,
                        0.45e18,
                        0.8e18,
                        0.8e18
                    );

                CTokenConfiguration memory config = CTokenConfiguration({
                    collateralFactor: 0.4e18,
                    reserveFactor: 0.1e18,
                    seizeShare: 2.8e16, //2.8%,
                    supplyCap: 100e18,
                    borrowCap: 100e18,
                    priceFeed: addresses.getAddress("BTC_ORACLE"),
                    tokenAddress: token,
                    addressesString: "MOONWELL_BTC",
                    name: "Moonwell BTC",
                    symbol: "mBTC",
                    jrm: jrmConfig
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
