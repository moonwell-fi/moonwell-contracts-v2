// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";

/// @title EthereumPostDeploymentActions
/// @notice Abstract contract containing actions to configure xWELL ecosystem on Ethereum
/// @dev This contract exposes functions for setting up ownership and permissions
///      after MultichainGovernorV2 is live on Ethereum. These functions can be
///      called from a script or mocked in tests with vm.startPrank.
abstract contract EthereumPostDeploymentActions {
    /// @notice Grant pause guardian role on xWELL
    /// @param xWellProxy The xWELL proxy address
    /// @param pauseGuardian The address to grant pause guardian role to
    function grantPauseGuardianXWell(
        address xWellProxy,
        address pauseGuardian
    ) public {
        xWELL(xWellProxy).grantPauseGuardian(pauseGuardian);
    }

    /// @notice Set emissions manager on stkWELL
    /// @param stkWellProxy The stkWELL proxy address
    /// @param emissionsManager The emissions manager address to set
    /// @dev stkWELL uses the Aave StakedToken pattern with governance-controlled emissions
    ///      Note: stkWELL does not have an owner() function, only governance controls
    function setEmissionsManagerStkWell(
        address stkWellProxy,
        address emissionsManager
    ) public {
        (bool success, ) = stkWellProxy.call(
            abi.encodeWithSignature(
                "setEmissionsManager(address)",
                emissionsManager
            )
        );
        require(success, "Failed to set emissions manager");
    }

    /// @notice Transfer ownership of xWELL to new owner
    /// @param xWellProxy The xWELL proxy address
    /// @param newOwner The new owner address (MultichainGovernorV2)
    function transferOwnershipXWell(
        address xWellProxy,
        address newOwner
    ) public {
        xWELL(xWellProxy).transferOwnership(newOwner);
    }

    /// @notice Accept ownership of xWELL (called by new owner)
    /// @param xWellProxy The xWELL proxy address
    /// @dev This should be called by the new owner to complete the 2-step transfer
    function acceptOwnershipXWell(address xWellProxy) public {
        xWELL(xWellProxy).acceptOwnership();
    }

    /// @notice Transfer ownership of WormholeBridgeAdapter to new owner
    /// @param bridgeAdapterProxy The WormholeBridgeAdapter proxy address
    /// @param newOwner The new owner address (MultichainGovernorV2)
    function transferOwnershipBridgeAdapter(
        address bridgeAdapterProxy,
        address newOwner
    ) public {
        WormholeBridgeAdapter(bridgeAdapterProxy).transferOwnership(newOwner);
    }

    /// @notice Accept ownership of WormholeBridgeAdapter (called by new owner)
    /// @param bridgeAdapterProxy The WormholeBridgeAdapter proxy address
    /// @dev This should be called by the new owner to complete the 2-step transfer
    function acceptOwnershipBridgeAdapter(address bridgeAdapterProxy) public {
        WormholeBridgeAdapter(bridgeAdapterProxy).acceptOwnership();
    }

    /// @notice Execute all post-deployment actions in sequence
    /// @param xWellProxy The xWELL proxy address
    /// @param stkWellProxy The stkWELL proxy address
    /// @param bridgeAdapterProxy The WormholeBridgeAdapter proxy address
    /// @param pauseGuardian The pause guardian address
    /// @param emissionsManager The emissions manager address
    /// @param newOwner The new owner address (MultichainGovernorV2)
    function executeAllActions(
        address xWellProxy,
        address stkWellProxy,
        address bridgeAdapterProxy,
        address pauseGuardian,
        address emissionsManager,
        address newOwner
    ) public {
        // 1. Grant pause guardian on xWELL
        grantPauseGuardianXWell(xWellProxy, pauseGuardian);

        // 2. Set emissions manager on stkWELL
        setEmissionsManagerStkWell(stkWellProxy, emissionsManager);

        // 3. Transfer ownership of xWELL
        transferOwnershipXWell(xWellProxy, newOwner);

        // 4. Transfer ownership of WormholeBridgeAdapter
        transferOwnershipBridgeAdapter(bridgeAdapterProxy, newOwner);
    }
}
