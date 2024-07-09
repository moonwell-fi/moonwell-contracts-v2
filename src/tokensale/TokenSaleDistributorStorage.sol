// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./TokenSaleDistributorProxyStorage.sol";

contract TokenSaleDistributorStorage is TokenSaleDistributorProxyStorage {
    address public tokenAddress;

    // 60 * 60 * 24 * 365 / 12 seconds
    uint256 public constant monthlyVestingInterval = 2628000;

    mapping(address => Allocation[]) public allocations;

    struct Allocation {
        // True for linear vesting, false for monthly
        bool isLinear;
        // Vesting start timestamp
        uint256 epoch;
        // Linear: The amount of seconds after the cliff before all tokens are vested
        // Monthly: The number of monthly claims before all tokens are vested
        uint256 vestingDuration;
        // Seconds after epoch when tokens start vesting
        uint256 cliff;
        // Percentage of tokens that become vested immediately after the cliff. 100 % = 1e18.
        uint256 cliffPercentage;
        // Total amount of allocated tokens
        uint256 amount;
        // Amount of claimed tokens from this allocation
        uint256 claimed;
    }
}
