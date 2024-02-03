// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {MoonwellViewsV2} from "@protocol/views/MoonwellViewsV2.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/*
to run:
forge script script/UpgradeMoonwellViewsV2.s.sol:UpgradeMoonwellViewsV2 -vvvv --rpc-url {rpc}  --broadcast --etherscan-api-key {key}
*/

contract UpgradeMoonwellViewsV2 is Script, Test {
    uint256 public PRIVATE_KEY;

    Addresses public addresses;

    function setUp() public {
        addresses = new Addresses();

        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = vm.envOr(
            "MOONWELL_DEPLOY_PK",
            77814517325470205911140941194401928579557062014761831930645393041380819009408
        );
    }

    function run() public {
        vm.startBroadcast(PRIVATE_KEY);

        MoonwellViewsV2 viewsContract = new MoonwellViewsV2();

        ProxyAdmin proxyAdmin = ProxyAdmin(
            addresses.getAddress("MOONWELL_VIEWS_PROXY_ADMIN")
        );

        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(
                addresses.getAddress("MOONWELL_VIEWS_PROXY")
            ),
            address(viewsContract)
        );

        vm.stopBroadcast();
    }
}
