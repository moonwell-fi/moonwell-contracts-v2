// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {IERC4626} from "@forge-std/interfaces/IERC4626.sol";
import {RateLimitedAllowance} from "./RateLimitedAllowance.sol";
import {RateLimitCommonLibrary} from "@zelt/src/lib/RateLimitCommonLibrary.sol";
import {RateLimitedLibrary, RateLimit} from "@zelt/src/lib/RateLimitedLibrary.sol";

contract VaultRateLimitedAllowance is RateLimitedAllowance {
    function _transfer(
        address from,
        address to,
        uint160 amount,
        address vault
    ) internal override {
        IERC4626(vault).withdraw(uint256(amount), to, from);
    }
}
