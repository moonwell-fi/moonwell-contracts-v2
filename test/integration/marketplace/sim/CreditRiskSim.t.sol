// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {console} from "@forge-std/console.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

import {CreditLoan} from "@protocol/marketplace/CreditLoan.sol";
import {CreditMarketplaceFactory} from "@protocol/marketplace/CreditMarketplaceFactory.sol";
import {CreditTierRegistry} from "@protocol/marketplace/CreditTierRegistry.sol";
import {Offer, OfferStatus, Request, RequestStatus, BackendTerms, PaymentSchedule, LoanStatus} from "@protocol/marketplace/CreditTypes.sol";

import {Signers} from "@test/unit/marketplace/Signers.sol";

interface IMErc20Mint {
    function mint(uint256 amount) external returns (uint256);
}

interface IMTokenView {
    function borrowRatePerTimestamp() external view returns (uint256);

    function borrowBalanceCurrent(address) external returns (uint256);

    function balanceOfUnderlying(address) external returns (uint256);
}

/// RISK SIMULATION (not a pass/fail suite — run with -vv to read the tables).
/// Quantifies, against real Moonwell on a forked Base, the lender's PnL when
/// a borrower strategically defaults after the escrowed collateral falls. The
/// loan is sized to the protocol's enforced MINIMUM borrower over-
/// collateralization (110% via minOriginationLtvBufferBps = 1000) so the
/// numbers describe the protocol's risk BOUNDARY, not a conservative backend.
///
///   RUN_RISK_SIM=true forge test \
///     --match-path 'test/integration/marketplace/sim/CreditRiskSim.t.sol' \
///     --match-test test_riskReport -vv
contract CreditRiskSim is Test, Signers {
    Addresses internal addresses;

    CreditLoan internal loanImpl;
    CreditMarketplaceFactory internal factory;
    CreditTierRegistry internal tierRegistry;

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

    uint16 internal loanApr;
    uint256 internal collateral110; // collateral units ≈ 110% of principal

    // Lender supplies generously so the clone's Moonwell health stays high and
    // the ONLY variable in these scenarios is the borrower's collateral. The
    // Moonwell-liquidation axis is studied separately (see report).
    uint256 internal constant LENDER_USDC_SUPPLY = 5_000e6;
    uint256 internal constant PRINCIPAL = 400e6;
    uint256 internal constant INTEREST_AMT = 10e6;
    uint256 internal constant FINAL_AMT = PRINCIPAL + INTEREST_AMT;
    uint32 internal constant NUM_INTEREST = 4;
    uint32 internal constant INTERVAL = 7 days;
    uint32 internal constant GRACE = 1 days;
    uint16 internal constant FEE_BPS = 500;
    uint16 internal constant OVER_SEIZURE_BPS = 2_000; // 20%
    uint16 internal constant LTV_BUFFER_BPS = 1_000; // 10% origination buffer

    /// This is an analysis harness, not a CI test. It lives outside the
    /// `test/integration/marketplace/*` CI glob and is additionally gated:
    /// run it explicitly with `RUN_RISK_SIM=true forge test --match-path
    /// 'test/integration/marketplace/sim/CreditRiskSim.t.sol' -vv`.
    function _simEnabled() internal view returns (bool) {
        return vm.envOr("RUN_RISK_SIM", false);
    }

    function setUp() public {
        if (!_simEnabled()) return; // skip the fork + setup when not requested
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
        tierRegistry = new CreditTierRegistry(makeAddr("tierOwner"));
        factory = new CreditMarketplaceFactory(
            temporalGovernor,
            unitroller,
            address(loanImpl),
            backendSignerEOA,
            feeRecipient,
            pauseGuardian,
            address(tierRegistry)
        );

        vm.startPrank(temporalGovernor);
        factory.setStalenessWindow(1 days);
        factory.whitelistMToken(
            mUsdc,
            true,
            AggregatorV3Interface(usdcOracle),
            uint32(1 days)
        );
        factory.whitelistCollateralToken(
            cbbtc,
            true,
            AggregatorV3Interface(btcUsdFeed),
            uint32(1 days)
        );
        factory.setMinOriginationLtvBufferBps(LTV_BUFFER_BPS);
        factory.setDefaultParams(GRACE, OVER_SEIZURE_BPS, 2, FEE_BPS);
        vm.stopPrank();

        deal(usdc, lender, LENDER_USDC_SUPPLY);
        vm.startPrank(lender);
        IERC20(usdc).approve(mUsdc, LENDER_USDC_SUPPLY);
        require(
            IMErc20Mint(mUsdc).mint(LENDER_USDC_SUPPLY) == 0,
            "mint failed"
        );
        vm.stopPrank();

        loanApr = _aprAboveMoonwell();
        collateral110 = _collateralForBuffer();

        vm.prank(lender);
        IERC20(mUsdc).approve(address(factory), type(uint256).max);
    }

    // ─── helpers ─────────────────────────────────────────────────────

    function _aprAboveMoonwell() internal view returns (uint16) {
        uint256 ratePerSec = IMTokenView(mUsdc).borrowRatePerTimestamp();
        uint256 minBps = (ratePerSec * 365 days) / 1e14;
        return uint16(minBps + 100);
    }

    /// cbBTC units worth ≈ 110% of PRINCIPAL at the live BTC/USD price (the
    /// protocol minimum), with a hair of margin so origination clears.
    function _collateralForBuffer() internal view returns (uint256) {
        (, int256 answer, , , ) = AggregatorV3Interface(btcUsdFeed)
            .latestRoundData();
        // priceUsd1e18 per cbBTC = answer(8dec) * 1e10. principalUsd1e18 ≈
        // PRINCIPAL(6dec) * 1e12 (USDC ~$1). required = principalUsd * 1.1.
        uint256 priceUsd1e18 = uint256(answer) * 1e10;
        uint256 requiredUsd1e18 = (PRINCIPAL *
            1e12 *
            (10_000 + LTV_BUFFER_BPS)) / 10_000;
        uint256 units = (requiredUsd1e18 * 1e8) / priceUsd1e18;
        return (units * 1003) / 1000; // +0.3% so collateral >= required
    }

    function _btcAnswer() internal view returns (int256 a) {
        (, a, , , ) = AggregatorV3Interface(btcUsdFeed).latestRoundData();
    }

    /// Mock the cbBTC feed to `dropBps` below its live price, fresh-stamped.
    function _crashCollateral(uint16 dropBps) internal returns (int256) {
        (uint80 r, int256 a, uint256 s, , uint80 ar) = AggregatorV3Interface(
            btcUsdFeed
        ).latestRoundData();
        int256 crashed = (a * int256(uint256(10_000 - dropBps))) / 10_000;
        vm.mockCall(
            btcUsdFeed,
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(r, crashed, s, block.timestamp, ar)
        );
        return crashed;
    }

    function _refreshUsdcFeed() internal {
        (uint80 r, int256 a, uint256 s, , uint80 ar) = AggregatorV3Interface(
            usdcOracle
        ).latestRoundData();
        vm.mockCall(
            usdcOracle,
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(r, a, s, block.timestamp, ar)
        );
    }

    function _originate(uint64 firstDueAt) internal returns (CreditLoan clone) {
        bytes32 d = factory.DOMAIN_SEPARATOR();
        uint256 mAmt = IERC20(mUsdc).balanceOf(lender);
        address[] memory col = new address[](1);
        col[0] = cbbtc;
        Offer memory o = Offer({
            lender: lender,
            mToken: mUsdc,
            mTokenAmount: mAmt,
            principalToken: usdc,
            maxPrincipal: 500e6,
            maxApr: loanApr,
            minApr: 0,
            minTerm: 1 days,
            maxTerm: 60 days,
            acceptedCollateral: col,
            minBorrowerCreditTier: 0,
            expiresAt: uint64(block.timestamp + 1 hours),
            nonce: 1,
            status: OfferStatus.Active
        });
        Request memory r = Request({
            borrower: borrower,
            principalToken: usdc,
            principal: PRINCIPAL,
            collateralToken: cbbtc,
            collateralAmount: collateral110,
            maxApr: loanApr,
            minTerm: 1 days,
            maxTerm: 60 days,
            expiresAt: uint64(block.timestamp + 1 hours),
            nonce: 2,
            status: RequestStatus.Active
        });
        PaymentSchedule memory s = PaymentSchedule({
            numInterestPayments: NUM_INTEREST,
            intervalSeconds: INTERVAL,
            firstInterestDueAt: firstDueAt,
            principalDueAt: firstDueAt + uint64(INTERVAL) * NUM_INTEREST,
            interestAmountPerPayment: INTEREST_AMT,
            finalPaymentAmount: FINAL_AMT
        });
        BackendTerms memory t = BackendTerms({
            chainId: block.chainid,
            factory: address(factory),
            loanNonce: 3,
            lender: lender,
            borrower: borrower,
            mToken: mUsdc,
            mTokenAmount: mAmt,
            principalToken: usdc,
            principal: PRINCIPAL,
            collateralToken: cbbtc,
            collateralAmount: collateral110,
            apr: loanApr,
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

        deal(cbbtc, borrower, collateral110);
        vm.prank(borrower);
        IERC20(cbbtc).approve(address(factory), type(uint256).max);

        uint256 offerId = factory.postOffer(o, signOffer(o, lenderKey, d));
        uint256 requestId = factory.postRequest(
            r,
            signRequest(r, borrowerKey, d)
        );
        bytes memory oSig = signOffer(o, lenderKey, d);
        bytes memory rSig = signRequest(r, borrowerKey, d);
        bytes memory bSig = signBackendTerms(t, backendSignerKey, d);
        (, address loanAddr) = factory.createLoan(
            offerId,
            requestId,
            t,
            oSig,
            rSig,
            bSig
        );
        clone = CreditLoan(loanAddr);
    }

    function _currentBorrow(address loan) internal returns (uint256) {
        return IMTokenView(mUsdc).borrowBalanceCurrent(loan);
    }

    // ─── the simulation ──────────────────────────────────────────────

    /// For each collateral drop, a borrower with no further intent strategically
    /// defaults as early as possible (misses 2 interest installments). We then
    /// run the lender's full recovery (clawback → seizeAll → repay Moonwell →
    /// redeem) and report the lender's marketplace-specific PnL in USDC:
    ///   PnL = (interest received − USDC injected to repay Moonwell)
    ///         + (seized collateral valued at the crashed price)
    /// The pledged mUSDC + its supply yield are returned in full (no Moonwell
    /// liquidation here) and are the lender's always-on baseline, excluded.
    function test_riskReport_collateralCrashEarlyDefault() public {
        if (!_simEnabled()) {
            vm.skip(true);
            return;
        }
        uint16[7] memory drops = [0, 500, 1000, 1500, 2000, 3000, 5000];

        console.log("=================================================");
        console.log("SCENARIO 1: collateral crash + early strategic default");
        console.log(
            string.concat(
                " principal_usdc6=",
                vm.toString(PRINCIPAL),
                " collateral_cbbtc8=",
                vm.toString(collateral110),
                " loanApr_bps=",
                vm.toString(uint256(loanApr)),
                " btcusd_8dp=",
                vm.toString(uint256(_btcAnswer()))
            )
        );

        for (uint256 i = 0; i < drops.length; i++) {
            uint256 snap = vm.snapshot();
            int256 pnl = _earlyDefaultPnL(drops[i]);
            console.log(
                string.concat(
                    "drop_bps=",
                    vm.toString(uint256(drops[i])),
                    " | lender_pnl_usdc6=",
                    vm.toString(pnl),
                    " | pnl_pct_of_principal=",
                    vm.toString((pnl * 10000) / int256(PRINCIPAL)),
                    "bps",
                    pnl < 0 ? " | LENDER LOSS" : " | ok"
                )
            );
            vm.revertTo(snap);
        }
    }

    /// Returns lender marketplace PnL (USDC 6dp, signed) for an early default at
    /// `dropBps` collateral crash.
    function _earlyDefaultPnL(uint16 dropBps) internal returns (int256) {
        // Clear any feed mocks left over from a prior scenario (revertTo does
        // not clear vm.mockCall) so origination prices against the real feed.
        vm.clearMockedCalls();
        uint64 firstDueAt = uint64(block.timestamp + INTERVAL);
        CreditLoan clone = _originate(firstDueAt);

        // Give the lender a large USDC stash to fund the Moonwell repay; track
        // the net delta (interest in − repay out).
        uint256 stash = 1_000_000e6;
        deal(usdc, lender, stash);
        uint256 usdc0 = IERC20(usdc).balanceOf(lender);
        uint256 cbbtc0 = IERC20(cbbtc).balanceOf(lender);

        // Borrower pays nothing and misses cursor 0 and 1 → Defaulted.
        int256 crashed = _crashCollateral(dropBps);
        vm.warp(firstDueAt + GRACE + 1);
        _crashCollateral(dropBps);
        _refreshUsdcFeed();
        clone.claimMissedPayment();
        vm.warp(firstDueAt + INTERVAL + GRACE + 1);
        _crashCollateral(dropBps);
        _refreshUsdcFeed();
        clone.claimMissedPayment();
        require(clone.status() == LoanStatus.Defaulted, "not defaulted");

        // Lender seizes remaining collateral, repays the Moonwell borrow in
        // full, redeems the pledged mUSDC.
        vm.startPrank(lender);
        clone.seizeAll();
        uint256 owed = _currentBorrow(address(clone));
        IERC20(usdc).approve(address(clone), owed + 1e6);
        clone.repayLoanAfterDefault(owed + 1e6);
        clone.redeemAndReturn();
        vm.stopPrank();

        uint256 usdc1 = IERC20(usdc).balanceOf(lender);
        uint256 seizedUnits = IERC20(cbbtc).balanceOf(lender) - cbbtc0;
        // collateral value (USDC 6dp) = units(8dp) * crashedAnswer(8dp) / 1e10
        uint256 colUsdc = (seizedUnits * uint256(crashed)) / 1e10;

        int256 deltaUsdc = int256(usdc1) - int256(usdc0); // interest − repay
        return deltaUsdc + int256(colUsdc);
    }

    /// Baseline: borrower repays fully. Reports the lender's marketplace PnL
    /// (interest spread net of Moonwell borrow accrual) for one happy loan.
    function test_riskReport_happyPathBaseline() public {
        if (!_simEnabled()) {
            vm.skip(true);
            return;
        }
        uint64 firstDueAt = uint64(block.timestamp + INTERVAL);
        CreditLoan clone = _originate(firstDueAt);

        uint256 lenderUsdc0 = IERC20(usdc).balanceOf(lender);
        uint256 feeRec0 = IERC20(usdc).balanceOf(feeRecipient);

        deal(usdc, borrower, FINAL_AMT * 2);
        vm.prank(borrower);
        IERC20(usdc).approve(address(clone), type(uint256).max);
        for (uint32 i = 0; i < NUM_INTEREST; i++) {
            vm.warp(firstDueAt + uint64(i) * INTERVAL);
            vm.prank(borrower);
            clone.makePayment();
        }
        vm.warp(firstDueAt + uint64(NUM_INTEREST) * INTERVAL - 1);
        vm.prank(borrower);
        clone.makePayment();
        require(clone.status() == LoanStatus.Settled, "not settled");

        uint256 grossInterest = NUM_INTEREST * INTEREST_AMT + INTEREST_AMT; // 50 USDC
        int256 lenderInterest = int256(
            IERC20(usdc).balanceOf(lender) - lenderUsdc0
        );
        int256 fee = int256(IERC20(usdc).balanceOf(feeRecipient) - feeRec0);
        int256 moonwellAccrual = int256(grossInterest) - lenderInterest - fee;

        console.log("=================================================");
        console.log("SCENARIO 0: happy path (full repay)");
        console.log(
            string.concat(
                " gross_interest_usdc6=",
                vm.toString(grossInterest),
                " lender_interest=",
                vm.toString(lenderInterest),
                " fee=",
                vm.toString(fee),
                " moonwell_accrual=",
                vm.toString(moonwellAccrual),
                " loanApr_bps=",
                vm.toString(uint256(loanApr))
            )
        );
    }
}
