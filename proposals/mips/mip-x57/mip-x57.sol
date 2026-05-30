//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {RewardsDistributionTemplate} from "@proposals/templates/RewardsDistribution.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {BASE_FORK_ID, OPTIMISM_FORK_ID} from "@utils/ChainIds.sol";

/// @title MIP-X57
/// @notice Rewards distribution for the 2026-05-22 -> 2026-06-19 epoch.
///         Unlike prior rewards MIPs, this one does NOT bridge xWELL from
///         Moonbeam in-proposal. xWELL on Base TG and Optimism TG is
///         expected to be pre-staged via a separate fast-path (prep MIP
///         or direct MGLIMMER multisig action) before x57 executes on
///         chain. Rationale: Wormhole Executor signed quotes have ~1h
///         expiry and Moonwell governance takes ~5 days, so a quote
///         signed at MIP-authoring time would be stale on execution.
///
///         For fork simulation, beforeSimulationHook() deals xWELL to
///         the destination TGs to model that pre-staging.
contract mipx57 is RewardsDistributionTemplate {
    function name() external pure override returns (string memory) {
        return "MIP-X57";
    }

    function beforeSimulationHook(Addresses addresses) public override {
        super.beforeSimulationHook(addresses);

        // Pre-stage xWELL on destination TGs to simulate the separate
        // bridge step that happens outside this proposal.
        _preStageDestinationTG(
            addresses,
            BASE_FORK_ID,
            12_000_000e18 // covers Base TG outflow 11,856,475.01 WELL
        );
        _preStageDestinationTG(
            addresses,
            OPTIMISM_FORK_ID,
            900_000e18 // covers Optimism TG outflow 877,006.57 WELL
        );
    }

    function _preStageDestinationTG(
        Addresses addresses,
        uint256 forkId,
        uint256 amount
    ) internal {
        vm.selectFork(forkId);
        address xwell = addresses.getAddress("xWELL_PROXY");
        address tg = addresses.getAddress("TEMPORAL_GOVERNOR");
        deal(xwell, tg, IERC20(xwell).balanceOf(tg) + amount);
    }
}
