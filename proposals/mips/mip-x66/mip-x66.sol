//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {MarketUpdateV2Template} from "@proposals/templates/MarketUpdateV2.sol";

/// @title MIP-X66: Anthias Labs Urgent Risk Parameter Recommendations
///        (8/29/26)
/// @notice Data-driven market update: all parameter changes are configured in
///         x66.json (collateral factors, reserve factors, and interest rate
///         model replacements on Base and Optimism). The supply/borrow cap
///         changes from the same recommendation are executed separately by
///         the Cap Guardian and are not part of this proposal.
contract mipx66 is MarketUpdateV2Template {
    function name() external pure override returns (string memory) {
        return "MIP-X66";
    }
}
