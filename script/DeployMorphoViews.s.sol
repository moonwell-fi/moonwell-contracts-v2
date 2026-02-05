// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";
import {Test} from "@forge-std/Test.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MorphoViews} from "@protocol/views/MorphoViews.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/*
to run:
forge script script/DeployMorphoViews.s.sol:DeployMorphoViews -vvvv --rpc-url {rpc} --broadcast --etherscan-api-key {key}

Example for Base mainnet:
forge script script/DeployMorphoViews.s.sol:DeployMorphoViews -vvvv --rpc-url https://mainnet.base.org --broadcast --verify --etherscan-api-key {BASESCAN_API_KEY}

*/

contract DeployMorphoViews is Script, Test {
    Addresses public addresses;

    function setUp() public {
        addresses = new Addresses();
    }

    function run() public {
        vm.startBroadcast();

        address unitroller = addresses.getAddress("UNITROLLER");
        address morpho = addresses.getAddress("MORPHO_BLUE");

        MorphoViews viewsContract = new MorphoViews();

        bytes memory initdata = abi.encodeWithSignature(
            "initialize(address,address)",
            unitroller,
            morpho
        );

        ProxyAdmin proxyAdmin = new ProxyAdmin();

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(viewsContract),
            address(proxyAdmin),
            initdata
        );

        console.log("MorphoViews Implementation:", address(viewsContract));
        console.log("MorphoViews Proxy:", address(proxy));
        console.log("ProxyAdmin:", address(proxyAdmin));

        vm.stopBroadcast();
    }
}
