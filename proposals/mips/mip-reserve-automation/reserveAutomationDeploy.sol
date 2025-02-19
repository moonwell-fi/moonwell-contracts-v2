// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {Script} from "@forge-std/Script.sol";
import {stdJson} from "@forge-std/StdJson.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Test} from "@forge-std/Test.sol";

import "@protocol/utils/ChainIds.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {AutomationDeploy} from "@protocol/market/AutomationDeploy.sol";
import {ReserveAutomation} from "@protocol/market/ReserveAutomation.sol";
import {ERC20HoldingDeposit} from "@protocol/market/ERC20HoldingDeposit.sol";
import {ChainIds, BASE_FORK_ID} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// how to run locally:
///       forge script proposals/mips/mip-reserve-automation/reserveAutomationDeploy.sol:ReserveAutomationDeploy --rpc-url base
struct MarketConfig {
    string chainlinkFeed;
    string market;
}

contract ReserveAutomationDeploy is Script, Test {
    using ChainIds for uint256;
    using stdJson for string;

    /// @notice the name of the proposal
    string public constant NAME = "Reserve Automation Deployment";

    AutomationDeploy private _deployer;
    Addresses internal _addresses;

    function setUp() public virtual {
        _addresses = new Addresses();
    }

    /// @notice array of market configs to deploy automation for
    function _getMTokens(
        uint256 chainId
    ) internal view returns (MarketConfig[] memory) {
        string memory file = vm.readFile(
            string.concat(
                "./proposals/mips/mip-reserve-automation/",
                string.concat(vm.toString(chainId), ".json")
            )
        );
        MarketConfig[] memory configs = abi.decode(
            vm.parseJson(file),
            (MarketConfig[])
        );
        return configs;
    }

    function run() public {
        vm.startBroadcast();

        deploy(_addresses);

        vm.stopBroadcast();

        _addresses.printAddresses();

        validate(_addresses);
    }

    function deploy(Addresses addresses) public {
        address temporalGov = addresses.getAddress("TEMPORAL_GOVERNOR");
        address pauseGuardian = addresses.getAddress("PAUSE_GUARDIAN");
        address xWellProxy = addresses.getAddress("xWELL_PROXY");

        _deployer = new AutomationDeploy();

        /// Deploy ERC20HoldingDeposit for xWELL
        address holdingDeposit;

        if (addresses.isAddressSet("RESERVE_WELL_HOLDING_DEPOSIT")) {
            holdingDeposit = addresses.getAddress(
                "RESERVE_WELL_HOLDING_DEPOSIT"
            );
        } else {
            holdingDeposit = _deployer.deployERC20HoldingDeposit(
                xWellProxy,
                temporalGov
            );
            addresses.addAddress(
                "RESERVE_WELL_HOLDING_DEPOSIT",
                holdingDeposit
            );
        }

        /// Deploy ReserveAutomation for each market config
        MarketConfig[] memory marketConfigs = _getMTokens(block.chainid);
        for (uint256 i = 0; i < marketConfigs.length; i++) {
            MarketConfig memory config = marketConfigs[i];
            address mTokenAddress = addresses.getAddress(config.market);
            ERC20 underlyingToken = ERC20(MErc20(mTokenAddress).underlying());

            string memory reserveAutomationIdentifier = string.concat(
                "RESERVE_AUTOMATION_",
                _stripMoonwellPrefix(config.market)
            );

            /// avoid redeploying a contract that already exists
            if (!addresses.isAddressSet(reserveAutomationIdentifier)) {
                ReserveAutomation.InitParams memory params = ReserveAutomation
                    .InitParams({
                        recipientAddress: holdingDeposit,
                        wellToken: xWellProxy,
                        reserveAsset: address(underlyingToken),
                        wellChainlinkFeed: addresses.getAddress(
                            "CHAINLINK_WELL_USD"
                        ),
                        reserveChainlinkFeed: addresses.getAddress(
                            config.chainlinkFeed
                        ),
                        owner: temporalGov,
                        mTokenMarket: addresses.getAddress(config.market),
                        guardian: pauseGuardian
                    });

                address automation = _deployer.deployReserveAutomation(params);

                addresses.addAddress(reserveAutomationIdentifier, automation);
            }
        }
    }

    function validate(Addresses addresses) public view {
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

        /// Validate ReserveAutomation for each market config
        MarketConfig[] memory marketConfigs = _getMTokens(block.chainid);
        for (uint256 i = 0; i < marketConfigs.length; i++) {
            MarketConfig memory config = marketConfigs[i];

            address automation = addresses.getAddress(
                string.concat(
                    "RESERVE_AUTOMATION_",
                    _stripMoonwellPrefix(config.market)
                )
            );

            ReserveAutomation reserve = ReserveAutomation(automation);

            assertEq(
                reserve.owner(),
                temporalGov,
                string.concat("incorrect owner for ", config.market)
            );
            assertEq(
                reserve.guardian(),
                pauseGuardian,
                string.concat("incorrect guardian for ", config.market)
            );
            assertEq(
                reserve.recipientAddress(),
                holdingDeposit,
                string.concat("incorrect recipient address for ", config.market)
            );
            assertEq(
                reserve.wellToken(),
                xWellProxy,
                string.concat("incorrect well token for ", config.market)
            );
            assertEq(
                reserve.wellChainlinkFeed(),
                addresses.getAddress("CHAINLINK_WELL_USD"),
                string.concat(
                    "incorrect well chainlink feed for ",
                    config.market
                )
            );
            assertEq(
                reserve.mTokenMarket(),
                addresses.getAddress(config.market),
                string.concat("incorrect mToken market for ", config.market)
            );

            ERC20 underlyingToken = ERC20(
                MErc20(addresses.getAddress(config.market)).underlying()
            );

            assertEq(
                reserve.reserveAsset(),
                address(underlyingToken),
                string.concat("incorrect reserve asset for ", config.market)
            );

            assertEq(
                reserve.reserveChainlinkFeed(),
                addresses.getAddress(config.chainlinkFeed),
                string.concat(
                    "incorrect reserve chainlink feed for ",
                    config.market
                )
            );
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
