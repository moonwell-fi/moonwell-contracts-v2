// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MoonwellViewsV1Moonbeam} from "@protocol/views/MoonwellViewsV1Moonbeam.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/*
Upgrades the Moonbeam views implementation behind MOONWELL_VIEWS_PROXY.

Fixes getUserStakingVotingPower, which queried stkWELL.getPriorVotes with
block.number while stkWELL snapshots (ERC20WithSnapshot) are keyed by
block.timestamp — making delegatedVotingPower always return 0.

Deploys MoonwellViewsV1Moonbeam (not MoonwellViewsV1) because the Moonbeam
proxy was initialized against the original Sep-2023 storage layout. A later
refactor in commit 04c5bc48 reordered state variables in BaseMoonwellViews,
which would shift `safetyModule` to the slot holding the WELL token if the
post-reorder implementation were deployed against this proxy (causing
getUserStakingInfo to revert with "unrecognized function selector"). The
Moonbeam-specific base preserves the legacy slot order.

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

        MoonwellViewsV1Moonbeam viewsContract = new MoonwellViewsV1Moonbeam();

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
            "new MoonwellViewsV1Moonbeam implementation:",
            address(viewsContract)
        );
    }
}
