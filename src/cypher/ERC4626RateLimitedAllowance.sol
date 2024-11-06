// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {IERC4626} from "@forge-std/interfaces/IERC4626.sol";
import {RateLimitedAllowance} from "./RateLimitedAllowance.sol";

contract ERC4626RateLimitedAllowance is RateLimitedAllowance {
    function _transfer(
        address from,
        address to,
        uint256 amount,
        address vault
    ) internal override {
        IERC4626(vault).withdraw(amount, to, from);
    }
}
