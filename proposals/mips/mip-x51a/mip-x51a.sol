//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {RewardsDistributionTemplate} from "@proposals/templates/RewardsDistribution.sol";

/// @title MIP-X51A
/// @notice Rewards distribution for Moonbeam + Optimism only (no Base actions).
///         Split from original mip-x51 to fit Moonbeam's effective per-extrinsic
///         gas ceiling (~25M empirical, vs. x51's 36.2M single-tx estimate).
///         Base actions and bad-debt repays live in mip-x51b.
contract mipx51a is RewardsDistributionTemplate {
    function name() external pure override returns (string memory) {
        return "MIP-X51A";
    }
}
