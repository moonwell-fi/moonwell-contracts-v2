pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {WETH9} from "@protocol/router/IWETH.sol";
import {MockWeth} from "@test/mock/MockWeth.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MockWormholeCore} from "@test/mock/MockWormholeCore.sol";
import {MockChainlinkOracle} from "@test/mock/MockChainlinkOracle.sol";
import {FaucetTokenWithPermit} from "@test/helper/FaucetToken.sol";
import {ChainlinkCompositeOracle} from "@protocol/oracles/ChainlinkCompositeOracle.sol";

abstract contract Configs is Test {
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

    uint256 public constant _optimismSepoliaChainId = 11155420;
    uint256 public constant _baseSepoliaChainId = 84532;
    uint256 public constant _localChainId = 31337;
    uint256 public constant _baseChainId = 8453;

    /// @notice initial mToken mint amount
    uint256 public constant initialMintAmount = 1 ether;

    function _setEmissionConfiguration(string memory emissionPath) internal {
        string memory fileContents = vm.readFile(emissionPath);
        bytes memory rawJson = vm.parseJson(fileContents);
        EmissionConfig[] memory decodedEmissions = abi.decode(
            rawJson,
            (EmissionConfig[])
        );

        for (uint256 i = 0; i < decodedEmissions.length; i++) {
            emissions[block.chainid].push(decodedEmissions[i]);
        }
    }

    function _setMTokenConfiguration(string memory mTokenPath) internal {
        string memory fileContents = vm.readFile(mTokenPath);
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

            cTokenConfigurations[block.chainid].push(decodedJson[i]);
        }
    }

    function localInit(Addresses addresses) public {
        if (block.chainid == _localChainId) {
            /// create mock wormhole core for local testing
            MockWormholeCore wormholeCore = new MockWormholeCore();

            addresses.addAddress("WORMHOLE_CORE", address(wormholeCore));
            addresses.addAddress("PAUSE_GUARDIAN", address(this));
        }
    }

    function deployAndMint(Addresses addresses) public {
        if (block.chainid == _baseSepoliaChainId) {
            // USDBC
            address usdbc = addresses.getAddress("USDBC");
            FaucetTokenWithPermit(usdbc).allocateTo(
                addresses.getAddress("TEMPORAL_GOVERNOR"),
                initialMintAmount
            );

            address cbeth = addresses.getAddress("cbETH");
            FaucetTokenWithPermit(cbeth).allocateTo(
                addresses.getAddress("TEMPORAL_GOVERNOR"),
                initialMintAmount
            );

            // WETH
            WETH9 weth = WETH9(addresses.getAddress("WETH"));
            vm.deal(address(this), 0.00001e18);
            weth.deposit{value: 0.00001e18}();
            weth.transfer(
                addresses.getAddress("TEMPORAL_GOVERNOR"),
                0.00001e18
            );
        }
        if (block.chainid == _optimismSepoliaChainId) {
            // allocate tokens to temporal governor
            FaucetTokenWithPermit usdc = new FaucetTokenWithPermit(
                1e18,
                "USD Coin",
                6, /// 6 decimals
                "USDC"
            );

            addresses.addAddress("USDC", address(usdc));

            FaucetTokenWithPermit wsteth = new FaucetTokenWithPermit(
                1e18,
                "wstETH",
                18, /// 18 decimals
                "wstETH"
            );

            addresses.addAddress("wstETH", address(wsteth));

            FaucetTokenWithPermit(usdc).allocateTo(
                addresses.getAddress("TEMPORAL_GOVERNOR"),
                initialMintAmount
            );

            // wstETH
            FaucetTokenWithPermit(wsteth).allocateTo(
                addresses.getAddress("TEMPORAL_GOVERNOR"),
                initialMintAmount
            );

            // WETH
            WETH9 weth = WETH9(addresses.getAddress("WETH"));
            vm.deal(address(this), 0.00001e18);
            weth.deposit{value: 0.00001e18}();
            weth.transfer(
                addresses.getAddress("TEMPORAL_GOVERNOR"),
                0.00001e18
            );
        }
    }

    function init(Addresses addresses) public {
        if (block.chainid == _localChainId) {
            console.log("\n----- deploying locally -----\n");

            /// cToken config for WETH, WBTC and USDBC on local

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
                    "USDBC"
                );

                token.allocateTo(
                    addresses.getAddress("TEMPORAL_GOVERNOR"),
                    initialMintAmount
                );

                addresses.addAddress("USDBC", address(token));
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
                    initialMintAmount: 1e6, /// supply 1 USDBC
                    collateralFactor: 0.9e18,
                    reserveFactor: 0.1e18,
                    seizeShare: 2.8e16, //2.8%,
                    supplyCap: 10_000_000e6,
                    borrowCap: 10_000_000e6,
                    priceFeedName: "USDC_ORACLE",
                    tokenAddressName: "USDBC",
                    name: "Moonwell USDBC",
                    symbol: "mUSDbC",
                    addressesString: "MOONWELL_USDBC",
                    jrm: jrmConfig
                });

                cTokenConfigurations[_localChainId].push(config);
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

                cTokenConfigurations[_localChainId].push(config);
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
            (block.chainid == _localChainId) &&
            addresses.getAddress("GOVTOKEN") == address(0)
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
                if (block.chainid == _localChainId) {
                    /// set supply speed to be 0 and borrow reward speeds to 1

                    /// pay USDBC Emissions for depositing ETH locally
                    EmissionConfig memory emissionConfig = EmissionConfig({
                        mToken: mTokenConfigs[i].addressesString,
                        owner: "EMISSIONS_ADMIN",
                        emissionToken: addresses.getAddress("GOVTOKEN"),
                        supplyEmissionPerSec: 0,
                        borrowEmissionsPerSec: 0,
                        endTime: block.timestamp + 4 weeks
                    });

                    emissions[_localChainId].push(emissionConfig);
                }

                if (
                    block.chainid == _baseSepoliaChainId ||
                    block.chainid == _baseChainId
                ) {
                    /// pay USDBC Emissions for depositing ETH locally
                    EmissionConfig memory emissionConfig = EmissionConfig({
                        mToken: mTokenConfigs[i].addressesString,
                        owner: "EMISSIONS_ADMIN",
                        emissionToken: addresses.getAddress("xWELL_PROXY"),
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
