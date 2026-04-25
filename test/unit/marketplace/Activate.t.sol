// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {CreditLoan} from "@protocol/marketplace/CreditLoan.sol";
import {InitParams, LoanStatus} from "@protocol/marketplace/CreditTypes.sol";

import {Fixture} from "./Fixture.t.sol";

/// Tests for CreditLoan.activate — the step the factory runs after the
/// clone is initialized (spec §7.3 tail). PR5 will wire this into the
/// real createLoan flow; PR4 unit-tests it in isolation by hand-deploying
/// a fresh CreditLoan (non-proxy, but functionally equivalent for logic
/// verification), pranking the factory as msg.sender, and mocking the
/// Moonwell comptroller + mToken calls.
contract ActivateTest is Fixture {
    event LoanActivated(uint64 activatedAt);

    /// Selectors for Moonwell surface we mock. Declared here so the tests
    /// don't need to import the Moonwell contracts directly.
    bytes4 internal constant ENTER_MARKETS_SEL =
        bytes4(keccak256("enterMarkets(address[])"));
    bytes4 internal constant BORROW_SEL = bytes4(keccak256("borrow(uint256)"));

    uint256 internal constant PRINCIPAL = 400e6;

    CreditLoan internal clone;

    function setUp() public override {
        super.setUp();
        clone = new CreditLoan();
        InitParams memory p = _defaultParams();
        vm.prank(address(factory));
        clone.initialize(p);
    }

    // ─── helpers ─────────────────────────────────────────────────────

    function _defaultParams() internal view returns (InitParams memory p) {
        p.lender = lender;
        p.borrower = borrower;
        p.mToken = mUsdc;
        p.mTokenAmount = 1_000e6;
        p.principalToken = usdc;
        p.principal = PRINCIPAL;
        p.collateralToken = cbbtc;
        p.collateralAmount = 1e7;
        p.apr = 1_000;
        p.term = 30 days;
        p.feeRecipient = feeRecipient;
        p.comptrollerAddr = unitroller;
        p.collateralFeedStaleness = 3_600;
        p.principalFeedStaleness = 3_600;
    }

    function _mockMoonwellSuccess() internal {
        uint256[] memory errs = new uint256[](1);
        vm.mockCall(
            unitroller,
            abi.encodeWithSelector(ENTER_MARKETS_SEL),
            abi.encode(errs)
        );
        vm.mockCall(
            mUsdc,
            abi.encodeWithSelector(BORROW_SEL, PRINCIPAL),
            abi.encode(uint256(0))
        );
        /// borrow() on the real mToken would mint USDC into the clone;
        /// we mock it away, so simulate the post-borrow state by dealing
        /// USDC directly into the clone.
        deal(usdc, address(clone), PRINCIPAL);
    }

    // ─── tests ────────────────────────────────────────────────────────

    function test_activate_happyTransitionsToActive() public {
        _mockMoonwellSuccess();

        assertTrue(clone.status() == LoanStatus.Pending);

        uint256 borrowerBefore = IERC20(usdc).balanceOf(borrower);

        vm.expectEmit(true, true, true, true, address(clone));
        emit LoanActivated(uint64(block.timestamp));

        vm.prank(address(factory));
        clone.activate();

        assertTrue(clone.status() == LoanStatus.Active);
        assertEq(clone.activatedAt(), uint64(block.timestamp));
        assertEq(IERC20(usdc).balanceOf(borrower) - borrowerBefore, PRINCIPAL);
        assertEq(IERC20(usdc).balanceOf(address(clone)), 0);
    }

    function test_activate_nonFactoryReverts() public {
        _mockMoonwellSuccess();

        vm.prank(lender);
        vm.expectRevert(CreditLoan.OnlyFactory.selector);
        clone.activate();
    }

    function test_activate_twiceReverts() public {
        _mockMoonwellSuccess();

        vm.prank(address(factory));
        clone.activate();

        /// Re-fund so the second call wouldn't fail on transfer — the
        /// point is the status guard fires first.
        deal(usdc, address(clone), PRINCIPAL);

        vm.prank(address(factory));
        vm.expectRevert(CreditLoan.LoanNotPending.selector);
        clone.activate();
    }

    function test_activate_enterMarketsFailureReverts() public {
        uint256[] memory errs = new uint256[](1);
        errs[0] = 7;
        vm.mockCall(
            unitroller,
            abi.encodeWithSelector(ENTER_MARKETS_SEL),
            abi.encode(errs)
        );

        vm.prank(address(factory));
        vm.expectRevert(
            abi.encodeWithSelector(CreditLoan.EnterMarketsFailed.selector, 7)
        );
        clone.activate();
    }

    function test_activate_borrowFailureReverts() public {
        uint256[] memory errs = new uint256[](1);
        vm.mockCall(
            unitroller,
            abi.encodeWithSelector(ENTER_MARKETS_SEL),
            abi.encode(errs)
        );
        vm.mockCall(
            mUsdc,
            abi.encodeWithSelector(BORROW_SEL, PRINCIPAL),
            abi.encode(uint256(9))
        );

        vm.prank(address(factory));
        vm.expectRevert(
            abi.encodeWithSelector(CreditLoan.BorrowFailed.selector, 9)
        );
        clone.activate();
    }
}
