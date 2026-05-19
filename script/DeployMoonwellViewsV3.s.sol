// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;
pragma experimental ABIEncoderV2;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MoonwellViewsV3} from "@protocol/views/MoonwellViewsV3.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/*
Standalone deployment for MoonwellViewsV3 (impl + dedicated ProxyAdmin +
TransparentUpgradeableProxy initialized in one shot). Skips if
MOONWELL_VIEWS_PROXY is already registered for the current chain in
chains/<chainId>.json.

How to use (Optimism):
forge script script/DeployMoonwellViewsV3.s.sol:DeployMoonwellViewsV3 \
    -vvvv \
    --rpc-url optimism --etherscan-api-key optimism \
    --verify --broadcast

How to use (Base):
forge script script/DeployMoonwellViewsV3.s.sol:DeployMoonwellViewsV3 \
    -vvvv \
    --rpc-url base --etherscan-api-key base \
    --verify --broadcast

Omit --broadcast for a dry run. After a successful broadcast, register the
emitted addresses in chains/<chainId>.json under MOONWELL_VIEWS_IMPLEMENTATION,
MOONWELL_VIEWS_PROXY_ADMIN, and MOONWELL_VIEWS_PROXY.
*/
contract DeployMoonwellViewsV3 is Script {
    Addresses public addresses;

    function setUp() public {
        addresses = new Addresses();
    }

    function run() public {
        if (addresses.isAddressSet("MOONWELL_VIEWS_PROXY", block.chainid)) {
            console.log(
                "MOONWELL_VIEWS_PROXY already deployed on chain %s at %s - skipping",
                block.chainid,
                addresses.getAddress("MOONWELL_VIEWS_PROXY")
            );
            return;
        }

        address unitroller = addresses.getAddress("UNITROLLER");
        address safetyModule = addresses.getAddress("stkWELL_PROXY");
        address governanceToken = addresses.getAddress("xWELL_PROXY");
        address tokenSaleDistributor = address(0);
        address nativeMarket = address(0);
        address governanceTokenLP = address(0);

        vm.startBroadcast();

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

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(viewsContract),
            address(proxyAdmin),
            initdata
        );

        vm.stopBroadcast();

        console.log("Deployed MoonwellViewsV3 on chain %s:", block.chainid);
        console.log("  MOONWELL_VIEWS_IMPLEMENTATION:", address(viewsContract));
        console.log("  MOONWELL_VIEWS_PROXY_ADMIN:   ", address(proxyAdmin));
        console.log("  MOONWELL_VIEWS_PROXY:         ", address(proxy));
        console.log(
            "  Register these in chains/%s.json after broadcast.",
            block.chainid
        );
    }
}
