// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MoonwellViewsV1} from "@protocol/views/MoonwellViewsV1.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/*
Upgrades the Moonbeam MoonwellViewsV1 implementation behind MOONWELL_VIEWS_PROXY.
Fixes getUserStakingVotingPower, which queried stkWELL.getPriorVotes with
block.number while stkWELL snapshots (ERC20WithSnapshot) are keyed by
block.timestamp — making delegatedVotingPower always return 0.

Must be broadcast by the MOONWELL_VIEWS_PROXY_ADMIN owner (MOONWELL_DEPLOYER).

to run:
forge script script/UpgradeMoonwellViewsV1.s.sol:UpgradeMoonwellViewsV1 -vvvv --rpc-url moonbeam --broadcast
*/

contract UpgradeMoonwellViewsV1 is Script, Test {
    Addresses public addresses;

    function setUp() public {
        addresses = new Addresses();
    }

    function run() public {
        vm.startBroadcast();

        MoonwellViewsV1 viewsContract = new MoonwellViewsV1();

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

        console.log(
            "new MoonwellViewsV1 implementation:",
            address(viewsContract)
        );
    }
}
