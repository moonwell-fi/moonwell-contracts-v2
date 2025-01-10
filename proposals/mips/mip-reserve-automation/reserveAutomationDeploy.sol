// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {Script} from "@forge-std/Script.sol";
import {Test} from "@forge-std/Test.sol";
import {console} from "@forge-std/console.sol";

import "@protocol/utils/ChainIds.sol";

import {ReserveAutomation} from "@protocol/market/ReserveAutomation.sol";
import {ERC20HoldingDeposit} from "@protocol/market/ERC20HoldingDeposit.sol";
import {AutomationDeploy} from "@protocol/market/AutomationDeploy.sol";
import {ChainIds, BASE_FORK_ID} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// how to run locally:
///       forge script proposals/mips/mip-reserve-automation/reserveAutomationDeploy.sol:ReserveAutomationDeploy --rpc-url base
contract ReserveAutomationDeploy is Script, Test {
    using ChainIds for uint256;

    /// @notice the name of the proposal
    string public constant NAME = "Reserve Automation Deployment";

    /// @notice the maximum discount allowed for reserve sales (10%)
    uint256 public constant MAX_DISCOUNT = 1e17;

    /// @notice the period over which the discount is applied (1 week)
    uint256 public constant DISCOUNT_APPLICATION_PERIOD = 4 hours;

    /// @notice the period before discount starts applying (1 day)
    uint256 public constant NON_DISCOUNT_PERIOD = 4 hours;

    AutomationDeploy private _deployer;
    Addresses public addresses;

    function setUp() public {
        addresses = new Addresses();
    }

    /// @notice array of mToken names to deploy automation for
    function _getMTokens() internal pure returns (string[] memory) {
        string[] memory tokens = new string[](12);
        tokens[0] = "MOONWELL_USDC";
        tokens[1] = "MOONWELL_USDBC";
        tokens[2] = "MOONWELL_DAI";
        tokens[3] = "MOONWELL_WETH";
        tokens[4] = "MOONWELL_cbETH";
        tokens[5] = "MOONWELL_wstETH";
        tokens[6] = "MOONWELL_rETH";
        tokens[7] = "MOONWELL_AERO";
        tokens[8] = "MOONWELL_weETH";
        tokens[9] = "MOONWELL_cbBTC";
        tokens[10] = "MOONWELL_EURC";
        tokens[11] = "MOONWELL_wrsETH";
        return tokens;
    }

    function run() public {
        // Deploy contracts

        address temporalGov = addresses.getAddress("TEMPORAL_GOVERNOR");
        address pauseGuardian = addresses.getAddress("PAUSE_GUARDIAN");
        address xWellProxy = addresses.getAddress("xWELL_PROXY");

        vm.startBroadcast();

        _deployer = new AutomationDeploy();

        /// Deploy ERC20HoldingDeposit for xWELL
        address holdingDeposit = _deployer.deployERC20HoldingDeposit(
            xWellProxy,
            temporalGov
        );

        addresses.addAddress("RESERVE_WELL_HOLDING_DEPOSIT", holdingDeposit);

        /// Deploy ReserveAutomation for each mToken
        string[] memory mTokens = _getMTokens();
        for (uint256 i = 0; i < mTokens.length; i++) {
            string memory mTokenName = mTokens[i];
            string memory underlyingName = _getUnderlyingName(mTokenName);
            string memory oracleName = _getOracleName(underlyingName);

            ReserveAutomation.InitParams memory params = ReserveAutomation
                .InitParams(
                    MAX_DISCOUNT,
                    DISCOUNT_APPLICATION_PERIOD,
                    NON_DISCOUNT_PERIOD,
                    holdingDeposit,
                    xWellProxy,
                    addresses.getAddress(underlyingName),
                    addresses.getAddress("CHAINLINK_WELL_USD"),
                    addresses.getAddress(oracleName),
                    temporalGov,
                    addresses.getAddress(mTokenName),
                    pauseGuardian
                );

            address automation = _deployer.deployReserveAutomation(params);

            addresses.addAddress(
                string.concat(
                    "RESERVE_AUTOMATION_",
                    _stripMoonwellPrefix(mTokenName)
                ),
                automation
            );
        }

        vm.stopBroadcast();

        addresses.printAddresses();
        addresses.resetRecordingAddresses();

        _validate();
    }

    function _validate() internal view {
        address temporalGov = addresses.getAddress("TEMPORAL_GOVERNOR");
        address pauseGuardian = addresses.getAddress("PAUSE_GUARDIAN");
        address xWellProxy = addresses.getAddress("xWELL_PROXY");
        address holdingDeposit = addresses.getAddress(
            "RESERVE_WELL_HOLDING_DEPOSIT"
        );

        /// Validate ERC20HoldingDeposit
        assertEq(
            ERC20HoldingDeposit(holdingDeposit).token(),
            xWellProxy,
            "incorrect holding deposit token"
        );
        assertEq(
            ERC20HoldingDeposit(holdingDeposit).owner(),
            temporalGov,
            "incorrect holding deposit owner"
        );

        /// Validate ReserveAutomation for each mToken
        string[] memory mTokens = _getMTokens();
        for (uint256 i = 0; i < mTokens.length; i++) {
            string memory mTokenName = mTokens[i];
            string memory underlyingName = _getUnderlyingName(mTokenName);
            string memory oracleName = _getOracleName(underlyingName);

            address automation = addresses.getAddress(
                string.concat(
                    "RESERVE_AUTOMATION_",
                    _stripMoonwellPrefix(mTokenName)
                )
            );

            ReserveAutomation reserve = ReserveAutomation(automation);

            assertEq(
                reserve.owner(),
                temporalGov,
                string.concat("incorrect owner for ", mTokenName)
            );
            assertEq(
                reserve.guardian(),
                pauseGuardian,
                string.concat("incorrect guardian for ", mTokenName)
            );
            assertEq(
                reserve.maxDiscount(),
                MAX_DISCOUNT,
                string.concat("incorrect max discount for ", mTokenName)
            );
            assertEq(
                reserve.discountApplicationPeriod(),
                DISCOUNT_APPLICATION_PERIOD,
                string.concat(
                    "incorrect discount application period for ",
                    mTokenName
                )
            );
            assertEq(
                reserve.nonDiscountPeriod(),
                NON_DISCOUNT_PERIOD,
                string.concat("incorrect non discount period for ", mTokenName)
            );
            assertEq(
                reserve.recipientAddress(),
                holdingDeposit,
                string.concat("incorrect recipient address for ", mTokenName)
            );
            assertEq(
                reserve.wellToken(),
                xWellProxy,
                string.concat("incorrect well token for ", mTokenName)
            );
            assertEq(
                reserve.reserveAsset(),
                addresses.getAddress(underlyingName),
                string.concat("incorrect reserve asset for ", mTokenName)
            );
            assertEq(
                reserve.wellChainlinkFeed(),
                addresses.getAddress("CHAINLINK_WELL_USD"),
                string.concat("incorrect well chainlink feed for ", mTokenName)
            );
            assertEq(
                reserve.reserveChainlinkFeed(),
                addresses.getAddress(oracleName),
                string.concat(
                    "incorrect reserve chainlink feed for ",
                    mTokenName
                )
            );
            assertEq(
                reserve.mTokenMarket(),
                addresses.getAddress(mTokenName),
                string.concat("incorrect mToken market for ", mTokenName)
            );
        }
    }

    /// @notice Helper function to get the underlying token name from an mToken name
    /// @param mTokenName The name of the mToken
    /// @return The name of the underlying token
    function _getUnderlyingName(
        string memory mTokenName
    ) internal pure returns (string memory) {
        string memory token = _stripMoonwellPrefix(mTokenName);
        if (keccak256(bytes(token)) == keccak256(bytes("USDBC"))) {
            return "USDBC";
        } else if (keccak256(bytes(token)) == keccak256(bytes("USDC"))) {
            return "USDC";
        } else if (keccak256(bytes(token)) == keccak256(bytes("DAI"))) {
            return "DAI";
        } else if (keccak256(bytes(token)) == keccak256(bytes("WETH"))) {
            return "WETH";
        } else if (keccak256(bytes(token)) == keccak256(bytes("cbETH"))) {
            return "cbETH";
        } else if (keccak256(bytes(token)) == keccak256(bytes("wstETH"))) {
            return "wstETH";
        } else if (keccak256(bytes(token)) == keccak256(bytes("rETH"))) {
            return "rETH";
        } else if (keccak256(bytes(token)) == keccak256(bytes("AERO"))) {
            return "AERO";
        } else if (keccak256(bytes(token)) == keccak256(bytes("weETH"))) {
            return "weETH";
        } else if (keccak256(bytes(token)) == keccak256(bytes("cbBTC"))) {
            return "cbBTC";
        } else if (keccak256(bytes(token)) == keccak256(bytes("EURC"))) {
            return "EURC";
        } else if (keccak256(bytes(token)) == keccak256(bytes("wrsETH"))) {
            return "wrsETH";
        } else if (keccak256(bytes(token)) == keccak256(bytes("WELL"))) {
            return "xWELL_PROXY";
        } else {
            revert("unknown mToken");
        }
    }

    /// @notice Helper function to get the oracle name for a token
    /// @param tokenName The name of the token
    /// @return The name of the oracle for the token
    function _getOracleName(
        string memory tokenName
    ) internal pure returns (string memory) {
        if (keccak256(bytes(tokenName)) == keccak256(bytes("USDBC"))) {
            return "USDC_ORACLE";
        } else if (keccak256(bytes(tokenName)) == keccak256(bytes("USDC"))) {
            return "USDC_ORACLE";
        } else if (keccak256(bytes(tokenName)) == keccak256(bytes("DAI"))) {
            return "DAI_ORACLE";
        } else if (keccak256(bytes(tokenName)) == keccak256(bytes("WETH"))) {
            return "CHAINLINK_ETH_USD";
        } else if (keccak256(bytes(tokenName)) == keccak256(bytes("cbETH"))) {
            return "cbETH_ORACLE";
        } else if (keccak256(bytes(tokenName)) == keccak256(bytes("wstETH"))) {
            return "CHAINLINK_WSTETH_STETH_COMPOSITE_ORACLE";
        } else if (keccak256(bytes(tokenName)) == keccak256(bytes("rETH"))) {
            return "CHAINLINK_RETH_ETH_COMPOSITE_ORACLE";
        } else if (keccak256(bytes(tokenName)) == keccak256(bytes("AERO"))) {
            return "CHAINLINK_AERO_ORACLE";
        } else if (keccak256(bytes(tokenName)) == keccak256(bytes("weETH"))) {
            return "CHAINLINK_WEETH_ETH_COMPOSITE_ORACLE";
        } else if (keccak256(bytes(tokenName)) == keccak256(bytes("cbBTC"))) {
            return "CHAINLINK_BTC_USD";
        } else if (keccak256(bytes(tokenName)) == keccak256(bytes("EURC"))) {
            return "CHAINLINK_EURC_USD";
        } else if (keccak256(bytes(tokenName)) == keccak256(bytes("wrsETH"))) {
            return "CHAINLINK_wrsETH_COMPOSITE_ORACLE";
        } else if (
            keccak256(bytes(tokenName)) == keccak256(bytes("xWELL_PROXY"))
        ) {
            return "CHAINLINK_WELL_USD";
        } else {
            revert("unknown token");
        }
    }

    /// @notice Helper function to strip the MOONWELL_ prefix from a token name
    /// @param mTokenName The name of the mToken
    /// @return The token name without the MOONWELL_ prefix
    function _stripMoonwellPrefix(
        string memory mTokenName
    ) internal pure returns (string memory) {
        bytes memory mTokenBytes = bytes(mTokenName);
        bytes memory prefix = bytes("MOONWELL_");
        require(mTokenBytes.length > prefix.length, "invalid mToken name");

        bytes memory result = new bytes(mTokenBytes.length - prefix.length);
        for (uint256 i = prefix.length; i < mTokenBytes.length; i++) {
            result[i - prefix.length] = mTokenBytes[i];
        }

        return string(result);
    }
}
