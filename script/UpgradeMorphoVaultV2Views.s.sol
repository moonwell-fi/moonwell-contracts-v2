// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";
import {Test} from "@forge-std/Test.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MorphoVaultV2Views} from "@protocol/views/MorphoVaultV2Views.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/*
To run (dry run):
forge script script/UpgradeMorphoVaultV2Views.s.sol:UpgradeMorphoVaultV2Views -vvvv --rpc-url base

To run (broadcast):
forge script script/UpgradeMorphoVaultV2Views.s.sol:UpgradeMorphoVaultV2Views -vvvv --rpc-url base --broadcast --verify --etherscan-api-key {BASESCAN_API_KEY}
*/

contract UpgradeMorphoVaultV2Views is Script, Test {
    Addresses public addresses;

    function setUp() public {
        addresses = new Addresses();
    }

    function run() public {
        vm.startBroadcast();

        // Deploy new implementation
        MorphoVaultV2Views viewsContract = new MorphoVaultV2Views();

        console.log(
            "New MorphoVaultV2Views Implementation:",
            address(viewsContract)
        );

        // Get the ProxyAdmin (shared with MoonwellViews)
        ProxyAdmin proxyAdmin = ProxyAdmin(
            addresses.getAddress("MOONWELL_VIEWS_PROXY_ADMIN")
        );

        console.log("ProxyAdmin:", address(proxyAdmin));

        // Get the proxy address
        address proxyAddress = addresses.getAddress(
            "MORPHO_VAULT_V2_VIEWS_PROXY"
        );
        console.log("MorphoVaultV2Views Proxy:", proxyAddress);

        // Upgrade the proxy to the new implementation
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(proxyAddress),
            address(viewsContract)
        );

        console.log("Upgrade complete!");

        vm.stopBroadcast();
    }
}
