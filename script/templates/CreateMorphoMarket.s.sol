// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Script.sol";
import "@forge-std/Test.sol";
import {stdJson} from "@forge-std/StdJson.sol";

import "@protocol/utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {IMetaMorpho, MarketParams, IMetaMorphoStaticTyping} from "@protocol/morpho/IMetaMorpho.sol";
import {IMorphoBlue} from "@protocol/morpho/IMorphoBlue.sol";
import {IMorphoChainlinkOracleV2Factory} from "@protocol/morpho/IMorphoChainlinkOracleFactory.sol";
import {IMorphoChainlinkOracleV2} from "@protocol/morpho/IMorphoChainlinkOracleV2.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {ChainlinkOEVMorphoWrapper} from "@protocol/oracles/ChainlinkOEVMorphoWrapper.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {console} from "@forge-std/console.sol";
import {IERC4626} from "@forge-std/interfaces/IERC4626.sol";

/// @notice Template script: Create a Morpho Blue market and configure a vault cap/supply queue based on JSON
contract CreateMorphoMarket is Script, Test {
    using ChainIds for uint256;
    using stdJson for string;

    struct MarketConfig {
        string vaultAddressName; // vault registry name to configure caps/queues
        string loanTokenName; // name key for loan token (Addresses)
        string collateralTokenName; // name key for collateral token (Addresses)
        string irmName; // name key for IRM (Addresses)
        uint256 lltv; // loan-to-value mantissa
        // Optional oracle deployment block: presence triggers deployment if missing
        bool oracleConfigPresent;
        OracleConfig oracle;
    }

    struct OracleConfig {
        string addressName; // name key for oracle (Addresses)
        string proxyAddressName; // name key for oracle proxy wrapper (Addresses)
        string baseFeedName; // e.g. CHAINLINK_WELL_USD
        uint8 baseFeedDecimals; // e.g. 18
        string quoteFeedName; // e.g. CHAINLINK_USDC_USD
        uint8 quoteFeedDecimals; // e.g. 6
        string coreMarketAsFeeRecipient; // e.g. MOONWELL_WELL
    }

    uint256 internal constant MARKET_PARAMS_BYTES_LENGTH = 5 * 32;

    uint16 internal constant FEE_MULTIPLIER = 9000; // 90%
    uint8 internal constant MAX_ROUND_DELAY = 10;
    uint8 internal constant MAX_DECREMENTS = 10;

    string internal constant MORPHO_IMPLEMENTATION_NAME =
        "CHAINLINK_OEV_MORPHO_WRAPPER_IMPL";

    function run() external {
        // Setup fork for Base chain
        BASE_FORK_ID.createForksAndSelect();

        string memory json = vm.readFile(vm.envString("NEW_MARKET_PATH"));
        MarketConfig memory cfg = _parseConfig(json);

        Addresses addresses = new Addresses();

        vm.startBroadcast();

        // Ensure oracle is deployed or deploy it
        _ensureOracle(addresses, cfg.oracleConfigPresent, cfg.oracle);

        MarketParams memory market = _buildMarketParams(addresses, cfg);
        bytes32 marketId = _computeMarketId(market);
        address morphoBlue = addresses.getAddress("MORPHO_BLUE");

        _createMarket(morphoBlue, market, marketId, cfg);

        _validate(addresses, market, cfg, marketId);

        vm.stopBroadcast();

        addresses.printAddresses();
    }

    function _parseConfig(
        string memory json
    ) internal pure returns (MarketConfig memory cfg) {
        cfg = _parseCore(json);
        (bool hasOracle, OracleConfig memory ocfg) = _maybeParseOracle(json);
        if (hasOracle) {
            cfg.oracleConfigPresent = true;
            cfg.oracle = ocfg;
        }
    }

    function _parseCore(
        string memory json
    ) internal pure returns (MarketConfig memory cfg) {
        cfg.vaultAddressName = json.readString(".vaultAddressName");
        cfg.loanTokenName = json.readString(".loanTokenName");
        cfg.collateralTokenName = json.readString(".collateralTokenName");
        cfg.irmName = json.readString(".irmName");
        cfg.lltv = json.readUint(".lltv");
    }

    function _maybeParseOracle(
        string memory json
    ) internal pure returns (bool present, OracleConfig memory ocfg) {
        bytes memory oracleRaw = json.parseRaw(".oracle");
        if (oracleRaw.length == 0) {
            return (false, ocfg);
        }
        present = true;
        ocfg.baseFeedName = json.readString(".oracle.baseFeedName");
        ocfg.baseFeedDecimals = uint8(
            json.readUint(".oracle.baseFeedDecimals")
        );
        ocfg.quoteFeedName = json.readString(".oracle.quoteFeedName");
        ocfg.quoteFeedDecimals = uint8(
            json.readUint(".oracle.quoteFeedDecimals")
        );
        ocfg.addressName = json.readString(".oracle.addressName");
        ocfg.proxyAddressName = json.readString(".oracle.proxyAddressName");

        // coreMarketAsFeeRecipient is required
        bytes memory feeRecipientRaw = json.parseRaw(
            ".oracle.coreMarketAsFeeRecipient"
        );
        require(
            feeRecipientRaw.length > 0,
            "oracle.coreMarketAsFeeRecipient is required"
        );
        ocfg.coreMarketAsFeeRecipient = json.readString(
            ".oracle.coreMarketAsFeeRecipient"
        );
    }

    function _computeMarketId(
        MarketParams memory params
    ) internal pure returns (bytes32 marketParamsId) {
        assembly ("memory-safe") {
            marketParamsId := keccak256(params, MARKET_PARAMS_BYTES_LENGTH)
        }
    }

    function _ensureOracle(
        Addresses addresses,
        bool oracleConfigPresent,
        OracleConfig memory ocfg
    ) internal {
        if (oracleConfigPresent && !addresses.isAddressSet(ocfg.addressName)) {
            _deployAndRegisterOracle(addresses, ocfg);
        } else {
            require(
                addresses.isAddressSet(ocfg.addressName),
                "Oracle not found"
            );
        }
    }

    function _buildMarketParams(
        Addresses addresses,
        MarketConfig memory cfg
    ) internal view returns (MarketParams memory) {
        return
            MarketParams({
                loanToken: addresses.getAddress(cfg.loanTokenName),
                collateralToken: addresses.getAddress(cfg.collateralTokenName),
                oracle: addresses.getAddress(cfg.oracle.addressName),
                irm: addresses.getAddress(cfg.irmName),
                lltv: cfg.lltv
            });
    }

    function _createMarket(
        address morphoBlue,
        MarketParams memory market,
        bytes32 marketId,
        MarketConfig memory cfg
    ) internal {
        console.log("Creating market on Morpho Blue with parameters:");
        console.log("Loan token (%s): %s", cfg.loanTokenName, market.loanToken);
        console.log(
            "Collateral token (%s): %s",
            cfg.collateralTokenName,
            market.collateralToken
        );
        console.log("Oracle (%s): %s", cfg.oracle.addressName, market.oracle);
        console.log("IRM (%s): %s", cfg.irmName, market.irm);
        console.log("LLTV: %s", market.lltv);

        IMorphoBlue(morphoBlue).createMarket(market);

        console.log("Market created:");
        console.logBytes32(marketId);
    }

    function _validate(
        Addresses addresses,
        MarketParams memory market,
        MarketConfig memory cfg,
        bytes32 marketId
    ) internal view {
        // Market params match config
        assertEq(
            market.loanToken,
            addresses.getAddress(cfg.loanTokenName),
            "Market loan token mismatch"
        );
        assertEq(
            market.collateralToken,
            addresses.getAddress(cfg.collateralTokenName),
            "Market collateral token mismatch"
        );
        assertEq(
            market.oracle,
            addresses.getAddress(cfg.oracle.addressName),
            "Market oracle mismatch"
        );
        assertEq(
            market.irm,
            addresses.getAddress(cfg.irmName),
            "Market IRM mismatch"
        );
        assertEq(market.lltv, cfg.lltv, "Market LLTV mismatch");

        console.log("Validation completed successfully");
        console.log("Market loan token:", market.loanToken);
        console.log("Market collateral token:", market.collateralToken);
        console.log("Market oracle:", market.oracle);
        console.log("Market IRM:", market.irm);
        console.log("Market LLTV:", market.lltv);
        console.log("Market id:");
        console.logBytes32(marketId);
    }

    function _deployAndRegisterOracle(
        Addresses addresses,
        CreateMorphoMarket.OracleConfig memory ocfg
    ) internal {
        IMorphoChainlinkOracleV2Factory oracleFactory = IMorphoChainlinkOracleV2Factory(
                addresses.getAddress("MORPHO_CHAINLINK_ORACLE_FACTORY")
            );
        AggregatorV3Interface baseFeed = _getOrDeployBaseFeed(addresses, ocfg);
        IMorphoChainlinkOracleV2 oracle = _createOracle(
            oracleFactory,
            baseFeed,
            AggregatorV3Interface(addresses.getAddress(ocfg.quoteFeedName)), // assuming we don't deploy quote feeds (ie USDC)
            ocfg.baseFeedDecimals,
            ocfg.quoteFeedDecimals
        );
        addresses.addAddress(ocfg.addressName, address(oracle));
    }

    function _getOrDeployBaseFeed(
        Addresses addresses,
        CreateMorphoMarket.OracleConfig memory ocfg
    ) internal returns (AggregatorV3Interface) {
        // Reuse the proxy if it already exists for this market's base feed wrapper
        string memory proxyAddressName = string(
            abi.encodePacked(ocfg.proxyAddressName, "_PROXY")
        );
        if (addresses.isAddressSet(proxyAddressName)) {
            return
                AggregatorV3Interface(addresses.getAddress(proxyAddressName));
        }

        ChainlinkOEVMorphoWrapper logic;
        if (!addresses.isAddressSet(MORPHO_IMPLEMENTATION_NAME)) {
            logic = new ChainlinkOEVMorphoWrapper();
            addresses.addAddress(MORPHO_IMPLEMENTATION_NAME, address(logic));
        } else {
            logic = ChainlinkOEVMorphoWrapper(
                addresses.getAddress(MORPHO_IMPLEMENTATION_NAME)
            );
        }

        ProxyAdmin proxyAdmin;
        if (!addresses.isAddressSet("CHAINLINK_ORACLE_PROXY_ADMIN")) {
            proxyAdmin = new ProxyAdmin();
            addresses.addAddress(
                "CHAINLINK_ORACLE_PROXY_ADMIN",
                address(proxyAdmin)
            );
            proxyAdmin.transferOwnership(
                addresses.getAddress("TEMPORAL_GOVERNOR")
            );
        } else {
            proxyAdmin = ProxyAdmin(
                addresses.getAddress("CHAINLINK_ORACLE_PROXY_ADMIN")
            );
        }

        bytes memory initData = abi.encodeWithSelector(
            ChainlinkOEVMorphoWrapper.initializeV2.selector,
            addresses.getAddress(ocfg.baseFeedName),
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            addresses.getAddress("MORPHO_BLUE"),
            ocfg.coreMarketAsFeeRecipient,
            FEE_MULTIPLIER,
            MAX_ROUND_DELAY,
            MAX_DECREMENTS
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(logic),
            address(proxyAdmin),
            initData
        );
        addresses.addAddress(proxyAddressName, address(proxy));
    }

    function _createOracle(
        IMorphoChainlinkOracleV2Factory oracleFactory,
        AggregatorV3Interface baseFeed,
        AggregatorV3Interface quoteFeed,
        uint8 baseFeedDecimals,
        uint8 quoteFeedDecimals
    ) internal returns (IMorphoChainlinkOracleV2) {
        IMorphoChainlinkOracleV2 oracle = oracleFactory
            .createMorphoChainlinkOracleV2(
                IERC4626(address(0)), // no base vault
                1, // no conversion sample
                baseFeed,
                AggregatorV3Interface(address(0)),
                baseFeedDecimals,
                IERC4626(address(0)), // no quote vault
                1, // no conversion sample
                quoteFeed,
                AggregatorV3Interface(address(0)), // no second quote feed
                quoteFeedDecimals,
                bytes32(0) // no salt
            );
        return oracle;
    }
}

