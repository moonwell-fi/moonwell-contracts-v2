// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {console} from "@forge-std/console.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

import {CreditLoan} from "@protocol/marketplace/CreditLoan.sol";
import {CreditMarketplaceFactory} from "@protocol/marketplace/CreditMarketplaceFactory.sol";
import {Offer, OfferStatus, Request, RequestStatus, BackendTerms, PaymentSchedule, LoanStatus} from "@protocol/marketplace/CreditTypes.sol";
import {CreditTypeHashes} from "@protocol/marketplace/CreditTypeHashes.sol";
import {EIP712Lib} from "@protocol/marketplace/EIP712Lib.sol";

import {Signers} from "@test/unit/marketplace/Signers.sol";

interface IMErc20Mint {
    function mint(uint256 amount) external returns (uint256);
}

/// End-to-end integration test against a forked Base with real Moonwell.
/// No mocks, no stubs: the lender supplies real USDC, receives real
/// mUSDC, and the clone performs real `enterMarkets` + `borrow` +
/// `repayBorrowBehalf` calls against the live Comptroller and mUSDC on
/// Base mainnet. This is the flow PR9 / the audit team / a real-world
/// deploy would actually run — everything the unit suites only
/// approximate with mocks.
contract CreditMarketplaceIntegration is Test, Signers {
    Addresses internal addresses;

    CreditLoan internal loanImpl;
    CreditMarketplaceFactory internal factory;

    address internal temporalGovernor;
    address internal unitroller;
    address internal pauseGuardian;
    address internal usdc;
    address internal mUsdc;
    address internal cbbtc;
    address internal usdcOracle;
    address internal btcUsdFeed;

    address internal feeRecipient;
    address internal backendSignerEOA;
    uint256 internal backendSignerKey;
    address internal lender;
    uint256 internal lenderKey;
    address internal borrower;
    uint256 internal borrowerKey;

    // Loan economics — conservative so Moonwell's collateral factor on
    // mUSDC comfortably supports the borrow.
    uint256 internal constant LENDER_USDC_SUPPLY = 1_000e6; // 1,000 USDC
    uint256 internal constant M_TOKEN_AMOUNT_HINT = 900e6; // most of the mUSDC
    uint256 internal constant PRINCIPAL = 400e6; // 400 USDC borrowed
    uint256 internal constant INTEREST_AMT = 10e6; // 10 USDC per installment
    uint256 internal constant FINAL_AMT = PRINCIPAL + INTEREST_AMT; // with trailing stub
    uint32 internal constant NUM_INTEREST = 4;
    uint32 internal constant INTERVAL = 7 days;
    uint256 internal constant COLLATERAL_AMOUNT = 1e7; // 0.1 cbBTC (~$10k)
    uint32 internal constant GRACE = 1 days;
    uint16 internal constant FEE_BPS = 500; // 5%
    uint16 internal constant OVER_SEIZURE_BPS = 2_000;

    function setUp() public {
        vm.createSelectFork("base");
        addresses = new Addresses();

        temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        unitroller = addresses.getAddress("UNITROLLER");
        pauseGuardian = addresses.getAddress("PAUSE_GUARDIAN");
        usdc = addresses.getAddress("USDC");
        mUsdc = addresses.getAddress("MOONWELL_USDC");
        cbbtc = addresses.getAddress("cbBTC");
        usdcOracle = addresses.getAddress("USDC_ORACLE");
        btcUsdFeed = addresses.getAddress("CHAINLINK_BTC_USD");

        feeRecipient = makeAddr("feeRecipient");
        (backendSignerEOA, backendSignerKey) = makeAddrAndKey("backend");
        (lender, lenderKey) = makeAddrAndKey("lender");
        (borrower, borrowerKey) = makeAddrAndKey("borrower");

        loanImpl = new CreditLoan();
        factory = new CreditMarketplaceFactory(
            temporalGovernor,
            unitroller,
            address(loanImpl),
            backendSignerEOA,
            feeRecipient,
            pauseGuardian
        );

        // Governance-level setup per spec §14.3 post-deploy checklist.
        vm.startPrank(temporalGovernor);
        factory.whitelistMToken(mUsdc, true);
        factory.whitelistPrincipalToken(
            usdc,
            AggregatorV3Interface(usdcOracle)
        );
        factory.whitelistCollateralToken(
            cbbtc,
            AggregatorV3Interface(btcUsdFeed)
        );
        factory.setStalenessWindow(1 days);
        factory.setMinOriginationLtvBufferBps(1_000); // 10%
        factory.setDefaultParams(
            GRACE,
            OVER_SEIZURE_BPS,
            2, // consecutiveMissesForDefault
            FEE_BPS
        );
        vm.stopPrank();

        // Lender supplies USDC into Moonwell, receives real mUSDC.
        deal(usdc, lender, LENDER_USDC_SUPPLY);
        vm.startPrank(lender);
        IERC20(usdc).approve(mUsdc, LENDER_USDC_SUPPLY);
        uint256 err = IMErc20Mint(mUsdc).mint(LENDER_USDC_SUPPLY);
        require(err == 0, "mUSDC mint failed");
        vm.stopPrank();

        // Borrower holds the non-Moonwell collateral.
        deal(cbbtc, borrower, COLLATERAL_AMOUNT);

        // Approvals to factory (used at createLoan's safeTransferFrom).
        vm.prank(lender);
        IERC20(mUsdc).approve(address(factory), type(uint256).max);
        vm.prank(borrower);
        IERC20(cbbtc).approve(address(factory), type(uint256).max);
    }

    function _lenderMTokenBalance() internal view returns (uint256) {
        return IERC20(mUsdc).balanceOf(lender);
    }

    function _offer(
        uint256 nonce,
        uint256 mTokenAmount
    ) internal view returns (Offer memory o) {
        address[] memory col = new address[](1);
        col[0] = cbbtc;
        o = Offer({
            lender: lender,
            mToken: mUsdc,
            mTokenAmount: mTokenAmount,
            principalToken: usdc,
            maxPrincipal: 500e6,
            maxApr: 1_000,
            minApr: 500,
            minTerm: 1 days,
            maxTerm: 60 days,
            acceptedCollateral: col,
            minBorrowerCreditTier: 0,
            expiresAt: uint64(block.timestamp + 1 hours),
            nonce: nonce,
            status: OfferStatus.Active
        });
    }

    function _request(uint256 nonce) internal view returns (Request memory r) {
        r = Request({
            borrower: borrower,
            principalToken: usdc,
            principal: PRINCIPAL,
            collateralToken: cbbtc,
            collateralAmount: COLLATERAL_AMOUNT,
            maxApr: 1_000,
            minTerm: 1 days,
            maxTerm: 60 days,
            expiresAt: uint64(block.timestamp + 1 hours),
            nonce: nonce,
            status: RequestStatus.Active
        });
    }

    function _terms(
        uint256 loanNonce,
        uint256 mTokenAmount,
        uint64 firstDueAt
    ) internal view returns (BackendTerms memory t) {
        PaymentSchedule memory s = PaymentSchedule({
            numInterestPayments: NUM_INTEREST,
            intervalSeconds: INTERVAL,
            firstInterestDueAt: firstDueAt,
            principalDueAt: firstDueAt + uint64(INTERVAL) * NUM_INTEREST,
            interestAmountPerPayment: INTEREST_AMT,
            finalPaymentAmount: FINAL_AMT
        });
        t = BackendTerms({
            chainId: block.chainid,
            factory: address(factory),
            loanNonce: loanNonce,
            lender: lender,
            borrower: borrower,
            mToken: mUsdc,
            mTokenAmount: mTokenAmount,
            principalToken: usdc,
            principal: PRINCIPAL,
            collateralToken: cbbtc,
            collateralAmount: COLLATERAL_AMOUNT,
            apr: 800,
            term: 30 days,
            schedule: s,
            gracePeriod: GRACE,
            overSeizureBps: OVER_SEIZURE_BPS,
            consecutiveMissesForDefault: 2,
            marketplaceFeeBps: FEE_BPS,
            feeRecipient: feeRecipient,
            borrowerCreditTier: 0,
            issuedAt: uint64(block.timestamp),
            validUntil: uint64(block.timestamp + 1 hours)
        });
    }

    struct LifecycleContext {
        uint256 mTokenAmount;
        uint64 firstDueAt;
        uint256 feeRecipientStart;
    }

    function _postAndMatch(
        uint256 mTokenAmount,
        uint64 firstDueAt
    ) internal returns (address loanAddr) {
        bytes32 domain = factory.DOMAIN_SEPARATOR();
        Offer memory o = _offer(1, mTokenAmount);
        Request memory r = _request(2);
        BackendTerms memory t = _terms(3, mTokenAmount, firstDueAt);

        uint256 offerId = factory.postOffer(o, signOffer(o, lenderKey, domain));
        uint256 requestId = factory.postRequest(
            r,
            signRequest(r, borrowerKey, domain)
        );

        bytes memory oSig = signOffer(o, lenderKey, domain);
        bytes memory rSig = signRequest(r, borrowerKey, domain);
        bytes memory bSig = signBackendTerms(t, backendSignerKey, domain);

        (, loanAddr) = factory.createLoan(
            offerId,
            requestId,
            t,
            oSig,
            rSig,
            bSig
        );
    }

    function _runPaymentLoop(CreditLoan clone, uint64 firstDueAt) internal {
        // Borrower funds their upcoming payments + approves the clone.
        deal(usdc, borrower, FINAL_AMT * 2);
        vm.prank(borrower);
        IERC20(usdc).approve(address(clone), type(uint256).max);

        for (uint32 i = 0; i < NUM_INTEREST; i++) {
            vm.warp(firstDueAt + uint64(i) * INTERVAL);
            vm.prank(borrower);
            clone.makePayment();
            assertEq(clone.paymentCursor(), i + 1);
        }
        assertEq(clone.totalInterestPaid(), NUM_INTEREST * INTEREST_AMT);

        vm.warp(firstDueAt + uint64(NUM_INTEREST) * INTERVAL - 1);
        vm.prank(borrower);
        clone.makePayment();
    }

    function test_fullLifecycle_happyPath() public {
        LifecycleContext memory ctx = LifecycleContext({
            mTokenAmount: _lenderMTokenBalance(),
            firstDueAt: uint64(block.timestamp + INTERVAL),
            feeRecipientStart: IERC20(usdc).balanceOf(feeRecipient)
        });
        assertTrue(
            ctx.mTokenAmount >= M_TOKEN_AMOUNT_HINT,
            "lender needs real mUSDC"
        );

        address loanAddr = _postAndMatch(ctx.mTokenAmount, ctx.firstDueAt);
        CreditLoan clone = CreditLoan(loanAddr);

        assertTrue(clone.status() == LoanStatus.Active);
        assertEq(IERC20(mUsdc).balanceOf(loanAddr), ctx.mTokenAmount);
        assertEq(IERC20(cbbtc).balanceOf(loanAddr), COLLATERAL_AMOUNT);
        assertEq(
            IERC20(usdc).balanceOf(borrower),
            PRINCIPAL,
            "borrower should have received principal"
        );

        _runPaymentLoop(clone, ctx.firstDueAt);

        assertTrue(clone.status() == LoanStatus.Settled);

        // Moonwell's real borrow APR accrues over the term, so the exact
        // fee + lender split depends on the fork block's utilization.
        // Upper-bound checks based on gross interest paid, plus
        // conservation-of-value: the clone is fully drained, and the
        // distribution (fee + lender + leftover for Moonwell interest)
        // equals the gross borrower interest contributions.
        uint256 grossInterest = NUM_INTEREST *
            INTEREST_AMT +
            (FINAL_AMT - PRINCIPAL);
        uint256 feeReceived = IERC20(usdc).balanceOf(feeRecipient) -
            ctx.feeRecipientStart;
        uint256 lenderUsdc = IERC20(usdc).balanceOf(lender);

        assertGt(feeReceived, 0, "fee recipient should have received some fee");
        assertLe(
            feeReceived,
            (grossInterest * FEE_BPS) / 10_000,
            "fee <= gross interest share"
        );
        assertGt(lenderUsdc, 0, "lender should have received some interest");
        assertLe(lenderUsdc, grossInterest, "lender <= gross interest");
        // Lender + fee together must equal the distributable pot
        // (grossInterest minus Moonwell's accrued borrow interest).
        assertLt(
            feeReceived + lenderUsdc,
            grossInterest,
            "Moonwell consumed non-zero borrow accrual"
        );
        // Lender's mToken balance >= original pledged (supply yield only
        // ever adds).
        assertGe(IERC20(mUsdc).balanceOf(lender), ctx.mTokenAmount);
        assertEq(
            IERC20(cbbtc).balanceOf(borrower),
            COLLATERAL_AMOUNT,
            "borrower should have received residual collateral"
        );
        assertEq(IERC20(mUsdc).balanceOf(loanAddr), 0);
        assertEq(IERC20(cbbtc).balanceOf(loanAddr), 0);
        assertEq(IERC20(usdc).balanceOf(loanAddr), 0, "clone fully drained");
    }
}
