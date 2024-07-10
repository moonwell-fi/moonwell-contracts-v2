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
import {MoonwellViewsV3} from "@protocol/views/MoonwellViewsV3.sol";

import {console} from "@forge-std/console.sol";
/*
to run:
forge script script/DeployMoonwellViewsV3.s.sol:DeployMoonwellViewsV3 -vvvv --rpc-url {rpc}  --broadcast --etherscan-api-key {key}
forge script script/DeployMoonwellViewsV3.s.sol:DeployMoonwellViewsV3 -vvvv --rpc-url https://sepolia.base.org --broadcast

*/

contract DeployMoonwellViewsV3 is Script, Test {
    Addresses public addresses;

    function setUp() public {
        addresses = new Addresses();
    }

    function run() public {
        vm.startBroadcast();

        address unitroller = addresses.getAddress("UNITROLLER");
        address tokenSaleDistributor = address(0);
        address safetyModule = address(0);
        address governanceToken = addresses.getAddress("xWELL_PROXY");
        address nativeMarket = address(0);
        address governanceTokenLP = address(0);

        MoonwellViewsV3 viewsContract = new MoonwellViewsV3();

        bytes memory initdata = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address)",
            unitroller,
            tokenSaleDistributor,
            safetyModule,
            governanceToken,
            nativeMarket,
            governanceTokenLP
        );

        ProxyAdmin proxyAdmin = new ProxyAdmin();

        new TransparentUpgradeableProxy(address(viewsContract), address(proxyAdmin), initdata);

        vm.stopBroadcast();
    }
}
