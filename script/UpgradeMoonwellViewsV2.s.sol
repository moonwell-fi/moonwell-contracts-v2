// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@forge-std/Test.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MoonwellViewsV2} from "@protocol/views/MoonwellViewsV2.sol";

/*
to run:
forge script script/UpgradeMoonwellViewsV2.s.sol:UpgradeMoonwellViewsV2 -vvvv --rpc-url {rpc}  --broadcast --etherscan-api-key {key}
*/

contract UpgradeMoonwellViewsV2 is Script, Test {
    Addresses public addresses;

    function setUp() public {
        addresses = new Addresses();
    }

    function run() public {
        vm.startBroadcast();

        MoonwellViewsV2 viewsContract = new MoonwellViewsV2();

        ProxyAdmin proxyAdmin = ProxyAdmin(addresses.getAddress("MOONWELL_VIEWS_PROXY_ADMIN"));

        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(addresses.getAddress("MOONWELL_VIEWS_PROXY")), address(viewsContract)
        );

        vm.stopBroadcast();
    }
}
