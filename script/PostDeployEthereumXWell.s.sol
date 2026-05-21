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
    To simulate (dry-run, no --broadcast):
        forge script \
          script/PostDeployEthereumXWell.s.sol:PostDeployEthereumXWellDeployer \
          -vvvv --rpc-url ethereum

    To execute (requires MOONWELL_DEPLOYER signer — must be current stkWELL
    EMISSION_MANAGER, and mip-x58 must already be on-chain):
        forge script \
          script/PostDeployEthereumXWell.s.sol:PostDeployEthereumXWellDeployer \
          -vvvv --rpc-url ethereum --broadcast
*/
contract PostDeployEthereumXWellDeployer is
    Script,
    EthereumPostDeploymentActions
{
    function run() external {
        Addresses addresses = new Addresses();

        address stkWellProxy = addresses.getAddress("STK_GOVTOKEN_PROXY");
        address emissionsAdmin = addresses.getAddress("EMISSIONS_ADMIN");

        // mip-x58 retargets EMISSIONS_ADMIN to MultichainGovernorV2 in
        address currentEmissionManager = IStakedWell(stkWellProxy)
            .EMISSION_MANAGER();

        console.log(
            "=== Ethereum xWELL Step 2: setEmissionsManager on stkWELL ==="
        );
        console.log("stkWELL Proxy:           ", stkWellProxy);
        console.log("Current EMISSION_MANAGER:", currentEmissionManager);
        console.log("Target EMISSIONS_ADMIN:  ", emissionsAdmin);
        console.log("");
        console.log(
            "NOTE: broadcasting key must equal the current EMISSION_MANAGER."
        );
        console.log("");

        vm.startBroadcast();
        setEmissionsManagerStkWell(stkWellProxy, emissionsAdmin);
        vm.stopBroadcast();

        address newEmissionManager = IStakedWell(stkWellProxy)
            .EMISSION_MANAGER();
        console.log("Post-tx EMISSION_MANAGER:", newEmissionManager);
        require(
            newEmissionManager == emissionsAdmin,
            "EMISSION_MANAGER not updated"
        );
    }
}

/*
    Prints target + calldata for the 3 transactions to be submitted from the
    PAUSE_GUARDIAN multisig on Ethereum. Read-only — does NOT broadcast.

    Submit each (target, calldata) pair as a separate Safe transaction.

    To print:
        forge script \
          script/PostDeployEthereumXWell.s.sol:PostDeployEthereumXWellMultisig \
          -vvvv --rpc-url ethereum
*/
contract PostDeployEthereumXWellMultisig is Script {
    function run() external {
        Addresses addresses = new Addresses();

        address xWellProxy = addresses.getAddress("xWELL_PROXY");
        address bridgeAdapterProxy = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );
        address pauseGuardian = addresses.getAddress("PAUSE_GUARDIAN");
        address multichainGovernorV2 = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_V2_PROXY"
        );

        console.log("=== PAUSE_GUARDIAN multisig calldata (Ethereum) ===");
        console.log("Multisig (PAUSE_GUARDIAN):", pauseGuardian);
        console.log("");

        console.log("--- Current state ---");
        console.log(
            "xWELL.owner():                ",
            xWELL(xWellProxy).owner()
        );
        console.log(
            "xWELL.pendingOwner():         ",
            xWELL(xWellProxy).pendingOwner()
        );
        console.log(
            "BridgeAdapter.owner():        ",
            WormholeBridgeAdapter(bridgeAdapterProxy).owner()
        );
        console.log(
            "BridgeAdapter.pendingOwner(): ",
            WormholeBridgeAdapter(bridgeAdapterProxy).pendingOwner()
        );
        console.log("");

        // Tx 1 — step 1: grantPauseGuardian on xWELL
        console.log(
            "--- Tx 1 (step 1): xWELL.grantPauseGuardian(PAUSE_GUARDIAN) ---"
        );
        console.log("target:  ", xWellProxy);
        console.log("calldata:");
        console.logBytes(
            abi.encodeWithSignature(
                "grantPauseGuardian(address)",
                pauseGuardian
            )
        );
        console.log("");

        // Tx 2 — step 3: transferOwnership on xWELL
        console.log(
            "--- Tx 2 (step 3): xWELL.transferOwnership(MultichainGovernorV2) ---"
        );
        console.log("target:  ", xWellProxy);
        console.log("calldata:");
        console.logBytes(
            abi.encodeWithSignature(
                "transferOwnership(address)",
                multichainGovernorV2
            )
        );
        console.log("");

        // Tx 3 — step 4: transferOwnership on WormholeBridgeAdapter
        console.log(
            "--- Tx 3 (step 4): WormholeBridgeAdapter.transferOwnership(MultichainGovernorV2) ---"
        );
        console.log("target:  ", bridgeAdapterProxy);
        console.log("calldata:");
        console.logBytes(
            abi.encodeWithSignature(
                "transferOwnership(address)",
                multichainGovernorV2
            )
        );
        console.log("");

        console.log("=== Follow-up ===");
        console.log(
            "After execution, MultichainGovernorV2 must call acceptOwnership() on:"
        );
        console.log(" - xWELL:                ", xWellProxy);
        console.log(" - WormholeBridgeAdapter:", bridgeAdapterProxy);
        console.log("This is done via a governance proposal.");
    }
}
