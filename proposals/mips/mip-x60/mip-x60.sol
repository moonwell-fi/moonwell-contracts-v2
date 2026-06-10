//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {RewardsDistributionV2Template} from "@proposals/templates/RewardsDistributionV2.sol";

/// @title MIP-X60
/// @notice Rewards distribution for the 2026-06-19 -> 2026-07-19 epoch.
///         First rewards MIP executed from Ethereum (MultichainGovernorV2):
///         - chain 1 is the source chain: FOUNDATION_MULTISIG funds the
///           governor (xWELL bridged to the Base Temporal Governor via the
///           WormholeBridgeAdapter on-chain-quoted path) and funds the
///           Ethereum MRD directly via transferFrom
///         - Base/Optimism remain external destination chains
///         - Moonbeam is a pure destination chain in wind-down mode
///         The template's beforeSimulationHook already simulates the
///         foundation's xWELL approval (and sim-only balance top-up), so no
///         extra hook is needed here.
contract mipx60 is RewardsDistributionV2Template {
    function name() external pure override returns (string memory) {
        return "MIP-X60";
    }
}
