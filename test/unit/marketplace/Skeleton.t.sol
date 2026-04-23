// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {InitParams} from "@protocol/marketplace/CreditTypes.sol";
import {CreditLoan} from "@protocol/marketplace/CreditLoan.sol";
import {CreditMarketplaceFactory} from "@protocol/marketplace/CreditMarketplaceFactory.sol";

import {Fixture} from "./Fixture.t.sol";

contract SkeletonTest is Fixture {
    function test_fixtureLoads() public view {
        assertTrue(address(factory) != address(0));
        assertTrue(address(loanImpl) != address(0));
        assertEq(block.chainid, 8453);
    }

    function test_factoryConstructor_setsImmutables() public view {
        assertEq(factory.owner(), temporalGovernor);
        assertEq(factory.temporalGovernor(), temporalGovernor);
        assertEq(factory.comptroller(), unitroller);
        assertEq(factory.pauseGuardian(), pauseGuardian);
        assertEq(factory.backendSigner(), backendSignerEOA);
        assertEq(factory.feeRecipient(), feeRecipient);
        assertEq(factory.creditLoanImplementation(), address(loanImpl));
        assertTrue(factory.DOMAIN_SEPARATOR() != bytes32(0));
    }

    function test_factoryConstructor_rejectsComptrollerImpl() public {
        CreditLoan freshImpl = new CreditLoan();
        address comptrollerImpl = addresses.getAddress("COMPTROLLER");

        vm.expectRevert(CreditMarketplaceFactory.InvalidComptroller.selector);
        new CreditMarketplaceFactory(
            temporalGovernor,
            comptrollerImpl,
            address(freshImpl),
            backendSignerEOA,
            feeRecipient,
            pauseGuardian
        );
    }

    function test_factoryConstructor_rejectsZeroAddresses() public {
        CreditLoan freshImpl = new CreditLoan();

        vm.expectRevert(CreditMarketplaceFactory.ZeroAddress.selector);
        new CreditMarketplaceFactory(
            address(0),
            unitroller,
            address(freshImpl),
            backendSignerEOA,
            feeRecipient,
            pauseGuardian
        );

        vm.expectRevert(CreditMarketplaceFactory.ZeroAddress.selector);
        new CreditMarketplaceFactory(
            temporalGovernor,
            unitroller,
            address(freshImpl),
            backendSignerEOA,
            feeRecipient,
            address(0)
        );
    }

    function test_creditLoanImpl_cannotBeReinitialized() public {
        InitParams memory p;
        vm.expectRevert(CreditLoan.AlreadyInitialized.selector);
        loanImpl.initialize(p);
    }

    function test_creditLoanImpl_factorySetFromConstructorMsgSender()
        public
        view
    {
        /// The factory locked the impl via initialize(sentinel) during its
        /// own constructor — so msg.sender from the impl's POV was the
        /// factory contract itself. Post-fix (initialize binds
        /// factory = msg.sender), loanImpl.factory() must equal the
        /// factory's address.
        assertEq(loanImpl.factory(), address(factory));
    }

    function test_creditLoan_initializeBindsFactoryToMsgSender() public {
        /// A fresh clone-like contract initialized by an arbitrary caller
        /// records that caller as `factory`. This is the core guarantee
        /// that makes cross-tx front-running harmless: an attacker who
        /// front-runs clone.initialize ends up with a clone whose factory
        /// is the attacker, not the real factory — so downstream
        /// factory-only hooks key off the wrong address and reject the
        /// attacker's clone.
        CreditLoan fresh = new CreditLoan();
        address rogue = makeAddr("rogue");

        InitParams memory p;
        vm.prank(rogue);
        fresh.initialize(p);

        assertEq(fresh.factory(), rogue);
    }

    function test_pause_callableByGuardian_unpauseOwnerOnly() public {
        vm.prank(pauseGuardian);
        factory.pause();
        assertTrue(factory.paused());

        vm.prank(pauseGuardian);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.unpause();

        vm.prank(temporalGovernor);
        factory.unpause();
        assertFalse(factory.paused());
    }

    function test_pause_rejectsRandomCaller() public {
        vm.expectRevert(CreditMarketplaceFactory.OnlyOwnerOrGuardian.selector);
        factory.pause();
    }
}
