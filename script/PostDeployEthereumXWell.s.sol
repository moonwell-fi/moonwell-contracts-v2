// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {EthereumPostDeploymentActions} from "@protocol/xWELL/EthereumPostDeploymentActions.sol";

/*
    Post-Deployment Configuration for xWELL Ecosystem on Ethereum

    This script configures the xWELL ecosystem on Ethereum after MultichainGovernorV2 deployment.
    It performs the following actions:
    1. Grant pause guardian role on xWELL to PAUSE_GUARDIAN
    2. Set emissions manager on stkWELL to EMISSIONS_ADMIN
    3. Transfer ownership of xWELL to MultichainGovernorV2
    4. Transfer ownership of stkWELL to MultichainGovernorV2
    5. Transfer ownership of WormholeBridgeAdapter to MultichainGovernorV2

    Note: This script should be run AFTER mip-x44.sol is executed and MultichainGovernorV2
          is live on Ethereum mainnet.

    To simulate:
        forge script script/PostDeployEthereumXWell.s.sol:PostDeployEthereumXWell -vvvv --rpc-url ethereum

    To run:
        forge script script/PostDeployEthereumXWell.s.sol:PostDeployEthereumXWell -vvvv \
        --rpc-url ethereum --broadcast --etherscan-api-key ethereum --verify

*/
contract PostDeployEthereumXWell is Script, EthereumPostDeploymentActions {
    function run() external {
        // Load addresses
        Addresses addresses = new Addresses();

        // Get contract addresses
        address xWellProxy = addresses.getAddress("xWELL_PROXY");
        address stkWellProxy = addresses.getAddress("STK_GOVTOKEN_PROXY");
        address bridgeAdapterProxy = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );
        address pauseGuardian = addresses.getAddress("PAUSE_GUARDIAN");
        address emissionsAdmin = addresses.getAddress("EMISSIONS_ADMIN");
        address multichainGovernorV2 = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_V2_PROXY"
        );

        console.log(
            "=== Ethereum xWELL Ecosystem Post-Deployment Configuration ==="
        );
        console.log("xWELL Proxy:", xWellProxy);
        console.log("stkWELL Proxy:", stkWellProxy);
        console.log("WormholeBridgeAdapter Proxy:", bridgeAdapterProxy);
        console.log("Pause Guardian:", pauseGuardian);
        console.log("Emissions Admin:", emissionsAdmin);
        console.log("MultichainGovernorV2:", multichainGovernorV2);
        console.log("");

        // Verify current ownership
        console.log("=== Current State ===");
        address xWellOwner = xWELL(xWellProxy).owner();
        console.log("xWELL current owner:", xWellOwner);

        address bridgeAdapterOwner = WormholeBridgeAdapter(bridgeAdapterProxy)
            .owner();
        console.log("WormholeBridgeAdapter current owner:", bridgeAdapterOwner);

        // Note: stkWELL does not have an owner() function - it's controlled by governance
        console.log("stkWELL: controlled by governance (no owner)");
        console.log("");

        // Start broadcasting transactions
        vm.startBroadcast();

        console.log("=== Executing Configuration Actions ===");

        // 1. Grant pause guardian on xWELL
        console.log("1. Granting pause guardian on xWELL...");
        grantPauseGuardianXWell(xWellProxy, pauseGuardian);

        // 2. Set emissions manager on stkWELL
        console.log("2. Setting emissions manager on stkWELL...");
        setEmissionsManagerStkWell(stkWellProxy, emissionsAdmin);

        // 3. Transfer ownership of xWELL
        console.log(
            "3. Transferring xWELL ownership to MultichainGovernorV2..."
        );
        transferOwnershipXWell(xWellProxy, multichainGovernorV2);

        // 4. Transfer ownership of WormholeBridgeAdapter
        console.log(
            "4. Transferring WormholeBridgeAdapter ownership to MultichainGovernorV2..."
        );
        transferOwnershipBridgeAdapter(
            bridgeAdapterProxy,
            multichainGovernorV2
        );

        vm.stopBroadcast();

        console.log("");
        console.log("=== Post-Configuration State ===");

        // Verify pending ownership transfers (Ownable2Step pattern)
        address xWellPendingOwner = xWELL(xWellProxy).pendingOwner();
        console.log("xWELL pending owner:", xWellPendingOwner);
        require(
            xWellPendingOwner == multichainGovernorV2,
            "xWELL pending owner not set correctly"
        );

        address bridgeAdapterPendingOwner = WormholeBridgeAdapter(
            bridgeAdapterProxy
        ).pendingOwner();
        console.log(
            "WormholeBridgeAdapter pending owner:",
            bridgeAdapterPendingOwner
        );
        require(
            bridgeAdapterPendingOwner == multichainGovernorV2,
            "WormholeBridgeAdapter pending owner not set correctly"
        );

        console.log("");
        console.log("=== Configuration Complete ===");
        console.log(
            "NOTE: MultichainGovernorV2 must call acceptOwnership() on xWELL and WormholeBridgeAdapter to complete the transfer."
        );
        console.log("This can be done through a governance proposal.");
    }
}
