// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";

import {Address} from "@utils/Address.sol";

import {IRateLimitedAllowance} from "@protocol/cypher/IRateLimitedAllowance.sol";
import {ERC4626RateLimitedAllowance} from "@protocol/cypher/ERC4626RateLimitedAllowance.sol";

contract ERC4626RateLimitedAllowanceUnitTest is Test {
    using SafeCast for *;
    event Approved(
        address indexed token,
        address indexed spender,
        address indexed owner,
        uint128 rateLimitPerSecond,
        uint128 bufferCap
    );

    ERC4626RateLimitedAllowance public rateLimitedAllowance;
    MockERC4626 public vault;

    function setUp() public {
        rateLimitedAllowance = new ERC4626RateLimitedAllowance();

        MockERC20 token = new MockERC20("Mock Token", "TKN", 18);

        vault = new MockERC4626(token, "Vault Mock", "VAULT");
    }

    function testApproveEmitsApprovedEvent() public {
        address spender = address(1234);
        uint128 rateLimitPerSecond = 1.5e16.toUint128();
        uint128 bufferCap = 1000e18.toUint128();

        vm.expectEmit();
        emit Approved(
            address(vault),
            spender,
            address(this),
            rateLimitPerSecond,
            bufferCap
        );
        rateLimitedAllowance.approve(
            address(vault),
            spender,
            rateLimitPerSecond,
            bufferCap
        );
    }

    function testApproveSetsToStorage() public {
        address spender = address(1234);
        uint128 rateLimitPerSecond = 1.5e16.toUint128();
        uint128 bufferCap = 1000e18.toUint128();

        rateLimitedAllowance.approve(
            address(vault),
            spender,
            rateLimitPerSecond,
            bufferCap
        );

        (
            uint128 rateLimitPerSecondStored,
            uint128 bufferCapStored
        ) = rateLimitedAllowance.getRateLimitedAllowance(
                address(this),
                address(vault),
                spender
            );

        vm.assertEq(
            rateLimitPerSecondStored,
            rateLimitPerSecond,
            "Wrong rateLimitPerSecond"
        );
        vm.assertEq(bufferCapStored, bufferCap, "Wrong bufferCap");
    }
}
