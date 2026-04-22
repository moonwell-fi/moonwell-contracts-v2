//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {RewardsDistributionTemplate} from "@proposals/templates/RewardsDistribution.sol";

/// @title MIP-X51B
/// @notice Rewards distribution for Base only (setMRDSpeeds, transferFrom,
///         withdrawWell, merkleCampaigns) plus the Moonbeam-side
///         bridgeToRecipient + transferFrom that fund Base's Temporal
///         Governor. Split from MIP-X51 to fit Moonbeam's per-transaction
///         gas ceiling of 16,777,216 (2^24). Bad-debt repayments originally
///         bundled with this proposal now ship separately as MIP-X51C.
contract mipx51b is RewardsDistributionTemplate {
    function name() external pure override returns (string memory) {
        return "MIP-X51B";
    }
}
