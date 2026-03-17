// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {MultichainVoteCollection} from "@protocol/governance/multichain/MultichainVoteCollection.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {WormholeUnwrapperAdapter} from "@protocol/xWELL/WormholeUnwrapperAdapter.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {MOONBEAM_CHAIN_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID, ETHEREUM_CHAIN_ID} from "@utils/ChainIds.sol";

/*
 Executor Migration — Deploy new implementation contracts and upgrade proxies.

 Each chain needs its own execution since the contracts live on different chains.
 The executor and executorQuoterRouter addresses must be set via environment variables:

   WORMHOLE_EXECUTOR — Executor address for this chain
   WORMHOLE_EXECUTOR_QUOTER_ROUTER — ExecutorQuoterRouter address (0x0 if not yet deployed)

 The WORMHOLE_CORE address is read from the Addresses registry.

 --- Moonbeam ---
 Deploys: MultichainGovernor, WormholeBridgeAdapter, WormholeUnwrapperAdapter
 Upgrade: MULTICHAIN_GOVERNOR_PROXY, WORMHOLE_BRIDGE_ADAPTER_PROXY (to unwrapper)

   forge script script/DeployExecutorMigration.s.sol:DeployExecutorMigrationMoonbeam -vvvv --rpc-url moonbeam
   forge script script/DeployExecutorMigration.s.sol:DeployExecutorMigrationMoonbeam -vvvv --rpc-url moonbeam --broadcast --verify

 --- Base ---
 Deploys: MultichainVoteCollection, WormholeBridgeAdapter
 Upgrade: VOTE_COLLECTION_PROXY, WORMHOLE_BRIDGE_ADAPTER_PROXY

   forge script script/DeployExecutorMigration.s.sol:DeployExecutorMigrationBase -vvvv --rpc-url base
   forge script script/DeployExecutorMigration.s.sol:DeployExecutorMigrationBase -vvvv --rpc-url base --broadcast --verify

 --- Optimism ---
 Deploys: MultichainVoteCollection, WormholeBridgeAdapter
 Upgrade: VOTE_COLLECTION_PROXY, WORMHOLE_BRIDGE_ADAPTER_PROXY

   forge script script/DeployExecutorMigration.s.sol:DeployExecutorMigrationOptimism -vvvv --rpc-url optimism
   forge script script/DeployExecutorMigration.s.sol:DeployExecutorMigrationOptimism -vvvv --rpc-url optimism --broadcast --verify

 --- Ethereum ---
 Deploys: WormholeBridgeAdapter
 Upgrade: WORMHOLE_BRIDGE_ADAPTER_PROXY

   forge script script/DeployExecutorMigration.s.sol:DeployExecutorMigrationEthereum -vvvv --rpc-url ethereum
   forge script script/DeployExecutorMigration.s.sol:DeployExecutorMigrationEthereum -vvvv --rpc-url ethereum --broadcast --verify
*/

/// @notice Shared logic for deploying new implementation contracts
abstract contract ExecutorMigrationBase is Script {
    function _getExecutorAddresses()
        internal
        returns (address coreBridge, address executorAddr, address quoterRouter)
    {
        Addresses addresses = new Addresses();
        coreBridge = addresses.getAddress("WORMHOLE_CORE");
        executorAddr = vm.envAddress("WORMHOLE_EXECUTOR");
        quoterRouter = vm.envOr("WORMHOLE_EXECUTOR_QUOTER_ROUTER", address(0));
    }

    function _deployGovernorLogic(
        address coreBridge,
        address executorAddr,
        address quoterRouter
    ) internal returns (address) {
        address impl = address(
            new MultichainGovernor(coreBridge, executorAddr, quoterRouter)
        );
        console.log("MultichainGovernor logic deployed:", impl);
        return impl;
    }

    function _deployVoteCollectionLogic(
        address coreBridge,
        address executorAddr,
        address quoterRouter
    ) internal returns (address) {
        address impl = address(
            new MultichainVoteCollection(coreBridge, executorAddr, quoterRouter)
        );
        console.log("MultichainVoteCollection logic deployed:", impl);
        return impl;
    }

    function _deployBridgeAdapterLogic(
        address coreBridge,
        address executorAddr,
        address quoterRouter
    ) internal returns (address) {
        address impl = address(
            new WormholeBridgeAdapter(coreBridge, executorAddr, quoterRouter)
        );
        console.log("WormholeBridgeAdapter logic deployed:", impl);
        return impl;
    }

    function _deployUnwrapperAdapterLogic(
        address coreBridge,
        address executorAddr,
        address quoterRouter
    ) internal returns (address) {
        address impl = address(
            new WormholeUnwrapperAdapter(coreBridge, executorAddr, quoterRouter)
        );
        console.log("WormholeUnwrapperAdapter logic deployed:", impl);
        return impl;
    }

    function _upgradeProxy(
        ProxyAdmin proxyAdmin,
        address proxy,
        address newImpl,
        string memory label
    ) internal {
        console.log(
            string.concat("Upgrading ", label, " proxy:"),
            proxy
        );
        console.log("  -> new implementation:", newImpl);

        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(proxy),
            newImpl
        );
    }
}

