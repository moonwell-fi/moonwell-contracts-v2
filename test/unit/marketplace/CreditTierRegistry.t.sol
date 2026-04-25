// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";

import {CreditTierRegistry} from "@protocol/marketplace/CreditTierRegistry.sol";

contract CreditTierRegistryTest is Test {
    event TierSet(
        address indexed borrower,
        uint16 previousTier,
        uint16 newTier
    );

    CreditTierRegistry internal registry;
    address internal owner;
    address internal alice;
    address internal bob;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        registry = new CreditTierRegistry(owner);
    }

    function test_constructor_setsOwner() public {
        assertEq(registry.owner(), owner);
    }

    function test_constructor_zeroOwnerReverts() public {
        vm.expectRevert(CreditTierRegistry.ZeroAddress.selector);
        new CreditTierRegistry(address(0));
    }

    function test_tier_defaultsZero() public {
        assertEq(registry.tier(alice), 0);
    }

    function test_setTier_happy() public {
        vm.expectEmit(true, true, true, true, address(registry));
        emit TierSet(alice, 0, 500);

        vm.prank(owner);
        registry.setTier(alice, 500);

        assertEq(registry.tier(alice), 500);
    }

    function test_setTier_overwriteEmitsPrevious() public {
        vm.prank(owner);
        registry.setTier(alice, 200);

        vm.expectEmit(true, true, true, true, address(registry));
        emit TierSet(alice, 200, 800);

        vm.prank(owner);
        registry.setTier(alice, 800);
        assertEq(registry.tier(alice), 800);
    }

    function test_setTier_onlyOwnerReverts() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        registry.setTier(bob, 1);
    }

    function test_setTier_zeroBorrowerReverts() public {
        vm.prank(owner);
        vm.expectRevert(CreditTierRegistry.ZeroAddress.selector);
        registry.setTier(address(0), 1);
    }

    function test_setTiers_batchHappy() public {
        address[] memory addrs = new address[](2);
        addrs[0] = alice;
        addrs[1] = bob;
        uint16[] memory tiers = new uint16[](2);
        tiers[0] = 100;
        tiers[1] = 999;

        vm.prank(owner);
        registry.setTiers(addrs, tiers);

        assertEq(registry.tier(alice), 100);
        assertEq(registry.tier(bob), 999);
    }

    function test_setTiers_lengthMismatchReverts() public {
        address[] memory addrs = new address[](2);
        addrs[0] = alice;
        addrs[1] = bob;
        uint16[] memory tiers = new uint16[](1);
        tiers[0] = 100;

        vm.prank(owner);
        vm.expectRevert(CreditTierRegistry.LengthMismatch.selector);
        registry.setTiers(addrs, tiers);
    }

    function test_setTiers_zeroBorrowerInBatchReverts() public {
        address[] memory addrs = new address[](2);
        addrs[0] = alice;
        addrs[1] = address(0);
        uint16[] memory tiers = new uint16[](2);
        tiers[0] = 1;
        tiers[1] = 2;

        vm.prank(owner);
        vm.expectRevert(CreditTierRegistry.ZeroAddress.selector);
        registry.setTiers(addrs, tiers);
    }

    function test_setTiers_onlyOwnerReverts() public {
        address[] memory addrs = new address[](1);
        addrs[0] = alice;
        uint16[] memory tiers = new uint16[](1);
        tiers[0] = 1;

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        registry.setTiers(addrs, tiers);
    }

    function test_ownership_twoStepTransfer() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        registry.transferOwnership(newOwner);
        assertEq(registry.owner(), owner);
        assertEq(registry.pendingOwner(), newOwner);

        vm.prank(newOwner);
        registry.acceptOwnership();
        assertEq(registry.owner(), newOwner);
        assertEq(registry.pendingOwner(), address(0));
    }

    function test_ownership_acceptByNonPendingReverts() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        registry.transferOwnership(newOwner);

        vm.prank(alice);
        vm.expectRevert("Ownable2Step: caller is not the new owner");
        registry.acceptOwnership();
    }
}
