// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {ETHEREUM_CHAIN_ID} from "@utils/ChainIds.sol";

/*

 Upgrade WormholeBridgeAdapter on Ethereum mainnet to V3 (direct VAA verification)

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
        address oldImpl = addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_LOGIC");

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

        vm.stopBroadcast();

        // Save old implementation as deprecated (outside broadcast — Addresses is local only)
        addresses.addAddress("WORMHOLE_BRIDGE_ADAPTER_LOGIC_V2", oldImpl);

        // Update logic address to new implementation
        addresses.changeAddress("WORMHOLE_BRIDGE_ADAPTER_LOGIC", newImpl, true);

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
        address newImpl = addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_LOGIC");
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
            "WormholeBridgeAdapter proxy implementation updated to:",
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

        // 3. Verify owner is still the deployer
        address deployer = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        require(
            adapter.owner() == deployer,
            "Ethereum: WormholeBridgeAdapter owner changed"
        );
        console.log("WormholeBridgeAdapter owner:", deployer);

        // 4. Verify gasLimit is 300_000
        require(
            adapter.gasLimit() == 300_000,
            "Ethereum: gasLimit changed after upgrade"
        );
        console.log("gasLimit preserved: 300000");

        // 5. Verify initializeV3 cannot be called again (reinitializer guard)
        try adapter.initializeV3(address(1)) {
            revert("Ethereum: initializeV3 should have reverted");
        } catch {}

        console.log("=== Validation Passed ===\n");
    }
}