/// @notice Deploy and upgrade on Moonbeam
/// Contracts: MultichainGovernor, WormholeBridgeAdapter (unwrapper)
contract DeployExecutorMigrationMoonbeam is ExecutorMigrationBase {
    function run() public {
        require(block.chainid == MOONBEAM_CHAIN_ID, "Must run on Moonbeam");

        Addresses addresses = new Addresses();
        (address coreBridge, address executorAddr, address quoterRouter) =
            _getExecutorAddresses();

        console.log("\n=== Executor Migration: Moonbeam ===");
        console.log("Core Bridge:", coreBridge);
        console.log("Executor:", executorAddr);
        console.log("Quoter Router:", quoterRouter);

        vm.startBroadcast();

        // Deploy new implementations with executor immutables
        address governorImpl = _deployGovernorLogic(coreBridge, executorAddr, quoterRouter);
        address unwrapperImpl = _deployUnwrapperAdapterLogic(coreBridge, executorAddr, quoterRouter);

        // Upgrade proxies
        // Note: MultichainGovernor is owned by governance (self-upgrade via proposal)
        // WormholeBridgeAdapter on Moonbeam uses the unwrapper variant
        // These upgrades must go through governance proposals in production.
        // This script deploys the implementations; the actual proxy upgrade
        // should be done via a governance proposal calling ProxyAdmin.upgrade().

        console.log("\n=== New Implementation Addresses ===");
        console.log("MultichainGovernor impl:", governorImpl);
        console.log("WormholeUnwrapperAdapter impl:", unwrapperImpl);

        vm.stopBroadcast();

        // Store addresses for governance proposal
        addresses.changeAddress("MULTICHAIN_GOVERNOR_IMPL", governorImpl, true);
        addresses.changeAddress("WORMHOLE_UNWRAPPER_ADAPTER_IMPL", unwrapperImpl, true);
        addresses.printAddresses();
    }
}

/// @notice Deploy and upgrade on Base
/// Contracts: MultichainVoteCollection, WormholeBridgeAdapter
contract DeployExecutorMigrationBase is ExecutorMigrationBase {
    function run() public {
        require(block.chainid == BASE_CHAIN_ID, "Must run on Base");

        Addresses addresses = new Addresses();
        (address coreBridge, address executorAddr, address quoterRouter) =
            _getExecutorAddresses();

        console.log("\n=== Executor Migration: Base ===");
        console.log("Core Bridge:", coreBridge);
        console.log("Executor:", executorAddr);
        console.log("Quoter Router:", quoterRouter);

        vm.startBroadcast();

        address voteCollectionImpl = _deployVoteCollectionLogic(coreBridge, executorAddr, quoterRouter);
        address bridgeAdapterImpl = _deployBridgeAdapterLogic(coreBridge, executorAddr, quoterRouter);

        console.log("\n=== New Implementation Addresses ===");
        console.log("MultichainVoteCollection impl:", voteCollectionImpl);
        console.log("WormholeBridgeAdapter impl:", bridgeAdapterImpl);

        vm.stopBroadcast();

        addresses.changeAddress("VOTE_COLLECTION_IMPL", voteCollectionImpl, true);
        addresses.changeAddress("WORMHOLE_BRIDGE_ADAPTER_LOGIC", bridgeAdapterImpl, true);
        addresses.printAddresses();
    }
}

/// @notice Deploy and upgrade on Optimism
/// Contracts: MultichainVoteCollection, WormholeBridgeAdapter
contract DeployExecutorMigrationOptimism is ExecutorMigrationBase {
    function run() public {
        require(block.chainid == OPTIMISM_CHAIN_ID, "Must run on Optimism");

        Addresses addresses = new Addresses();
        (address coreBridge, address executorAddr, address quoterRouter) =
            _getExecutorAddresses();

        console.log("\n=== Executor Migration: Optimism ===");
        console.log("Core Bridge:", coreBridge);
        console.log("Executor:", executorAddr);
        console.log("Quoter Router:", quoterRouter);

        vm.startBroadcast();

        address voteCollectionImpl = _deployVoteCollectionLogic(coreBridge, executorAddr, quoterRouter);
        address bridgeAdapterImpl = _deployBridgeAdapterLogic(coreBridge, executorAddr, quoterRouter);

        console.log("\n=== New Implementation Addresses ===");
        console.log("MultichainVoteCollection impl:", voteCollectionImpl);
        console.log("WormholeBridgeAdapter impl:", bridgeAdapterImpl);

        vm.stopBroadcast();

        addresses.changeAddress("VOTE_COLLECTION_IMPL", voteCollectionImpl, true);
        addresses.changeAddress("WORMHOLE_BRIDGE_ADAPTER_LOGIC", bridgeAdapterImpl, true);
        addresses.printAddresses();
    }
}

/// @notice Deploy and upgrade on Ethereum
/// Contracts: WormholeBridgeAdapter only
contract DeployExecutorMigrationEthereum is ExecutorMigrationBase {
    function run() public {
        require(block.chainid == ETHEREUM_CHAIN_ID, "Must run on Ethereum");

        Addresses addresses = new Addresses();
        (address coreBridge, address executorAddr, address quoterRouter) =
            _getExecutorAddresses();

        console.log("\n=== Executor Migration: Ethereum ===");
        console.log("Core Bridge:", coreBridge);
        console.log("Executor:", executorAddr);
        console.log("Quoter Router:", quoterRouter);

        vm.startBroadcast();

        address bridgeAdapterImpl = _deployBridgeAdapterLogic(coreBridge, executorAddr, quoterRouter);

        console.log("\n=== New Implementation Addresses ===");
        console.log("WormholeBridgeAdapter impl:", bridgeAdapterImpl);

        vm.stopBroadcast();

        addresses.changeAddress("WORMHOLE_BRIDGE_ADAPTER_LOGIC", bridgeAdapterImpl, true);
        addresses.printAddresses();
    }
}
