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

    MockERC4626 public vault;
    MockERC20 public underlying;
    ERC4626RateLimitedAllowance public rateLimitedAllowance;
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

    function testApproveAgainUpdateStorage() public {
        rateLimitedAllowance.approve(
            address(vault),
            1.5e16.toUint128(),
            1000e18.toUint128()
        );

        (
            uint128 rateLimitPerSecondStoredBefore,
            uint128 bufferCapStoredBefore,
            uint256 bufferBefore,
            uint256 lastBufferUsedTimeBefore
        ) = rateLimitedAllowance.getRateLimitedAllowance(
                address(this),
                address(vault)
            );

        vm.assertEq(
            rateLimitPerSecondStoredBefore,
            1.5e16,
            "Wrong rateLimitPerSecond"
        );
        vm.assertEq(bufferCapStoredBefore, 1000e18, "Wrong bufferCap before");
        vm.assertEq(bufferBefore, bufferCapStoredBefore, "Wrong buffer before");
        vm.assertEq(
            lastBufferUsedTimeBefore,
            block.timestamp,
            "Wrong last buffer used time"
        );

        uint128 newRateLimitPerSecond = 2e16.toUint128();
        uint128 newBufferCap = 2000e18.toUint128();

        vm.warp(1 days);

        rateLimitedAllowance.approve(
            address(vault),
            newRateLimitPerSecond,
            newBufferCap
        );

        (
            uint128 rateLimitPerSecondStored,
            uint128 bufferCapStored,
            uint256 buffer,
            uint256 lastBufferUsedTime
        ) = rateLimitedAllowance.getRateLimitedAllowance(
                address(this),
                address(vault)
            );

        vm.assertEq(
            rateLimitPerSecondStored,
            newRateLimitPerSecond,
            "Wrong rateLimitPerSecond"
        );
        vm.assertEq(bufferCapStored, newBufferCap, "Wrong bufferCap");
        vm.assertEq(buffer, newBufferCap, "Wrong buffer");
        vm.assertEq(
            lastBufferUsedTime,
            block.timestamp,
            "Wrong last buffer used time"
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
            uint128 bufferCapStored,
            uint256 buffer,
            uint256 lastBufferUsedTime
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

        vm.assertEq(buffer, bufferCap, "Wrong buffer");

        vm.assertEq(
            lastBufferUsedTime,
            block.timestamp,
            "Wrong last buffer used time"
        );
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

    function testTransferFailIfHitRateLimitBufferCap(
        uint128 bufferCap,
        uint128 rateLimitPerSecond
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

        underlying.mint(address(this), bufferCap);
        underlying.approve(address(vault), bufferCap);
        vault.deposit(bufferCap, address(this));

        vault.approve(address(rateLimitedAllowance), type(uint256).max);

        rateLimitedAllowance.approve(
            address(vault),
            rateLimitPerSecond,
            bufferCap
        );

        address receiver = address(0xADBC);

        vm.prank(spender);
        rateLimitedAllowance.transferFrom(
            address(this),
            receiver,
            bufferCap,
            address(vault)
        );

        vm.prank(spender);
        vm.expectRevert("RateLimited: no rate limit buffer");
        rateLimitedAllowance.transferFrom(
            address(this),
            receiver,
            bufferCap,
            address(vault)
        );
    }

    function testTransferFailIfHitRateLimit(
        uint128 bufferCap,
        uint128 rateLimitPerSecond
    ) public {
        bufferCap = _bound(
            bufferCap,
            1e6.toUint128(),
            (type(uint128).max).toUint128()
        ).toUint128();
        rateLimitPerSecond = _bound(
            rateLimitPerSecond,
            1.toUint128(),
            type(uint128).max.toUint128()
        ).toUint128();

        underlying.mint(address(this), bufferCap);
        underlying.approve(address(vault), bufferCap);
        vault.deposit(bufferCap, address(this));

        vault.approve(address(rateLimitedAllowance), type(uint256).max);

        rateLimitedAllowance.approve(
            address(vault),
            rateLimitPerSecond,
            bufferCap
        );

        address receiver = address(0xADBC);

        vm.prank(spender);
        rateLimitedAllowance.transferFrom(
            address(this),
            receiver,
            bufferCap - 1,
            address(vault)
        );

        vm.prank(spender);
        vm.expectRevert("RateLimited: rate limit hit");
        rateLimitedAllowance.transferFrom(
            address(this),
            receiver,
            2,
            address(vault)
        );
    }

    function testBufferIsDepletedWhenFundsAreWithdrawn(
        uint128 bufferCap,
        uint128 rateLimitPerSecond
    ) public {
        bufferCap = _bound(
            bufferCap,
            1e6.toUint128(),
            (type(uint128).max).toUint128()
        ).toUint128();
        rateLimitPerSecond = _bound(
            rateLimitPerSecond,
            1.toUint128(),
            type(uint128).max.toUint128()
        ).toUint128();

        underlying.mint(address(this), bufferCap);
        underlying.approve(address(vault), bufferCap);
        vault.deposit(bufferCap, address(this));

        vault.approve(address(rateLimitedAllowance), type(uint256).max);

        rateLimitedAllowance.approve(
            address(vault),
            rateLimitPerSecond,
            bufferCap
        );

        address receiver = address(0xADBC);

        vm.prank(spender);
        rateLimitedAllowance.transferFrom(
            address(this),
            receiver,
            bufferCap,
            address(vault)
        );

        (, , uint256 buffer, ) = rateLimitedAllowance.getRateLimitedAllowance(
            address(this),
            address(vault)
        );

        assertEq(buffer, 0, "Buffer is not depleted");
    }

    function testOwnerCanSetSpender() public {
        address newSpender = address(0x1234);

        vm.expectEmit();
        emit SpenderChanged(newSpender);
        rateLimitedAllowance.setSpender(newSpender);

        assertEq(rateLimitedAllowance.spender(), newSpender);
    }

    function testOnlyOwnerCanSetSpender() public {
        vm.prank(address(0x1234));
        vm.expectRevert("Ownable: caller is not the owner");
        rateLimitedAllowance.setSpender(address(0x1234));
    }

    function testOwnerCanPause() public {
        rateLimitedAllowance.pause();

        vm.assertEq(rateLimitedAllowance.paused(), true);
    }

    function testOwnerCanUnpause() public {
        testOwnerCanPause();

        rateLimitedAllowance.unpause();
        vm.assertEq(rateLimitedAllowance.paused(), false);
    }

    function testRevertIfUnpauseWhenNotPaused() public {
        vm.expectRevert("Pausable: not paused");
        rateLimitedAllowance.unpause();
    }
    function testRevertIfPauseWhenPaused() public {
        testOwnerCanPause();

        vm.expectRevert("Pausable: paused");
        rateLimitedAllowance.pause();
    }

    function testOnlyOwnerCanPause() public {
        vm.prank(address(0x1234));
        vm.expectRevert("Ownable: caller is not the owner");
        rateLimitedAllowance.pause();
    }

    function testOnlyOwnerCanUnpause() public {
        testOwnerCanPause();

        vm.prank(address(0x1234));
        vm.expectRevert("Ownable: caller is not the owner");
        rateLimitedAllowance.unpause();
    }

    function testTransferFromRevertsIfPaused() public {
        testOwnerCanPause();

        vm.expectRevert("Pausable: paused");
        rateLimitedAllowance.transferFrom(
            address(this),
            address(0x1234),
            1,
            address(vault)
        );
    }
}
