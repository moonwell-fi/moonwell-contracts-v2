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
    MockERC20 underlying;

    function setUp() public {
        rateLimitedAllowance = new ERC4626RateLimitedAllowance();

        underlying = new MockERC20("Mock Token", "TKN", 18);

        vault = new MockERC4626(underlying, "Vault Mock", "VAULT");

        //        address initialMinter = address(0xCAFE);
        //        underlying.mint(address(this), 10000e18);
        //        underlying.approve(address(vault), 10000e18);
        //        vault.deposit(10000e18, address(this));
    }

    function testApproveEmitsApprovedEvent() public {
        address spender = address(0xABCD);
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
        address spender = address(0xABCD);
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

    function testSpenderCanTransferBufferCap() public {
        address spender = address(0xABCD);
        address receiver = address(0xADBC);
        uint128 rateLimitPerSecond = 1.5e16.toUint128();
        uint128 bufferCap = 1000e18.toUint128();
        uint256 underlyingAmount = 10_000e18;

        underlying.mint(address(this), underlyingAmount);
        underlying.approve(address(vault), underlyingAmount);
        vault.deposit(underlyingAmount, address(this));

        rateLimitedAllowance.approve(
            address(vault),
            spender,
            rateLimitPerSecond,
            bufferCap
        );

        vm.prank(spender);
        rateLimitedAllowance.transferFrom(
            address(this),
            receiver,
            uint256(bufferCap),
            address(vault)
        );
    }
}
