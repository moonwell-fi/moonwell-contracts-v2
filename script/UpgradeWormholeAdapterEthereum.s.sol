// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {ETHEREUM_CHAIN_ID, MOONBEAM_CHAIN_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID, BASE_WORMHOLE_CHAIN_ID, OPTIMISM_WORMHOLE_CHAIN_ID} from "@utils/ChainIds.sol";

/*

 Upgrade WormholeBridgeAdapter on Ethereum to V6.

 V5 (Wormhole Executor framework) was previously applied via this same script.
 V5 stored the on-chain Quoter contract in the `quoterAddress` slot, but the
 ExecutorQuoterRouter resolves `quoterContract[]` by the off-chain operator's
 signer EOA — so `bridgeCost()` silently returns 0. V6 overwrites the slot
 with `WORMHOLE_QUOTER_SIGNER` and re-validates end-to-end.

 The Ethereum xWELL deployment is owned by MOONWELL_DEPLOYER, not governance,
 so this is a one-off deployer script (same pattern as DeployXWellEthereum.s.sol).
 Base + Optimism are upgraded in lockstep via the governance MIP `mip-x53`.

 to simulate:
     forge script script/UpgradeWormholeAdapterEthereum.s.sol:UpgradeWormholeAdapterEthereum \
       -vvvv --rpc-url ethereum

 to run:
    forge script script/UpgradeWormholeAdapterEthereum.s.sol:UpgradeWormholeAdapterEthereum \
      -vvvv --rpc-url ethereum --broadcast --etherscan-api-key ethereum --verify

*/
contract UpgradeWormholeAdapterEthereum is Script {
    /// @notice new executor gas limit applied via `setGasLimit` after the
    ///         V6 upgrade. Mirrors the `mip-x53` bump on Base + Optimism.
    uint96 internal constant NEW_GAS_LIMIT = 700_000;

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
        address quoterSigner = addresses.getAddress("WORMHOLE_QUOTER_SIGNER");

        // Snapshot pre-upgrade state we expect to preserve through V6
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(adapterProxy);
        address ownerBefore = adapter.owner();
        uint96 gasLimitBefore = adapter.gasLimit();
        address xERC20Before = address(adapter.xERC20());
        address wormholeBefore = address(adapter.wormhole());
        address routerBefore = address(adapter.executorQuoterRouter());
        address executorBefore = address(adapter.executor());
        address quoterBefore = adapter.quoterAddress();

        console.log("=== Pre-upgrade state ===");
        console.log("  Adapter proxy   :", adapterProxy);
        console.log("  ProxyAdmin      :", proxyAdmin);
        console.log("  Owner           :", ownerBefore);
        console.log("  Gas limit       :", uint256(gasLimitBefore));
        console.log("  Target gas limit:", uint256(NEW_GAS_LIMIT));
        console.log("  xERC20          :", xERC20Before);
        console.log("  Wormhole core   :", wormholeBefore);
        console.log("  Quoter router   :", routerBefore);
        console.log("  Executor        :", executorBefore);
        console.log("  quoterAddress   :", quoterBefore, "(broken value)");
        console.log("  Target signer   :", quoterSigner);

        vm.startBroadcast();

        // Deploy new V6 implementation
        address newImpl = address(new WormholeBridgeAdapter());
        console.log("  New implementation:", newImpl);

        // Plain upgrade then call setQuoterAddress + setGasLimit on the proxy.
        // The new V6 implementation exposes setQuoterAddress so we can fix the
        // broken slot without a one-shot reinitializer; we bump the gas limit
        // in the same script to keep Ethereum aligned with mip-x53 on Base+OP.
        ProxyAdmin(proxyAdmin).upgrade(
            ITransparentUpgradeableProxy(adapterProxy),
            newImpl
        );
        adapter.setQuoterAddress(quoterSigner);
        adapter.setGasLimit(NEW_GAS_LIMIT);

        vm.stopBroadcast();

        console.log("\n=== Upgrade Complete ===");

        // Run validation
        _validateUpgrade(
            addresses,
            adapterProxy,
            proxyAdmin,
            newImpl,
            quoterSigner,
            ownerBefore,
            xERC20Before,
            wormholeBefore,
            routerBefore,
            executorBefore
        );
    }

    function _validateUpgrade(
        Addresses addresses,
        address adapterProxy,
        address proxyAdmin,
        address expectedImpl,
        address expectedSigner,
        address expectedOwner,
        address expectedXERC20,
        address expectedWormhole,
        address expectedRouter,
        address expectedExecutor
    ) internal {
        console.log("\n=== Running Validation ===");

        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(adapterProxy);

        // 1. Implementation upgraded
        validateProxy(
            vm,
            adapterProxy,
            expectedImpl,
            proxyAdmin,
            "Ethereum WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );

        // 2. quoterAddress now points at the off-chain signer
        require(
            adapter.quoterAddress() == expectedSigner,
            "quoterAddress not updated to signer"
        );

        // 3. Pre-V6 state preserved
        require(
            address(adapter.wormhole()) == expectedWormhole,
            "wormhole core bridge changed after upgrade"
        );
        require(
            address(adapter.executor()) == expectedExecutor,
            "executor changed after upgrade"
        );
        require(
            address(adapter.executorQuoterRouter()) == expectedRouter,
            "executorQuoterRouter changed after upgrade"
        );
        require(
            adapter.owner() == expectedOwner,
            "owner changed after upgrade"
        );
        require(
            adapter.gasLimit() == NEW_GAS_LIMIT,
            "gasLimit not bumped to 700k"
        );
        require(
            address(adapter.xERC20()) == expectedXERC20,
            "xERC20 changed after upgrade"
        );

        // 4. Trusted senders still configured
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

        // 5. bridgeCost(Base) is strictly positive after the V6 fix
        uint256 cost = adapter.bridgeCost(BASE_WORMHOLE_CHAIN_ID);
        console.log("  bridgeCost(Base):", cost);
        require(cost > 0, "bridgeCost still 0 after V6 fix");

        console.log("=== Validation Passed ===\n");
    }
}