/// @notice Follow-up script to set cap and queue on an existing vault for a given market
contract ConfigureMorphoMarketCaps is Script, Test {
    using ChainIds for uint256;
    using stdJson for string;

    struct CapsConfig {
        string vaultAddressName;
        string loanTokenName;
        string collateralTokenName;
        string irmName;
        uint256 lltv;
        uint256 supplyCap;
        bool setSupplyQueue;
        CreateMorphoMarket.OracleConfig oracle;
    }

    uint256 internal constant MARKET_PARAMS_BYTES_LENGTH = 5 * 32;

    function run() external {
        BASE_FORK_ID.createForksAndSelect();

        string memory json = vm.readFile(vm.envString("NEW_MARKET_PATH"));
        CapsConfig memory cfg = _parse(json);

        Addresses addresses = new Addresses();

        // only needed for existing vaults
        // vm.startBroadcast(addresses.getAddress("ANTHIAS_MULTISIG"));
        vm.startBroadcast();

        MarketParams memory market = MarketParams({
            loanToken: addresses.getAddress(cfg.loanTokenName),
            collateralToken: addresses.getAddress(cfg.collateralTokenName),
            oracle: addresses.getAddress(cfg.oracle.addressName),
            irm: addresses.getAddress(cfg.irmName),
            lltv: cfg.lltv
        });

        bytes32 marketId = _computeMarketId(market);
        IMetaMorpho vault = IMetaMorpho(
            addresses.getAddress(cfg.vaultAddressName)
        );

        vault.submitCap(market, cfg.supplyCap);
        vault.acceptCap(market);
        if (cfg.setSupplyQueue) {
            bytes32[] memory queue = new bytes32[](1);
            queue[0] = marketId;
            vault.setSupplyQueue(queue);
        }
        vm.stopBroadcast();
        (
            uint184 cap,
            bool accepted,
            uint64 removableAt
        ) = IMetaMorphoStaticTyping(address(vault)).config(marketId);
        assertEq(cap, cfg.supplyCap, "cap mismatch");
        assertEq(accepted, true, "cap not accepted");
        assertEq(removableAt, 0, "cap should not be removable");

        console.log("Configured cap/queue for market:");
        console.logBytes32(marketId);
    }

    function _parse(
        string memory json
    ) internal pure returns (CapsConfig memory cfg) {
        cfg.vaultAddressName = json.readString(".vaultAddressName");
        cfg.loanTokenName = json.readString(".loanTokenName");
        cfg.collateralTokenName = json.readString(".collateralTokenName");
        cfg.irmName = json.readString(".irmName");
        cfg.lltv = json.readUint(".lltv");
        cfg.supplyCap = json.readUint(".supplyCap");
        if (json.parseRaw(".setSupplyQueue").length != 0) {
            cfg.setSupplyQueue = json.readBool(".setSupplyQueue");
        }
        // oracle nested
        cfg.oracle.addressName = json.readString(".oracle.addressName");
    }

    function _computeMarketId(
        MarketParams memory params
    ) internal pure returns (bytes32 marketParamsId) {
        assembly ("memory-safe") {
            marketParamsId := keccak256(params, MARKET_PARAMS_BYTES_LENGTH)
        }
    }
}

