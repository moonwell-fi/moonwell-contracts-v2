// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";
import {Test} from "@forge-std/Test.sol";

import {MorphoVaultV2Views} from "@protocol/views/MorphoVaultV2Views.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract DeployMorphoVaultV2Views is Script, Test {
    Addresses public addresses;

    function setUp() public {
        addresses = new Addresses();
    }
    function run() public {
        vm.startBroadcast();

        address unitroller = addresses.getAddress("UNITROLLER");
        address proxyAdmin = addresses.getAddress("MOONWELL_VIEWS_PROXY_ADMIN");

        // Deploy implementation
        MorphoVaultV2Views viewsImplementation = new MorphoVaultV2Views();
        console.log(
            "MorphoVaultV2Views Implementation deployed at:",
            address(viewsImplementation)
        );

        // Encode initialization data
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address)",
            unitroller
        );

        // Deploy proxy with existing ProxyAdmin
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(viewsImplementation),
            proxyAdmin,
            initData
        );
        console.log("MorphoVaultV2Views Proxy deployed at:", address(proxy));

        vm.stopBroadcast();
    }
}
