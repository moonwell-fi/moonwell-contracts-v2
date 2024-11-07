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
        address indexed owner,
        uint128 rateLimitPerSecond,
        uint128 bufferCap
    );
    event SpenderChanged(address newSpender);

    ERC4626RateLimitedAllowance public rateLimitedAllowance;
    MockERC4626 public vault;
    MockERC20 underlying;
    address spender = address(0xABCD);

    function setUp() public {
        rateLimitedAllowance = new ERC4626RateLimitedAllowance(
            address(this),
            spender
        );

        underlying = new MockERC20("Mock Token", "TKN", 18);

        vault = new MockERC4626(underlying, "Vault Mock", "VAULT");
    }

    function testApproveEmitsApprovedEvent() public {
        uint128 rateLimitPerSecond = 1.5e16.toUint128();
        uint128 bufferCap = 1000e18.toUint128();

        vm.expectEmit();
        emit Approved(
            address(vault),
            address(this),
            rateLimitPerSecond,
            bufferCap
        );
        rateLimitedAllowance.approve(
            address(vault),
            rateLimitPerSecond,
            bufferCap
        );
    }

    function testFuzzApproveSetsToStorage(
        uint128 bufferCap,
        uint128 rateLimitPerSecond
    ) public {
        rateLimitedAllowance.approve(
            address(vault),
            rateLimitPerSecond,
            bufferCap
        );

        (
            uint128 rateLimitPerSecondStored,
            uint128 bufferCapStored
        ) = rateLimitedAllowance.getRateLimitedAllowance(
                address(this),
                address(vault)
            );

        vm.assertEq(
            rateLimitPerSecondStored,
            rateLimitPerSecond,
            "Wrong rateLimitPerSecond"
        );
        vm.assertEq(bufferCapStored, bufferCap, "Wrong bufferCap");
    }

    function testFuzzSpenderCanTransfer(
        uint128 bufferCap,
        uint128 rateLimitPerSecond,
        uint256 underlyingAmount
    ) public {
        bufferCap = _bound(
            bufferCap,
            1.toUint128(),
            (type(uint128).max).toUint128()
        ).toUint128();
        rateLimitPerSecond = _bound(
            rateLimitPerSecond,
            1.toUint128(),
            type(uint128).max.toUint128()
        ).toUint128();
        underlyingAmount = _bound(underlyingAmount, 1, bufferCap);

        address receiver = address(0xADBC);

        underlying.mint(address(this), underlyingAmount);
        underlying.approve(address(vault), underlyingAmount);
        vault.deposit(underlyingAmount, address(this));

        vault.approve(address(rateLimitedAllowance), type(uint256).max);

        rateLimitedAllowance.approve(
            address(vault),
            rateLimitPerSecond,
            bufferCap
        );

        uint256 receiverBalanceBefore = underlying.balanceOf(receiver);

        vm.prank(spender);
        rateLimitedAllowance.transferFrom(
            address(this),
            receiver,
            underlyingAmount,
            address(vault)
        );

        assertEq(
            receiverBalanceBefore + underlyingAmount,
            underlying.balanceOf(receiver),
            "Wrong receiver balance after withdrawn"
        );
    }

    function testOwnerCanSetSpender() public {
        address newSpender = address(0x1234);
        vm.expectEmit();
        emit SpenderChanged(newSpender);
        rateLimitedAllowance.setSpender(newSpender);
        assertEq(rateLimitedAllowance.spender(), newSpender);
    }
}
