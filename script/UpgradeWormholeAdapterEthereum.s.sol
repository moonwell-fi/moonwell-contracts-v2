// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {ETHEREUM_CHAIN_ID, MOONBEAM_CHAIN_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID, BASE_WORMHOLE_CHAIN_ID, OPTIMISM_WORMHOLE_CHAIN_ID, ETHEREUM_WORMHOLE_CHAIN_ID} from "@utils/ChainIds.sol";

/*

 Upgrade WormholeBridgeAdapter on Ethereum to Wormhole Executor framework (V4).

 The adapter already has V3 (wormhole core bridge) set from the processVAA migration.
 This V4 upgrade adds executor, quoter router, quoter, and wormhole chain ID.

 The Ethereum xWELL deployment is owned by MOONWELL_DEPLOYER, not governance,
 so this is a one-off deployer script (same pattern as DeployXWellEthereum.s.sol).

 to simulate:
     forge script script/UpgradeWormholeAdapterEthereum.s.sol:UpgradeWormholeAdapterEthereum \
       -vvvv --rpc-url ethereum

 to run:
    forge script script/UpgradeWormholeAdapterEthereum.s.sol:UpgradeWormholeAdapterEthereum \
      -vvvv --rpc-url ethereum --broadcast --etherscan-api-key ethereum --verify

*/
contract UpgradeWormholeAdapterEthereum is Script {
    function run() public {
        Addresses addresses = new Addresses();

        require(
            block.chainid == ETHEREUM_CHAIN_ID,
            "This script must be run on Ethereum mainnet"
        );

        address proxyAdmin = addresses.getAddress("PROXY_ADMIN");
        address adapterProxy = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );

        // Snapshot pre-upgrade state
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(adapterProxy);
        address ownerBefore = adapter.owner();
        uint96 gasLimitBefore = adapter.gasLimit();
        address xERC20Before = address(adapter.xERC20());
        address wormholeBefore = address(adapter.wormhole());

        console.log("=== Pre-upgrade state ===");
        console.log("  Owner:", ownerBefore);
        console.log("  Gas limit:", uint256(gasLimitBefore));
        console.log("  xERC20:", xERC20Before);
        console.log("  Wormhole (V3):", wormholeBefore);
        console.log("  Proxy:", adapterProxy);
        console.log("  ProxyAdmin:", proxyAdmin);

        vm.startBroadcast();

        // Deploy new implementation
        address newImpl = address(new WormholeBridgeAdapter());
        console.log("  New implementation:", newImpl);

        // Upgrade and initialize V5 (executor framework)
        // V3 (wormhole core bridge) is already set on-chain
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(adapterProxy),
            newImpl,
            abi.encodeWithSignature(
                "initializeV5(address,address,address)",
                addresses.getAddress("WORMHOLE_EXECUTOR"),
                addresses.getAddress("WORMHOLE_QUOTER_ROUTER"),
                addresses.getAddress("WORMHOLE_QUOTER")
            )
        );

        vm.stopBroadcast();

        console.log("\n=== Upgrade Complete ===");

        // Run validation
        _validateUpgrade(
            addresses,
            adapterProxy,
            proxyAdmin,
            newImpl,
            ownerBefore,
            gasLimitBefore,
            xERC20Before,
            wormholeBefore
        );
    }

    function _validateUpgrade(
        Addresses addresses,
        address adapterProxy,
        address proxyAdmin,
        address expectedImpl,
        address expectedOwner,
        uint96 expectedGasLimit,
        address expectedXERC20,
        address expectedWormhole
    ) internal view {
        console.log("\n=== Running Validation ===");

        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(adapterProxy);

        // 1. Verify implementation upgraded
        validateProxy(
            vm,
            adapterProxy,
            expectedImpl,
            proxyAdmin,
            "Ethereum WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );

        // 2. Verify V3 state preserved (wormhole core bridge)
        require(
            address(adapter.wormhole()) == expectedWormhole,
            "wormhole core bridge changed after upgrade"
        );

        // 3. Verify V4 state (executor framework)
        require(
            address(adapter.executor()) ==
                addresses.getAddress("WORMHOLE_EXECUTOR"),
            "executor not set correctly"
        );
        require(
            address(adapter.executorQuoterRouter()) ==
                addresses.getAddress("WORMHOLE_QUOTER_ROUTER"),
            "executorQuoterRouter not set correctly"
        );
        // 4. Verify storage preservation
        require(
            adapter.owner() == expectedOwner,
            "owner changed after upgrade"
        );
        require(
            adapter.gasLimit() == expectedGasLimit,
            "gasLimit changed after upgrade"
        );
        require(
            address(adapter.xERC20()) == expectedXERC20,
            "xERC20 changed after upgrade"
        );

        // 5. Verify trusted senders still configured
        require(
            adapter.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    MOONBEAM_CHAIN_ID
                )
            ),
            "Moonbeam adapter not trusted"
        );
        require(
            adapter.isTrustedSender(
                BASE_WORMHOLE_CHAIN_ID,
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    BASE_CHAIN_ID
                )
            ),
            "Base adapter not trusted"
        );
        require(
            adapter.isTrustedSender(
                OPTIMISM_WORMHOLE_CHAIN_ID,
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    OPTIMISM_CHAIN_ID
                )
            ),
            "Optimism adapter not trusted"
        );

        console.log("=== Validation Passed ===\n");
    }
}
