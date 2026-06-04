// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";

import {CreditTierRegistry} from "@protocol/marketplace/CreditTierRegistry.sol";
import {CreditAttestation} from "@protocol/marketplace/CreditTypes.sol";

import {Signers} from "./Signers.sol";

contract CreditTierRegistryTest is Test, Signers {
    event TierSet(
        address indexed borrower,
        uint16 previousTier,
        uint16 newTier
    );
    event CreditBureauAttestorSet(
        address indexed previous,
        address indexed updated
    );
    event TierAttested(
        address indexed subject,
        uint16 tier,
        uint16 score,
        uint64 issuedAt,
        uint64 validUntil,
        bytes32 reportHash
    );

    CreditTierRegistry internal registry;
    address internal owner;
    address internal alice;
    address internal bob;
    address internal attestor;
    uint256 internal attestorKey;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        (attestor, attestorKey) = makeAddrAndKey("attestor");
        registry = new CreditTierRegistry(owner);
        vm.prank(owner);
        registry.setCreditBureauAttestor(attestor);
    }

    // ─── attestation helpers ─────────────────────────────────────────

    function _att(
        address subject,
        uint16 tierCode,
        uint64 issuedAt
    ) internal pure returns (CreditAttestation memory) {
        return
            CreditAttestation({
                subject: subject,
                tier: tierCode,
                score: 750,
                reportHash: keccak256("report"),
                issuedAt: issuedAt,
                validUntil: issuedAt + 1 hours
            });
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

    // ─── setCreditBureauAttestor ─────────────────────────────────────

    function test_setCreditBureauAttestor_happy() public {
        address newAttestor = makeAddr("newAttestor");
        vm.expectEmit(true, true, true, true, address(registry));
        emit CreditBureauAttestorSet(attestor, newAttestor);
        vm.prank(owner);
        registry.setCreditBureauAttestor(newAttestor);
        assertEq(registry.creditBureauAttestor(), newAttestor);
    }

    function test_setCreditBureauAttestor_onlyOwnerReverts() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        registry.setCreditBureauAttestor(alice);
    }

    function test_setCreditBureauAttestor_zeroReverts() public {
        vm.prank(owner);
        vm.expectRevert(CreditTierRegistry.ZeroAddress.selector);
        registry.setCreditBureauAttestor(address(0));
    }

    // ─── setTierFromAttestation ──────────────────────────────────────

    function test_setTierFromAttestation_happy() public {
        CreditAttestation memory att = _att(alice, 4, uint64(block.timestamp));
        bytes memory sig = signCreditAttestation(
            att,
            attestorKey,
            registry.DOMAIN_SEPARATOR()
        );

        vm.expectEmit(true, true, true, true, address(registry));
        emit TierSet(alice, 0, 4);

        // Permissionless: a random relayer (not owner, not subject) can submit.
        vm.prank(makeAddr("keeper"));
        registry.setTierFromAttestation(att, sig);

        assertEq(registry.tier(alice), 4);
        assertEq(registry.tierAttestedAt(alice), att.issuedAt);
    }

    function test_setTierFromAttestation_attestorNotSetReverts() public {
        CreditTierRegistry fresh = new CreditTierRegistry(owner); // no attestor
        CreditAttestation memory att = _att(alice, 4, uint64(block.timestamp));
        bytes memory sig = signCreditAttestation(
            att,
            attestorKey,
            fresh.DOMAIN_SEPARATOR()
        );
        vm.expectRevert(CreditTierRegistry.AttestorNotSet.selector);
        fresh.setTierFromAttestation(att, sig);
    }

    function test_setTierFromAttestation_subjectZeroReverts() public {
        CreditAttestation memory att = _att(
            address(0),
            4,
            uint64(block.timestamp)
        );
        bytes memory sig = signCreditAttestation(
            att,
            attestorKey,
            registry.DOMAIN_SEPARATOR()
        );
        vm.expectRevert(CreditTierRegistry.ZeroAddress.selector);
        registry.setTierFromAttestation(att, sig);
    }

    function test_setTierFromAttestation_tierTooHighReverts() public {
        CreditAttestation memory att = _att(alice, 5, uint64(block.timestamp));
        bytes memory sig = signCreditAttestation(
            att,
            attestorKey,
            registry.DOMAIN_SEPARATOR()
        );
        vm.expectRevert(
            abi.encodeWithSelector(CreditTierRegistry.TierTooHigh.selector, 5)
        );
        registry.setTierFromAttestation(att, sig);
    }

    function test_setTierFromAttestation_notYetValidReverts() public {
        CreditAttestation memory att = _att(
            alice,
            4,
            uint64(block.timestamp + 100)
        );
        bytes memory sig = signCreditAttestation(
            att,
            attestorKey,
            registry.DOMAIN_SEPARATOR()
        );
        vm.expectRevert(CreditTierRegistry.AttestationNotYetValid.selector);
        registry.setTierFromAttestation(att, sig);
    }

    function test_setTierFromAttestation_expiredReverts() public {
        vm.warp(10_000);
        // issuedAt 5000 (<= now), validUntil 8600 (< now=10000) → expired.
        CreditAttestation memory att = _att(
            alice,
            4,
            uint64(block.timestamp - 5_000)
        );
        bytes memory sig = signCreditAttestation(
            att,
            attestorKey,
            registry.DOMAIN_SEPARATOR()
        );
        vm.expectRevert(CreditTierRegistry.AttestationExpired.selector);
        registry.setTierFromAttestation(att, sig);
    }

    function test_setTierFromAttestation_badSignatureReverts() public {
        (, uint256 wrongKey) = makeAddrAndKey("wrong");
        CreditAttestation memory att = _att(alice, 4, uint64(block.timestamp));
        bytes memory sig = signCreditAttestation(
            att,
            wrongKey,
            registry.DOMAIN_SEPARATOR()
        );
        vm.expectRevert(
            CreditTierRegistry.InvalidAttestationSignature.selector
        );
        registry.setTierFromAttestation(att, sig);
    }

    function test_setTierFromAttestation_tamperedTierReverts() public {
        CreditAttestation memory att = _att(alice, 3, uint64(block.timestamp));
        bytes memory sig = signCreditAttestation(
            att,
            attestorKey,
            registry.DOMAIN_SEPARATOR()
        );
        // Tamper after signing: a higher tier than was signed must not verify.
        att.tier = 4;
        vm.expectRevert(
            CreditTierRegistry.InvalidAttestationSignature.selector
        );
        registry.setTierFromAttestation(att, sig);
    }

    function test_setTierFromAttestation_staleReplayReverts() public {
        CreditAttestation memory att = _att(alice, 4, uint64(block.timestamp));
        bytes memory sig = signCreditAttestation(
            att,
            attestorKey,
            registry.DOMAIN_SEPARATOR()
        );
        registry.setTierFromAttestation(att, sig);

        // Re-submitting the same (still-unexpired) attestation must revert —
        // blocks downgrade-replay of a stale higher-tier attestation.
        vm.expectRevert(
            abi.encodeWithSelector(
                CreditTierRegistry.StaleAttestation.selector,
                att.issuedAt,
                att.issuedAt
            )
        );
        registry.setTierFromAttestation(att, sig);
    }

    function test_setTierFromAttestation_newerOverwrites() public {
        vm.warp(1_000_000);
        CreditAttestation memory a1 = _att(alice, 2, uint64(block.timestamp));
        registry.setTierFromAttestation(
            a1,
            signCreditAttestation(a1, attestorKey, registry.DOMAIN_SEPARATOR())
        );
        assertEq(registry.tier(alice), 2);

        vm.warp(1_000_100);
        CreditAttestation memory a2 = _att(alice, 4, uint64(block.timestamp));
        registry.setTierFromAttestation(
            a2,
            signCreditAttestation(a2, attestorKey, registry.DOMAIN_SEPARATOR())
        );
        assertEq(registry.tier(alice), 4);
        assertEq(registry.tierAttestedAt(alice), uint64(block.timestamp));
    }
}
