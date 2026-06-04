// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MoonwellStakingViews} from "@protocol/views/MoonwellStakingViews.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/*
Deploys a fresh MoonwellStakingViews proxy on Ethereum mainnet.

The standard `BaseMoonwellViews` cannot be deployed on Ethereum: its
initializer asserts `comptroller.isComptroller()`, but Ethereum has no
Moonwell Comptroller — only xWELL and stkWELL live there. This script
deploys the decoupled staking-only views contract behind a fresh
TransparentUpgradeableProxy, initialized with the live stkWELL
(STK_GOVTOKEN_PROXY) address.

Outputs the three addresses that need to be registered in chains/1.json
post-execution:
  - STAKING_VIEWS_IMPLEMENTATION
  - STAKING_VIEWS_PROXY_ADMIN
  - STAKING_VIEWS_PROXY

Address registration must happen AFTER on-chain execution (per project
rule) because `_checkAddress` validates `code.length > 0`.

to run:
forge script script/DeployMoonwellStakingViewsEthereum.s.sol:DeployMoonwellStakingViewsEthereum \
    -vvvv --rpc-url ethereum --broadcast
*/

contract DeployMoonwellStakingViewsEthereum is Script, Test {
    Addresses public addresses;

    function setUp() public {
        addresses = new Addresses();
    }

    function run() public {
        address safetyModule = addresses.getAddress(
            "STK_GOVTOKEN_PROXY",
            block.chainid
        );

        vm.startBroadcast();

        MoonwellStakingViews impl = new MoonwellStakingViews();

        bytes memory initdata = abi.encodeWithSelector(
            MoonwellStakingViews.initialize.selector,
            safetyModule
        );

        ProxyAdmin proxyAdmin = new ProxyAdmin();

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(proxyAdmin),
            initdata
        );

        vm.stopBroadcast();

        console.log("MoonwellStakingViews impl:        ", address(impl));
        console.log("MoonwellStakingViews proxy admin: ", address(proxyAdmin));
        console.log("MoonwellStakingViews proxy:       ", address(proxy));
        console.log("safetyModule wired in:            ", safetyModule);
    }
}