/// @notice Follow-up script to deposit to vault, supply collateral and borrow on a market
contract MorphoSupplyBorrow is Script, Test {
    using ChainIds for uint256;
    using stdJson for string;

    struct SBConfig {
        string vaultAddressName;
        string loanTokenName;
        string collateralTokenName;
        string irmName;
        uint256 lltv;
        uint256 vaultDepositAssets;
        uint256 collateralAmount;
        uint256 borrowAssets;
        CreateMorphoMarket.OracleConfig oracle;
    }

    uint256 internal constant MARKET_PARAMS_BYTES_LENGTH = 5 * 32;

    function run() external {
        BASE_FORK_ID.createForksAndSelect();

        string memory json = vm.readFile(vm.envString("NEW_MARKET_PATH"));
        SBConfig memory cfg = _parse(json);

        Addresses addresses = new Addresses();

        // Enforcing an immediate borrow and deposit: https://docs.morpho.org/curate/tutorials-market-v1/creating-market/#fill-all-attributes
        assertGt(
            cfg.vaultDepositAssets,
            0,
            "config.vaultDepositAssets must be greater than 0"
        );
        assertGt(
            cfg.collateralAmount,
            0,
            "config.collateralAmount must be greater than 0"
        );
        assertGt(
            cfg.borrowAssets,
            0,
            "config.borrowAssets must be greater than 0"
        );

        MarketParams memory market = MarketParams({
            loanToken: addresses.getAddress(cfg.loanTokenName),
            collateralToken: addresses.getAddress(cfg.collateralTokenName),
            oracle: addresses.getAddress(cfg.oracle.addressName),
            irm: addresses.getAddress(cfg.irmName),
            lltv: cfg.lltv
        });

        address morphoBlue = addresses.getAddress("MORPHO_BLUE");
        IMetaMorpho vault = IMetaMorpho(
            addresses.getAddress(cfg.vaultAddressName)
        );

        // Scale human-readable amounts by oracle decimals
        uint256 depositAmount = cfg.vaultDepositAssets;
        uint256 supplyAmount = cfg.collateralAmount;
        uint256 borrowAmount = cfg.borrowAssets;
        vm.startBroadcast();

        IERC20(market.loanToken).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, msg.sender);

        IERC20(market.collateralToken).approve(morphoBlue, supplyAmount);
        IMorphoBlue(morphoBlue).supplyCollateral(
            market,
            supplyAmount,
            msg.sender,
            ""
        );

        (uint256 assetsBorrowed, uint256 sharesBorrowed) = IMorphoBlue(
            morphoBlue
        ).borrow(market, borrowAmount, 0, msg.sender, msg.sender);
        vm.stopBroadcast();

        console.log("Borrowed:", assetsBorrowed);
        console.log("Borrow shares:", sharesBorrowed);
        console.log(
            "Loan token balance:",
            IERC20(market.loanToken).balanceOf(msg.sender)
        );
        console.log(
            "Collateral token balance:",
            IERC20(market.collateralToken).balanceOf(msg.sender)
        );
    }

    function _parse(
        string memory json
    ) internal pure returns (SBConfig memory cfg) {
        cfg.vaultAddressName = json.readString(".vaultAddressName");
        cfg.loanTokenName = json.readString(".loanTokenName");
        cfg.collateralTokenName = json.readString(".collateralTokenName");
        cfg.irmName = json.readString(".irmName");
        cfg.lltv = json.readUint(".lltv");
        cfg.vaultDepositAssets = json.readUint(".vaultDepositAssets");
        cfg.collateralAmount = json.readUint(".collateralAmount");
        cfg.borrowAssets = json.readUint(".borrowAssets");
        // oracle nested
        cfg.oracle.addressName = json.readString(".oracle.addressName");
        cfg.oracle.baseFeedDecimals = uint8(
            json.readUint(".oracle.baseFeedDecimals")
        );
        cfg.oracle.quoteFeedDecimals = uint8(
            json.readUint(".oracle.quoteFeedDecimals")
        );
    }
}
