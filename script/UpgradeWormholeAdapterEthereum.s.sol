// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {ETHEREUM_CHAIN_ID} from "@utils/ChainIds.sol";

/*

 Upgrade WormholeBridgeAdapter on Ethereum mainnet to V3 (direct VAA verification) and set new pause guardian

 to simulate:
     forge script script/UpgradeWormholeAdapterEthereum.s.sol:UpgradeWormholeAdapterEthereum -vvvv --rpc-url ethereum

 to run:
    forge script script/UpgradeWormholeAdapterEthereum.s.sol:UpgradeWormholeAdapterEthereum -vvvv \
    --rpc-url ethereum --broadcast --etherscan-api-key ethereum --verify

*/
contract UpgradeWormholeAdapterEthereum is Script {
    function run() public {
        Addresses addresses = new Addresses();

        require(
            block.chainid == ETHEREUM_CHAIN_ID,
            "This script must be run on Ethereum mainnet"
        );

        ProxyAdmin proxyAdmin = ProxyAdmin(addresses.getAddress("PROXY_ADMIN"));

        address wormholeAdapterProxy = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );

        vm.startBroadcast();

        // Deploy new WormholeBridgeAdapter implementation
        address newImpl = address(new WormholeBridgeAdapter());

        // Upgrade proxy with initializeV3
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(wormholeAdapterProxy),
            newImpl,
            abi.encodeWithSignature(
                "initializeV3(address)",
                addresses.getAddress("WORMHOLE_CORE")
            )
        );

        // Update xWELL pause guardian
        xWELL xwellProxy = xWELL(addresses.getAddress("xWELL_PROXY"));
        xwellProxy.grantPauseGuardian(addresses.getAddress("PAUSE_GUARDIAN"));

        vm.stopBroadcast();

        // Add new logic address to new implementation
        addresses.addAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V2", newImpl);

        addresses.printAddresses();

        // Run validation
        _validateDeployment(addresses, proxyAdmin);
    }

    function _validateDeployment(
        Addresses addresses,
        ProxyAdmin proxyAdmin
    ) internal {
        address wormholeAdapterProxy = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );
        address newImpl = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_IMPL_V2"
        );
        address wormholeCore = addresses.getAddress("WORMHOLE_CORE");

        console.log("\n=== Running Validation ===");

        // 1. Verify proxy implementation updated
        validateProxy(
            vm,
            wormholeAdapterProxy,
            newImpl,
            address(proxyAdmin),
            "Ethereum WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );
        console.log(
            "WormholeBridgeAdapter implementation updated to:",
            newImpl
        );

        // 2. Verify wormhole() returns WORMHOLE_CORE
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
            wormholeAdapterProxy
        );
        require(
            address(adapter.wormhole()) == wormholeCore,
            "Ethereum: wormhole core not set correctly"
        );
        console.log("wormhole() set to:", wormholeCore);

        // 3. Verify gasLimit is 300_000
        require(
            adapter.gasLimit() == 300_000,
            "Ethereum: gasLimit changed after upgrade"
        );
        console.log("gasLimit preserved: 300000");

        // 4. Verify initializeV3 cannot be called again (reinitializer guard)
        try adapter.initializeV3(address(1)) {
            revert("Ethereum: initializeV3 should have reverted");
        } catch {}

        // 5. Verify xWELL pause guardian updated
        xWELL xwellProxy = xWELL(addresses.getAddress("xWELL_PROXY"));
        address expectedGuardian = addresses.getAddress("PAUSE_GUARDIAN");
        require(
            xwellProxy.pauseGuardian() == expectedGuardian,
            "Ethereum: xWELL pause guardian not updated correctly"
        );
        console.log("xWELL pause guardian updated to:", expectedGuardian);

        console.log("=== Validation Passed ===\n");
    }
}
