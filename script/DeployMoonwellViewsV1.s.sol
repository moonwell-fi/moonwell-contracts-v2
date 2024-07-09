// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@forge-std/Test.sol";

import {ProxyAdmin} from
    "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MoonwellViewsV1} from "@protocol/views/MoonwellViewsV1.sol";

/*
to run:
forge script script/DeployMoonwellViewsV1.s.sol:DeployMoonwellViewsV1 -vvvv --rpc-url {rpc}  --broadcast --etherscan-api-key {key}
*/

contract DeployMoonwellViewsV1 is Script, Test {
    Addresses public addresses;

    function setUp() public {
        addresses = new Addresses();
    }

    function run() public {
        vm.startBroadcast();

        address unitroller = addresses.getAddress("UNITROLLER");
        address tokenSaleDistributor = addresses.getAddress("TOKENSALE");
        address safetyModule = addresses.getAddress("STKGOVTOKEN");
        address governanceToken = addresses.getAddress("GOVTOKEN");
        address nativeMarket = addresses.getAddress("MNATIVE");
        address governanceTokenLP = addresses.getAddress("GOVTOKEN_LP");

        MoonwellViewsV1 viewsContract = new MoonwellViewsV1();

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

        new TransparentUpgradeableProxy(
            address(viewsContract), address(proxyAdmin), initdata
        );

        vm.stopBroadcast();
    }
}
