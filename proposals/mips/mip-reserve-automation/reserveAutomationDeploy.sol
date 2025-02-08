// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {Script} from "@forge-std/Script.sol";
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
contract ReserveAutomationDeploy is Script, Test {
    using ChainIds for uint256;

    /// @notice the name of the proposal
    string public constant NAME = "Reserve Automation Deployment";

    AutomationDeploy private _deployer;
    Addresses internal _addresses;

    function setUp() public virtual {
        _addresses = new Addresses();
    }

    /// @notice array of mToken names to deploy automation for
    function _getMTokens(
        uint256 chainId
    ) internal view returns (string[] memory) {
        string memory file = vm.readFile(
            string.concat(
                "./proposals/mips/mip-reserve-automation/",
                string.concat(vm.toString(chainId), ".json")
            )
        );
        string[] memory mTokens = abi.decode(vm.parseJson(file), (string[]));
        return mTokens;
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

        ChainlinkOracle oracle = ChainlinkOracle(
            addresses.getAddress("CHAINLINK_ORACLE")
        );

        /// Deploy ReserveAutomation for each mToken
        string[] memory mTokens = _getMTokens(block.chainid);
        for (uint256 i = 0; i < mTokens.length; i++) {
            string memory mTokenName = mTokens[i];
            address mTokenAddress = addresses.getAddress(mTokenName);
            ERC20 underlyingToken = ERC20(MErc20(mTokenAddress).underlying());

            string memory reserveAutomationIdentifier = string.concat(
                "RESERVE_AUTOMATION_",
                _stripMoonwellPrefix(mTokenName)
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
                        reserveChainlinkFeed: address(
                            oracle.getFeed(underlyingToken.symbol())
                        ),
                        owner: temporalGov,
                        mTokenMarket: addresses.getAddress(mTokenName),
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

        ChainlinkOracle oracle = ChainlinkOracle(
            addresses.getAddress("CHAINLINK_ORACLE")
        );

        /// Validate ReserveAutomation for each mToken
        string[] memory mTokens = _getMTokens(block.chainid);
        for (uint256 i = 0; i < mTokens.length; i++) {
            string memory mTokenName = mTokens[i];

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
                reserve.wellChainlinkFeed(),
                addresses.getAddress("CHAINLINK_WELL_USD"),
                string.concat("incorrect well chainlink feed for ", mTokenName)
            );
            assertEq(
                reserve.mTokenMarket(),
                addresses.getAddress(mTokenName),
                string.concat("incorrect mToken market for ", mTokenName)
            );

            ERC20 underlyingToken = ERC20(
                MErc20(addresses.getAddress(mTokenName)).underlying()
            );

            assertEq(
                reserve.reserveAsset(),
                address(underlyingToken),
                string.concat("incorrect reserve asset for ", mTokenName)
            );
            assertEq(
                reserve.reserveChainlinkFeed(),
                address(oracle.getFeed(underlyingToken.symbol())),
                string.concat(
                    "incorrect reserve chainlink feed for ",
                    mTokenName
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
