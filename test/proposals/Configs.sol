pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {WETH9} from "@protocol/router/IWETH.sol";
import {MockWeth} from "@test/mock/MockWeth.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {MockWormholeCore} from "@test/mock/MockWormholeCore.sol";
import {MockChainlinkOracle} from "@test/mock/MockChainlinkOracle.sol";
import {FaucetTokenWithPermit} from "@test/helper/FaucetToken.sol";
import {ChainlinkCompositeOracle} from "@protocol/Oracles/ChainlinkCompositeOracle.sol";

contract Configs is Test {
    struct CTokenConfiguration {
        string addressesString; /// string used to set address in Addresses.sol
        uint256 borrowCap; /// borrow cap
        uint256 collateralFactor; /// collateral factor of the asset
        uint256 initialMintAmount;
        JumpRateModelConfiguration jrm; /// jump rate model configuration information
        string name; /// name of the mToken
        string priceFeedName; /// chainlink price oracle
        uint256 reserveFactor; /// reserve factor of the asset
        uint256 seizeShare; /// fee gotten from liquidation
        uint256 supplyCap; /// supply cap
        string symbol; /// symbol of the mToken
        string tokenAddressName; /// underlying token address
    }

    struct JumpRateModelConfiguration {
        uint256 baseRatePerYear;
        uint256 jumpMultiplierPerYear;
        uint256 kink;
        uint256 multiplierPerYear;
    }

    mapping(uint256 => CTokenConfiguration[]) public cTokenConfigurations;

    struct EmissionConfig {
        uint256 borrowEmissionsPerSec;
        address emissionToken;
        uint256 endTime;
        string mToken;
        string owner;
        uint256 supplyEmissionPerSec;
    }

    /// mapping of all emission configs per chainid
    mapping(uint256 => EmissionConfig[]) public emissions;

    uint256 public constant _baseGoerliChainId = 84531;
    uint256 public constant localChainId = 31337;
    uint256 public constant _baseChainId = 8453;

    /// @notice initial mToken mint amount
    uint256 public constant initialMintAmount = 1 ether;

    constructor() {
        string memory fileContents = vm.readFile(
            "./test/proposals/mainnetMTokens.json"
        );
        bytes memory rawJson = vm.parseJson(fileContents);

        CTokenConfiguration[] memory decodedJson = abi.decode(
            rawJson,
            (CTokenConfiguration[])
        );

        for (uint256 i = 0; i < decodedJson.length; i++) {
            require(
                decodedJson[i].collateralFactor <= 0.95e18,
                "collateral factor absurdly high, are you sure you want to proceed?"
            );

            /// possible to set supply caps and not borrow caps,
            /// but not set borrow caps and not set supply caps
            if (decodedJson[i].supplyCap != 0) {
                require(
                    decodedJson[i].supplyCap > decodedJson[i].borrowCap,
                    "borrow cap gte supply cap, are you sure you want to proceed?"
                );
            } else if (decodedJson[i].borrowCap != 0) {
                revert("borrow cap must be set with a supply cap");
            }

            console.log("\n ------ MToken Configuration ------");
            console.log("addressesString:", decodedJson[i].addressesString);
            console.log("supplyCap:", decodedJson[i].supplyCap);
            console.log("borrowCap:", decodedJson[i].borrowCap);
            console.log("collateralFactor:", decodedJson[i].collateralFactor);
            console.log("initialMintAmount:", decodedJson[i].initialMintAmount);
            console.log("name:", decodedJson[i].name);
            console.log("priceFeedName:", decodedJson[i].priceFeedName);
            console.log("reserveFactor:", decodedJson[i].reserveFactor);
            console.log("seizeShare:", decodedJson[i].seizeShare);
            console.log("supplyCap:", decodedJson[i].supplyCap);
            console.log("symbol:", decodedJson[i].symbol);
            console.log("tokenAddressName:", decodedJson[i].tokenAddressName);
            console.log(
                "jrm.baseRatePerYear:",
                decodedJson[i].jrm.baseRatePerYear
            );
            console.log(
                "jrm.multiplierPerYear:",
                decodedJson[i].jrm.multiplierPerYear
            );
            console.log(
                "jrm.jumpMultiplierPerYear:",
                decodedJson[i].jrm.jumpMultiplierPerYear
            );
            console.log("jrm.kink:", decodedJson[i].jrm.kink);

            cTokenConfigurations[_baseChainId].push(decodedJson[i]);
        }

        fileContents = vm.readFile(
            "./test/proposals/mainnetRewardStreams.json"
        );
        rawJson = vm.parseJson(fileContents);
        EmissionConfig[] memory decodedEmissions = abi.decode(
            rawJson,
            (EmissionConfig[])
        );

        for (uint256 i = 0; i < decodedEmissions.length; i++) {
            console.log("\n ------ Emission Configuration ------");
            console.log(
                "borrowEmissionsPerSec:",
                decodedEmissions[i].borrowEmissionsPerSec
            );
            console.log("emissionToken:", decodedEmissions[i].emissionToken);
            console.log("endTime:", decodedEmissions[i].endTime);
            console.log("mToken:", decodedEmissions[i].mToken);
            console.log("owner:", decodedEmissions[i].owner);
            console.log(
                "supplyEmissionPerSec:",
                decodedEmissions[i].supplyEmissionPerSec
            );

            emissions[_baseChainId].push(decodedEmissions[i]);
        }
    }

    function localInit(Addresses addresses) public {
        if (block.chainid == localChainId) {
            /// create mock wormhole core for local testing
            MockWormholeCore wormholeCore = new MockWormholeCore();

            addresses.addAddress("WORMHOLE_CORE", address(wormholeCore));
            addresses.addAddress("PAUSE_GUARDIAN", address(this));
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
                WETH9 weth = WETH9(addresses.getAddress("WETH"));
                vm.deal(address(this), 0.00001e18);
                weth.deposit{value: 0.00001e18}();
                weth.transfer(
                    addresses.getAddress("TEMPORAL_GOVERNOR"),
                    0.00001e18
                );
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
                    initialMintAmount: 1e6, /// supply 1 USDC
                    collateralFactor: 0.9e18,
                    reserveFactor: 0.1e18,
                    seizeShare: 2.8e16, //2.8%,
                    supplyCap: 10_000_000e6,
                    borrowCap: 10_000_000e6,
                    priceFeedName: "USDC_ORACLE",
                    tokenAddressName: "USDC",
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
                    initialMintAmount: 0.00001e18, /// supply .00001 eth
                    collateralFactor: 0.6e18,
                    reserveFactor: 0.1e18,
                    seizeShare: 2.8e16, //2.8%,
                    supplyCap: 100e18,
                    borrowCap: 100e18,
                    priceFeedName: "ETH_ORACLE",
                    tokenAddressName: "WETH",
                    addressesString: "MOONWELL_WETH",
                    name: "Moonwell WETH",
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
                JumpRateModelConfiguration
                    memory jrmConfigUSDC = JumpRateModelConfiguration(
                        0.00e18, // 0 Base per Gauntlet recommendation
                        0.15e18, // 0.15 Multiplier per Gauntlet recommendation
                        3e18, // 3 Jump Multiplier per Gauntlet recommendation
                        0.6e18 // 0.6 Kink per Gauntlet recommendation
                    );

                CTokenConfiguration memory config = CTokenConfiguration({
                    initialMintAmount: 1e6, /// supply 1 usdc
                    collateralFactor: 0.8e18, // 80% per Gauntlet recommendation
                    reserveFactor: 0.15e18, // 15% per Gauntlet recommendation
                    seizeShare: 0.03e18, // 3% per Gauntlet recommendation
                    supplyCap: 40_000_000e6, // $40m per Gauntlet recommendation
                    borrowCap: 32_000_000e6, // $32m per Gauntlet recommendation
                    priceFeedName: "USDC_ORACLE",
                    tokenAddressName: "USDC",
                    name: "Moonwell USDC",
                    symbol: "mUSDC",
                    addressesString: "MOONWELL_USDC",
                    jrm: jrmConfigUSDC
                });

                cTokenConfigurations[_baseGoerliChainId].push(config);
            }

            {
                JumpRateModelConfiguration
                    memory jrmConfigWETH = JumpRateModelConfiguration(
                        0.02e18, // 0.02 Base per Gauntlet recommendation
                        0.15e18, // 0.15 Multiplier per Gauntlet recommendation
                        3e18, // 3 Jump Multiplier per Gauntlet recommendation
                        0.6e18 // 0.6 Kink per Gauntlet recommendation
                    );

                CTokenConfiguration memory config = CTokenConfiguration({
                    initialMintAmount: 0.00001e18, /// supply .00001 eth
                    collateralFactor: 0.75e18, // 75% per Gauntlet recommendation
                    reserveFactor: 0.25e18, // 25% per Gauntlet recommendation
                    seizeShare: 0.03e18, // 3% per Gauntlet recommendation
                    supplyCap: 10_500e18, // 10,500 WETH per Gauntlet recommendation
                    borrowCap: 6_300e18, // 6,300 WETH per Gauntlet recommendation
                    priceFeedName: "ETH_ORACLE",
                    tokenAddressName: "WETH",
                    addressesString: "MOONWELL_WETH",
                    name: "Moonwell WETH",
                    symbol: "mWETH",
                    jrm: jrmConfigWETH
                });

                cTokenConfigurations[_baseGoerliChainId].push(config);
            }

            {
                JumpRateModelConfiguration
                    memory jrmConfigWBTC = JumpRateModelConfiguration(
                        0.02e18, // 0.02 Base per Gauntlet recommendation
                        0.15e18, // 0.15 Multiplier per Gauntlet recommendation
                        3e18, // 3 Jump Multiplier per Gauntlet recommendation
                        0.6e18 // 0.6 Kink per Gauntlet recommendation
                    );

                CTokenConfiguration memory config = CTokenConfiguration({
                    initialMintAmount: 0.00001e8, /// supply .00001 wBTC
                    collateralFactor: 0.7e18, // 70% per Gauntlet recommendation
                    reserveFactor: 0.25e18, // 25% per Gauntlet recommendation
                    seizeShare: 0.03e18, // 3% per Gauntlet recommendation
                    supplyCap: 330e18, // 330 WBTC per Gauntlet recommendation
                    borrowCap: 132e18, // 132 WBTC per Gauntlet recommendation
                    priceFeedName: "WBTC_ORACLE",
                    tokenAddressName: "WBTC",
                    addressesString: "MOONWELL_WBTC",
                    name: "Moonwell WBTC",
                    symbol: "mWBTC",
                    jrm: jrmConfigWBTC
                });

                cTokenConfigurations[_baseGoerliChainId].push(config);
            }

            {
                /// 1 cbETH = 1.0429 ETH
                if (addresses.getAddress("cbETH_ORACLE") == address(0)) {
                    MockChainlinkOracle oracle = new MockChainlinkOracle(
                        1.04296945e18,
                        18
                    );
                    ChainlinkCompositeOracle cbEthOracle = new ChainlinkCompositeOracle(
                            addresses.getAddress("ETH_ORACLE"),
                            address(oracle),
                            address(0)
                        );

                    addresses.addAddress("cbETH_ORACLE", address(cbEthOracle));
                }

                JumpRateModelConfiguration
                    memory jrmConfigCbETH = JumpRateModelConfiguration(
                        0.01e18, // 0.01 Base per Gauntlet recommendation
                        0.2e18, // 0.2 Multiplier per Gauntlet recommendation
                        3e18, // 3 Jump Multiplier per Gauntlet recommendation
                        0.45e18 // 0.45 Kink per Gauntlet recommendation
                    );

                CTokenConfiguration memory config = CTokenConfiguration({
                    initialMintAmount: 0.00001e18, /// supply .00001 cbETH
                    collateralFactor: 0.73e18, // 73% per Gauntlet recommendation
                    reserveFactor: 0.25e18, // 25% per Gauntlet recommendation
                    seizeShare: 0.03e18, // 3% per Gauntlet recommendation
                    supplyCap: 5_000e18, // 5,000 cbETH per Gauntlet recommendation
                    borrowCap: 1_500e18, // 1,500 cbETH per Gauntlet recommendation
                    priceFeedName: "cbETH_ORACLE",
                    tokenAddressName: "cbETH",
                    addressesString: "MOONWELL_cbETH",
                    name: "Moonwell cbETH",
                    symbol: "mcbETH",
                    jrm: jrmConfigCbETH
                });

                cTokenConfigurations[_baseGoerliChainId].push(config);
            }

            {
                if (addresses.getAddress("wstETH_ORACLE") == address(0)) {
                    /// 1 stETH = 0.99938151 ETH
                    MockChainlinkOracle stETHETHOracle = new MockChainlinkOracle(
                            0.99938151e18,
                            18
                        );

                    /// 1 wstETH = 1.13297632 stETH
                    MockChainlinkOracle wstETHstETHOracle = new MockChainlinkOracle(
                            1.13297632e18,
                            18
                        );

                    ChainlinkCompositeOracle wstETHOracle = new ChainlinkCompositeOracle(
                            addresses.getAddress("ETH_ORACLE"),
                            address(stETHETHOracle),
                            address(wstETHstETHOracle)
                        );

                    addresses.addAddress(
                        "wstETH_ORACLE",
                        address(wstETHOracle)
                    );
                }

                JumpRateModelConfiguration
                    memory jrmConfigWstETH = JumpRateModelConfiguration(
                        0.01e18, // 0.01 Base per Gauntlet recommendation
                        0.2e18, // 0.2 Multiplier per Gauntlet recommendation
                        3e18, // 3 Jump Multiplier per Gauntlet recommendation
                        0.45e18 // 0.45 Kink per Gauntlet recommendation
                    );

                CTokenConfiguration memory config = CTokenConfiguration({
                    initialMintAmount: 0.00001e18, /// supply .00001 wSTETH
                    collateralFactor: 0.73e18, // 73% per Gauntlet recommendation
                    reserveFactor: 0.25e18, // 25% per Gauntlet recommendation
                    seizeShare: 0.03e18, // 3% per Gauntlet recommendation
                    supplyCap: 3_700e18, // 3,700 wstETH per Gauntlet recommendation
                    borrowCap: 1_110e18, // 1,110 wstETH per Gauntlet recommendation
                    priceFeedName: "wstETH_ORACLE",
                    tokenAddressName: "wstETH",
                    addressesString: "MOONWELL_wstETH",
                    name: "Moonwell wstETH",
                    symbol: "mwstETH",
                    jrm: jrmConfigWstETH
                });

                cTokenConfigurations[_baseGoerliChainId].push(config);
            }

            return;
        }

        if (block.chainid == _baseChainId) {
            if (addresses.getAddress("cbETH_ORACLE") == address(0)) {
                ChainlinkCompositeOracle cbEthOracle = new ChainlinkCompositeOracle(
                        addresses.getAddress("ETH_ORACLE"),
                        addresses.getAddress("cbETHETH_ORACLE"),
                        address(0)
                    );

                addresses.addAddress("cbETH_ORACLE", address(cbEthOracle));
            }

            return;
        }
    }

    function initEmissions(Addresses addresses, address) public {
        Configs.CTokenConfiguration[]
            memory mTokenConfigs = getCTokenConfigurations(block.chainid);

        if (
            (block.chainid == localChainId ||
                block.chainid == _baseGoerliChainId) &&
            addresses.getAddress("WELL") == address(0)
        ) {
            FaucetTokenWithPermit token = new FaucetTokenWithPermit(
                1e18,
                "Wormhole WELL",
                18, /// WELL is 18 decimals
                "WELL"
            );

            token.allocateTo(addresses.getAddress("MRD_PROXY"), 100_000_000e18);

            addresses.addAddress("WELL", address(token));
        }

        //// create reward configuration for all mTokens
        unchecked {
            for (uint256 i = 0; i < mTokenConfigs.length; i++) {
                if (block.chainid == localChainId) {
                    /// set supply speed to be 0 and borrow reward speeds to 1

                    /// pay USDC Emissions for depositing ETH locally
                    EmissionConfig memory emissionConfig = EmissionConfig({
                        mToken: mTokenConfigs[i].addressesString,
                        owner: "EMISSIONS_ADMIN",
                        emissionToken: addresses.getAddress("WELL"),
                        supplyEmissionPerSec: 0,
                        borrowEmissionsPerSec: 0,
                        endTime: block.timestamp + 4 weeks
                    });

                    emissions[localChainId].push(emissionConfig);
                }

                if (block.chainid == _baseGoerliChainId) {
                    /// pay USDC Emissions for depositing ETH locally
                    EmissionConfig memory emissionConfig = EmissionConfig({
                        mToken: mTokenConfigs[i].addressesString,
                        owner: "EMISSIONS_ADMIN",
                        emissionToken: addresses.getAddress("WELL"),
                        supplyEmissionPerSec: 0,
                        borrowEmissionsPerSec: 0,
                        endTime: block.timestamp + 4 weeks
                    });

                    emissions[block.chainid].push(emissionConfig);
                }
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
                    initialMintAmount: cTokenConfigurations[chainId][i]
                        .initialMintAmount,
                    collateralFactor: cTokenConfigurations[chainId][i]
                        .collateralFactor,
                    reserveFactor: cTokenConfigurations[chainId][i]
                        .reserveFactor,
                    seizeShare: cTokenConfigurations[chainId][i].seizeShare,
                    supplyCap: cTokenConfigurations[chainId][i].supplyCap,
                    borrowCap: cTokenConfigurations[chainId][i].borrowCap,
                    addressesString: cTokenConfigurations[chainId][i]
                        .addressesString,
                    priceFeedName: cTokenConfigurations[chainId][i]
                        .priceFeedName,
                    tokenAddressName: cTokenConfigurations[chainId][i]
                        .tokenAddressName,
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
