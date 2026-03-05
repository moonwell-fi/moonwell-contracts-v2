// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MoonwellViewsV1Moonriver} from "@protocol/views/MoonwellViewsV1Moonriver.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/*
to run:
forge script script/DeployMoonwellViewsV1Moonriver.s.sol:DeployMoonwellViewsV1Moonriver -vvvv --rpc-url moonriver --broadcast
*/

contract DeployMoonwellViewsV1Moonriver is Script, Test {
    Addresses public addresses;

    function setUp() public {
        addresses = new Addresses();
    }

    /// @notice Core deployment logic, reusable from tests
    /// @param _addresses the address registry to read config from
    /// @return views the fully configured MoonwellViewsV1Moonriver behind a proxy
    function deploy(
        Addresses _addresses
    ) public returns (MoonwellViewsV1Moonriver views) {
        // 1. Deploy implementation
        MoonwellViewsV1Moonriver viewsImpl = new MoonwellViewsV1Moonriver();

        // 2. Build init params
        MoonwellViewsV1Moonriver.InitParams memory params;
        params.comptroller = _addresses.getAddress("UNITROLLER");
        params.safetyModule = _addresses.getAddress("STK_GOVTOKEN_PROXY");
        params.governanceToken = _addresses.getAddress("GOVTOKEN");
        params.nativeMarket = _addresses.getAddress("MNATIVE");
        params.governanceTokenLP = _addresses.getAddress("GOVTOKEN_LP");
        params.nativeWrapped = _addresses.getAddress("WMOVR");
        params.stableToken = _addresses.getAddress("USDC");
        params.stableDecimals = 6;

        params.tokens = new address[](3);
        params.pairs = new address[](3);

        params.tokens[0] = _addresses.getAddress("WMOVR");
        params.pairs[0] = _addresses.getAddress("WMOVR_USDC_PAIR");

        params.tokens[1] = _addresses.getAddress("xcKSM");
        params.pairs[1] = _addresses.getAddress("xcKSM_WMOVR_PAIR");

        params.tokens[2] = _addresses.getAddress("FRAX");
        params.pairs[2] = _addresses.getAddress("FRAX_WMOVR_PAIR");

        // 3. Deploy proxy — single initialize sets protocol + DEX config
        ProxyAdmin proxyAdmin = new ProxyAdmin();

        bytes memory initdata = abi.encodeWithSelector(
            MoonwellViewsV1Moonriver.initialize.selector,
            params
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(viewsImpl),
            address(proxyAdmin),
            initdata
        );

        views = MoonwellViewsV1Moonriver(address(proxy));

        // 4. Validate deployment with view calls
        views.getProtocolInfo();
        views.getNativeTokenPrice();
        views.getGovernanceTokenPrice();

        // 5. Register deployed addresses
        _setAddress(
            _addresses,
            "MOONWELL_VIEWS_IMPLEMENTATION",
            address(viewsImpl)
        );
        _setAddress(
            _addresses,
            "MOONWELL_VIEWS_PROXY_ADMIN",
            address(proxyAdmin)
        );
        _setAddress(_addresses, "MOONWELL_VIEWS_PROXY", address(proxy));
    }

    /// @notice Add or update an address in the registry
    function _setAddress(
        Addresses _addresses,
        string memory name,
        address addr
    ) internal {
        if (_addresses.isAddressSet(name)) {
            _addresses.changeAddress(name, addr, true);
        } else {
            _addresses.addAddress(name, addr);
        }
    }

    function run() public {
        vm.startBroadcast();

        deploy(addresses);

        vm.stopBroadcast();

        addresses.printAddresses();
    }
}
