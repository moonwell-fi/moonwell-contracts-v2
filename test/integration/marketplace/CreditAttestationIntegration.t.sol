// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {stdJson} from "@forge-std/StdJson.sol";
import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

import {CreditLoan} from "@protocol/marketplace/CreditLoan.sol";
import {CreditMarketplaceFactory} from "@protocol/marketplace/CreditMarketplaceFactory.sol";
import {CreditTierRegistry} from "@protocol/marketplace/CreditTierRegistry.sol";
import {Offer, OfferStatus, Request, RequestStatus, BackendTerms, PaymentSchedule, LoanStatus, CreditAttestation} from "@protocol/marketplace/CreditTypes.sol";

import {Signers} from "@test/unit/marketplace/Signers.sol";

interface IMErc20Mint {
    function mint(uint256 amount) external returns (uint256);
}

interface IMTokenBorrowRate {
    function borrowRatePerTimestamp() external view returns (uint256);
}

/// A genuinely non-Moonwell collateral token (a stand-in for a long-tail /
/// gold-backed asset). 18 decimals so the marketplace's decimal scaling is
/// exercised on a different width than cbBTC's 8.
contract MockCollateral is ERC20 {
    uint8 private immutable _dec;

    constructor(uint8 d) ERC20("Gold Stand-in", "XAUx") {
        _dec = d;
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// Phase 2a end-to-end on a forked Base with real Moonwell: a credit-bureau
/// EIP-712 `CreditAttestation` is verified on-chain by
/// `CreditTierRegistry.setTierFromAttestation`, which writes the borrower's
/// tier; the factory's existing tier-gate then lets a tier-gated,
/// overcollateralized loan originate, settle, or default+seize. Also covers a
/// genuinely non-Moonwell collateral asset (mock 18-dec token priced by the
/// real Base XAU/USD Chainlink feed): not-whitelisted reverts, origination,
/// and under-collateralization.
///
/// The committed fixture (`fixtures/credit_attestation.json`) is signed for a
/// FIXED `verifyingContract` (REGISTRY_ADDR) + chainId 8453 + attestor (anvil
/// #0), so the registry is deployed at that deterministic address via
/// `deployCodeTo` (which runs the constructor with `address(this) == where`,
/// making the registry's in-constructor DOMAIN_SEPARATOR match the fixture).
contract CreditAttestationIntegration is Test, Signers {
    using stdJson for string;

    /// Deterministic registry address the fixture is signed against. If you
    /// change this, regenerate the fixture (see fixtures README).
    address internal constant REGISTRY_ADDR =
        0x00000000000000000000000000000000C0FFEE01;

    /// Bureau attestor = anvil account #0 (TEST ONLY — never a real key).
    address internal constant ATTESTOR =
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 internal constant ATTESTOR_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    /// Borrower / attestation subject = anvil account #2 (TEST ONLY). Must
    /// equal the fixture `subject` so the Request signature recovers it.
    uint256 internal constant BORROWER_KEY =
        0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;

    /// Real Base XAU/USD Chainlink feed (8 decimals) — prices the mock
    /// non-Moonwell collateral.
    address internal constant GOLD_FEED =
        0x5213eBB69743b85644dbB6E25cdF994aFBb8cF31;

    uint16 internal constant GATE_TIER = 4; // prime

    Addresses internal addresses;

    CreditLoan internal loanImpl;
    CreditMarketplaceFactory internal factory;
    CreditTierRegistry internal tierRegistry;
    address internal tierRegistryOwner;
    MockCollateral internal goldToken;

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
    /// Loan APR (bps), computed from Moonwell's live USDC borrow rate so the
    /// on-chain APR floor clears regardless of the (unpinned) fork block's
    /// utilization. apr is otherwise inert — payment amounts come from the
    /// schedule, not apr.
    uint16 internal loanApr;

    uint256 internal constant LENDER_USDC_SUPPLY = 1_000e6;
    uint256 internal constant PRINCIPAL = 400e6;
    uint256 internal constant INTEREST_AMT = 10e6;
    uint256 internal constant FINAL_AMT = PRINCIPAL + INTEREST_AMT;
    uint32 internal constant NUM_INTEREST = 4;
    uint32 internal constant INTERVAL = 7 days;
    uint256 internal constant COLLATERAL_AMOUNT = 1e7; // 0.1 cbBTC
    uint32 internal constant GRACE = 1 days;
    uint16 internal constant FEE_BPS = 500;
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
        tierRegistryOwner = makeAddr("tierRegistryOwner");
        (backendSignerEOA, backendSignerKey) = makeAddrAndKey("backend");
        (lender, lenderKey) = makeAddrAndKey("lender");
        borrower = vm.addr(BORROWER_KEY); // anvil #2 — the fixture subject

        goldToken = new MockCollateral(18);

        // Deploy the registry at the deterministic address the fixture is
        // signed against. deployCodeTo runs the constructor with
        // address(this) == REGISTRY_ADDR, so DOMAIN_SEPARATOR binds it.
        deployCodeTo(
            "CreditTierRegistry.sol:CreditTierRegistry",
            abi.encode(tierRegistryOwner),
            REGISTRY_ADDR
        );
        tierRegistry = CreditTierRegistry(REGISTRY_ADDR);

        loanImpl = new CreditLoan();
        factory = new CreditMarketplaceFactory(
            temporalGovernor,
            unitroller,
            address(loanImpl),
            backendSignerEOA,
            feeRecipient,
            pauseGuardian,
            REGISTRY_ADDR
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
            3_600
        );
        factory.setMinOriginationLtvBufferBps(1_000);
        factory.setDefaultParams(GRACE, OVER_SEIZURE_BPS, 2, FEE_BPS);
        vm.stopPrank();

        vm.prank(tierRegistryOwner);
        tierRegistry.setCreditBureauAttestor(ATTESTOR);

        // Lender supplies USDC into Moonwell, receives real mUSDC.
        deal(usdc, lender, LENDER_USDC_SUPPLY);
        vm.startPrank(lender);
        IERC20(usdc).approve(mUsdc, LENDER_USDC_SUPPLY);
        require(
            IMErc20Mint(mUsdc).mint(LENDER_USDC_SUPPLY) == 0,
            "mint failed"
        );
        vm.stopPrank();

        // Read the live Moonwell USDC borrow rate AFTER the supply mint (the
        // utilization the clone's borrow will face), then price the loan APR
        // just above it so _checkAprFloor passes at any fork block.
        loanApr = _aprAboveMoonwell();

        deal(cbbtc, borrower, COLLATERAL_AMOUNT);

        vm.prank(lender);
        IERC20(mUsdc).approve(address(factory), type(uint256).max);
        vm.prank(borrower);
        IERC20(cbbtc).approve(address(factory), type(uint256).max);
    }

    // ─── attestation + oracle helpers ────────────────────────────────

    function _loadFixture()
        internal
        view
        returns (CreditAttestation memory att, bytes memory sig)
    {
        string memory path = string.concat(
            vm.projectRoot(),
            "/test/integration/marketplace/fixtures/credit_attestation.json"
        );
        string memory j = vm.readFile(path);
        att = CreditAttestation({
            subject: j.readAddress(".subject"),
            tier: uint16(j.readUint(".tier")),
            score: uint16(j.readUint(".score")),
            reportHash: j.readBytes32(".reportHash"),
            issuedAt: uint64(j.readUint(".issuedAt")),
            validUntil: uint64(j.readUint(".validUntil"))
        });
        sig = j.readBytes(".signature");
    }

    /// Attest the borrower at `GATE_TIER` via vm.sign (no disk fixture).
    function _attestPrime() internal {
        CreditAttestation memory att = CreditAttestation({
            subject: borrower,
            tier: GATE_TIER,
            score: 800,
            reportHash: keccak256("vm-sign-report"),
            issuedAt: uint64(block.timestamp),
            validUntil: uint64(block.timestamp + 1 hours)
        });
        tierRegistry.setTierFromAttestation(
            att,
            signCreditAttestation(
                att,
                ATTESTOR_KEY,
                tierRegistry.DOMAIN_SEPARATOR()
            )
        );
    }

    /// Re-stamp a real Chainlink feed's `updatedAt` to the current block so
    /// the clone's staleness check passes after we've warped time forward.
    function _restampFeed(address f) internal {
        (uint80 r, int256 a, uint256 s, , uint80 ar) = AggregatorV3Interface(f)
            .latestRoundData();
        vm.mockCall(
            f,
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(r, a, s, block.timestamp, ar)
        );
    }

    function _refreshOracle() internal {
        _restampFeed(btcUsdFeed);
        _restampFeed(usdcOracle);
    }

    function _currentBorrow(address loan) internal returns (uint256) {
        (bool ok, bytes memory data) = mUsdc.call(
            abi.encodeWithSignature("borrowBalanceCurrent(address)", loan)
        );
        require(ok, "borrowBalanceCurrent failed");
        return abi.decode(data, (uint256));
    }

    function _lenderMTokenBalance() internal view returns (uint256) {
        return IERC20(mUsdc).balanceOf(lender);
    }

    /// Smallest loan APR (bps) that clears _checkAprFloor (buffer = 0), plus a
    /// 1% margin. Inverts the factory's conversion:
    /// marketplaceRatePerSec = aprBps * 1e14 / 365 days >= moonwellRatePerSec.
    function _aprAboveMoonwell() internal view returns (uint16) {
        uint256 ratePerSec = IMTokenBorrowRate(mUsdc).borrowRatePerTimestamp();
        uint256 minBps = (ratePerSec * 365 days) / 1e14;
        uint256 aprBps = minBps + 100; // +1% over the live Moonwell rate
        require(aprBps <= 65535, "moonwell borrow APR too high for uint16");
        return uint16(aprBps);
    }

    // ─── match builders (collateral-parametrized) ────────────────────

    function _offerGated(
        uint256 mTokenAmount,
        address collToken
    ) internal view returns (Offer memory o) {
        address[] memory col = new address[](1);
        col[0] = collToken;
        o = Offer({
            lender: lender,
            mToken: mUsdc,
            mTokenAmount: mTokenAmount,
            principalToken: usdc,
            maxPrincipal: 500e6,
            maxApr: loanApr,
            minApr: 0,
            minTerm: 1 days,
            maxTerm: 60 days,
            acceptedCollateral: col,
            minBorrowerCreditTier: GATE_TIER, // prime-only
            expiresAt: uint64(block.timestamp + 1 hours),
            nonce: 1,
            status: OfferStatus.Active
        });
    }

    function _requestFor(
        address collToken,
        uint256 collAmount
    ) internal view returns (Request memory r) {
        r = Request({
            borrower: borrower,
            principalToken: usdc,
            principal: PRINCIPAL,
            collateralToken: collToken,
            collateralAmount: collAmount,
            maxApr: loanApr,
            minTerm: 1 days,
            maxTerm: 60 days,
            expiresAt: uint64(block.timestamp + 1 hours),
            nonce: 2,
            status: RequestStatus.Active
        });
    }

    function _termsFor(
        uint256 mTokenAmount,
        uint64 firstDueAt,
        address collToken,
        uint256 collAmount
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
            loanNonce: 3,
            lender: lender,
            borrower: borrower,
            mToken: mUsdc,
            mTokenAmount: mTokenAmount,
            principalToken: usdc,
            principal: PRINCIPAL,
            collateralToken: collToken,
            collateralAmount: collAmount,
            apr: loanApr,
            term: 30 days,
            schedule: s,
            gracePeriod: GRACE,
            overSeizureBps: OVER_SEIZURE_BPS,
            consecutiveMissesForDefault: 2,
            marketplaceFeeBps: FEE_BPS,
            feeRecipient: feeRecipient,
            borrowerCreditTier: GATE_TIER, // must == registry tier (exact match)
            issuedAt: uint64(block.timestamp),
            validUntil: uint64(block.timestamp + 1 hours)
        });
    }

    /// Post the gated offer + request + backend terms and match. Named sig
    /// locals stay under the stack limit at optimizer_runs=1.
    function _matchGated(
        uint256 mTokenAmount,
        uint64 firstDueAt,
        address collToken,
        uint256 collAmount
    ) internal returns (address loanAddr) {
        bytes32 domain = factory.DOMAIN_SEPARATOR();
        Offer memory o = _offerGated(mTokenAmount, collToken);
        Request memory r = _requestFor(collToken, collAmount);
        BackendTerms memory t = _termsFor(
            mTokenAmount,
            firstDueAt,
            collToken,
            collAmount
        );
        uint256 offerId = factory.postOffer(o, signOffer(o, lenderKey, domain));
        uint256 requestId = factory.postRequest(
            r,
            signRequest(r, BORROWER_KEY, domain)
        );
        bytes memory oSig = signOffer(o, lenderKey, domain);
        bytes memory rSig = signRequest(r, BORROWER_KEY, domain);
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

    /// Same posting flow but expects createLoan to revert with `selector`.
    function _matchGatedExpectRevert(
        uint256 mTokenAmount,
        uint64 firstDueAt,
        address collToken,
        uint256 collAmount,
        bytes4 selector
    ) internal {
        bytes32 domain = factory.DOMAIN_SEPARATOR();
        Offer memory o = _offerGated(mTokenAmount, collToken);
        Request memory r = _requestFor(collToken, collAmount);
        BackendTerms memory t = _termsFor(
            mTokenAmount,
            firstDueAt,
            collToken,
            collAmount
        );
        uint256 offerId = factory.postOffer(o, signOffer(o, lenderKey, domain));
        uint256 requestId = factory.postRequest(
            r,
            signRequest(r, BORROWER_KEY, domain)
        );
        bytes memory oSig = signOffer(o, lenderKey, domain);
        bytes memory rSig = signRequest(r, BORROWER_KEY, domain);
        bytes memory bSig = signBackendTerms(t, backendSignerKey, domain);
        // try/catch + selector compare: robust against parametrized custom
        // errors (InsufficientCollateral carries non-deterministic live-price
        // args, so vm.expectRevert(bytes4) can't match it across fork blocks).
        try
            factory.createLoan(offerId, requestId, t, oSig, rSig, bSig)
        returns (uint256, address) {
            revert("expected createLoan to revert");
        } catch (bytes memory reason) {
            assertEq(bytes4(reason), selector, "wrong revert selector");
        }
    }

    function _runPaymentLoopToSettle(
        CreditLoan clone,
        uint64 firstDueAt
    ) internal {
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
        assertTrue(clone.status() == LoanStatus.Settled);
    }

    // ─── happy-path e2e ──────────────────────────────────────────────

    /// THE e2e test: API-minted attestation fixture → on-chain verify → tier
    /// written → tier-gated overcollateralized loan originates and settles.
    function test_attestationFixture_writesTier_andGatedLoanSettles() public {
        (CreditAttestation memory att, bytes memory sig) = _loadFixture();
        assertEq(att.subject, borrower, "fixture subject must equal borrower");
        assertEq(att.tier, GATE_TIER, "fixture tier must equal gate");
        assertLe(att.issuedAt, block.timestamp);
        assertGt(att.validUntil, block.timestamp);

        tierRegistry.setTierFromAttestation(att, sig);
        assertEq(tierRegistry.tier(borrower), GATE_TIER);
        assertEq(tierRegistry.tierAttestedAt(borrower), att.issuedAt);

        uint256 mAmt = _lenderMTokenBalance();
        uint64 firstDueAt = uint64(block.timestamp + INTERVAL);
        // Assert the DELTA, not the absolute balance: the borrower (anvil #2) is
        // a real Base EOA that holds USDC dust on the unpinned fork, so an
        // absolute `== PRINCIPAL` check is fork-block-dependent. The contract
        // forwards exactly PRINCIPAL (CreditLoan.activate).
        uint256 borrowerUsdcBefore = IERC20(usdc).balanceOf(borrower);
        CreditLoan clone = CreditLoan(
            _matchGated(mAmt, firstDueAt, cbbtc, COLLATERAL_AMOUNT)
        );
        assertTrue(clone.status() == LoanStatus.Active);
        assertEq(
            IERC20(usdc).balanceOf(borrower) - borrowerUsdcBefore,
            PRINCIPAL,
            "principal sent"
        );
        _runPaymentLoopToSettle(clone, firstDueAt);
        assertEq(
            IERC20(cbbtc).balanceOf(borrower),
            COLLATERAL_AMOUNT,
            "collateral returned on settle"
        );
    }

    /// Control: same flow but the attestation is signed in-test with vm.sign.
    function test_control_vmSign_writesTier_andGatedLoanSettles() public {
        _attestPrime();
        assertEq(tierRegistry.tier(borrower), GATE_TIER);

        uint256 mAmt = _lenderMTokenBalance();
        uint64 firstDueAt = uint64(block.timestamp + INTERVAL);
        CreditLoan clone = CreditLoan(
            _matchGated(mAmt, firstDueAt, cbbtc, COLLATERAL_AMOUNT)
        );
        assertTrue(clone.status() == LoanStatus.Active);
        _runPaymentLoopToSettle(clone, firstDueAt);
    }

    // ─── attestation negative controls ───────────────────────────────

    /// Re-submitting the same fixture reverts (monotonic issuedAt guard).
    function test_fixtureReplay_reverts() public {
        (CreditAttestation memory att, bytes memory sig) = _loadFixture();
        tierRegistry.setTierFromAttestation(att, sig);
        vm.expectRevert(
            abi.encodeWithSelector(
                CreditTierRegistry.StaleAttestation.selector,
                att.issuedAt,
                att.issuedAt
            )
        );
        tierRegistry.setTierFromAttestation(att, sig);
    }

    /// Tampering a NON-cap field (score) after signing must fail the
    /// signature check — proves the signature binds the full attestation,
    /// not just the tier. (Bumping the tier would trip TierTooHigh first,
    /// which is covered separately in the registry unit suite at 3→4.)
    function test_fixtureTamperedScore_revertsBadSignature() public {
        (CreditAttestation memory att, bytes memory sig) = _loadFixture();
        att.score = att.score + 1;
        vm.expectRevert(
            CreditTierRegistry.InvalidAttestationSignature.selector
        );
        tierRegistry.setTierFromAttestation(att, sig);
    }

    // ─── seizure / default + partial & full unwind ───────────────────

    /// Attested-prime loan, partially repaid (one installment), then misses
    /// into default: progressive cbBTC clawback → seizeAll → the lender
    /// unwinds the Moonwell debt across multiple partial repays (with the
    /// borrower's pre-default interest applied per ACCT-02) → redeem.
    function test_attestedLoan_default_seize_partialAndFullUnwind() public {
        _attestPrime();
        uint256 mAmt = _lenderMTokenBalance();
        uint64 firstDueAt = uint64(block.timestamp + INTERVAL);
        CreditLoan clone = CreditLoan(
            _matchGated(mAmt, firstDueAt, cbbtc, COLLATERAL_AMOUNT)
        );

        // Borrower pays the first interest installment, leaving 10 USDC of
        // pre-default interest in the clone.
        deal(usdc, borrower, FINAL_AMT * 2);
        vm.prank(borrower);
        IERC20(usdc).approve(address(clone), type(uint256).max);
        vm.warp(firstDueAt);
        vm.prank(borrower);
        clone.makePayment();
        assertEq(clone.paymentCursor(), 1);
        assertEq(
            IERC20(usdc).balanceOf(address(clone)),
            INTEREST_AMT,
            "pre-default interest sits in clone"
        );

        // Miss cursor 1 → progressive clawback seizes cbBTC.
        vm.warp(firstDueAt + INTERVAL + GRACE + 1);
        _refreshOracle();
        clone.claimMissedPayment();
        assertEq(clone.missedCount(), 1);
        assertGt(clone.seizedCollateralAmount(), 0, "progressive seize");
        assertTrue(clone.status() == LoanStatus.Active);

        // Miss cursor 2 → threshold reached → Defaulted.
        vm.warp(firstDueAt + 2 * INTERVAL + GRACE + 1);
        _refreshOracle();
        clone.claimMissedPayment();
        assertEq(clone.missedCount(), 2);
        assertTrue(clone.status() == LoanStatus.Defaulted);

        // Lender seizes the remaining collateral.
        uint256 lenderCbbtcBefore = IERC20(cbbtc).balanceOf(lender);
        uint256 remaining = COLLATERAL_AMOUNT - clone.seizedCollateralAmount();
        vm.prank(lender);
        clone.seizeAll();
        assertTrue(clone.status() == LoanStatus.Closed);
        assertEq(
            IERC20(cbbtc).balanceOf(lender) - lenderCbbtcBefore,
            remaining
        );

        // ACCT-02: the borrower's pre-default interest is applied to the
        // Moonwell debt (lender supplies no top-up here).
        uint256 owedBefore = _currentBorrow(address(clone));
        vm.prank(lender);
        clone.repayLoanAfterDefault(0);
        assertEq(
            IERC20(usdc).balanceOf(address(clone)),
            0,
            "pre-default interest consumed by repay"
        );
        assertLt(_currentBorrow(address(clone)), owedBefore, "debt reduced");

        // Lender unwinds the rest: a PARTIAL repay first, then the remainder.
        deal(usdc, lender, PRINCIPAL * 2);
        vm.startPrank(lender);
        IERC20(usdc).approve(address(clone), type(uint256).max);
        uint256 half = _currentBorrow(address(clone)) / 2;
        clone.repayLoanAfterDefault(half);
        assertGt(_currentBorrow(address(clone)), 0, "partial leaves debt open");
        uint256 rem = _currentBorrow(address(clone));
        clone.repayLoanAfterDefault(rem + 1e6); // small overpay covers nothing extra (same block)
        vm.stopPrank();
        assertEq(_currentBorrow(address(clone)), 0, "fully repaid");

        // Lender redeems pledged mUSDC (+ supply yield); any residual USDC is
        // swept back to the lender (ACCT-02), clone fully drained.
        uint256 lenderMBefore = IERC20(mUsdc).balanceOf(lender);
        vm.prank(lender);
        clone.redeemAndReturn();
        assertGe(IERC20(mUsdc).balanceOf(lender) - lenderMBefore, mAmt);
        assertEq(IERC20(mUsdc).balanceOf(address(clone)), 0);
        assertEq(IERC20(usdc).balanceOf(address(clone)), 0, "residual swept");
    }

    // ─── non-Moonwell (gold-priced) collateral ───────────────────────

    /// A non-whitelisted collateral can't be posted on the offer side.
    function test_nonMoonwellCollateral_notWhitelisted_postOfferReverts()
        public
    {
        Offer memory o = _offerGated(
            _lenderMTokenBalance(),
            address(goldToken)
        );
        bytes memory oSig = signOffer(o, lenderKey, factory.DOMAIN_SEPARATOR());
        vm.expectRevert(
            CreditMarketplaceFactory.NotCollateralWhitelisted.selector
        );
        factory.postOffer(o, oSig);
    }

    /// ...nor on the request side.
    function test_nonMoonwellCollateral_notWhitelisted_postRequestReverts()
        public
    {
        Request memory r = _requestFor(address(goldToken), 1e18);
        bytes memory rSig = signRequest(
            r,
            BORROWER_KEY,
            factory.DOMAIN_SEPARATOR()
        );
        vm.expectRevert(
            CreditMarketplaceFactory.NotCollateralWhitelisted.selector
        );
        factory.postRequest(r, rSig);
    }

    /// Once governance whitelists the gold token with the real XAU/USD feed,
    /// a loan collateralized by it (18-dec token, ~$4.5k/oz) originates and
    /// settles — exercising a genuinely non-Moonwell asset + 18-dec scaling.
    function test_nonMoonwellCollateral_gold_originatesAndSettles() public {
        vm.prank(temporalGovernor);
        factory.whitelistCollateralToken(
            address(goldToken),
            true,
            AggregatorV3Interface(GOLD_FEED),
            uint32(1 days)
        );
        _attestPrime();

        uint256 goldAmt = 1e18; // 1 oz ≈ $4,469 ≫ $440 required
        goldToken.mint(borrower, goldAmt);
        vm.prank(borrower);
        goldToken.approve(address(factory), type(uint256).max);

        uint256 mAmt = _lenderMTokenBalance();
        uint64 firstDueAt = uint64(block.timestamp + INTERVAL);
        CreditLoan clone = CreditLoan(
            _matchGated(mAmt, firstDueAt, address(goldToken), goldAmt)
        );
        assertTrue(clone.status() == LoanStatus.Active);
        assertEq(clone.collateralAmount(), goldAmt);
        assertEq(goldToken.balanceOf(address(clone)), goldAmt);

        _runPaymentLoopToSettle(clone, firstDueAt);
        assertEq(goldToken.balanceOf(borrower), goldAmt, "gold returned");
    }

    /// Gold collateral worth less than 110% of the principal is rejected by
    /// the on-chain origination LTV check.
    function test_nonMoonwellCollateral_gold_underCollateralizedReverts()
        public
    {
        vm.prank(temporalGovernor);
        factory.whitelistCollateralToken(
            address(goldToken),
            true,
            AggregatorV3Interface(GOLD_FEED),
            uint32(1 days)
        );
        _attestPrime();

        uint256 goldAmt = 0.05e18; // 0.05 oz ≈ $223 < $440 required
        goldToken.mint(borrower, goldAmt);
        vm.prank(borrower);
        goldToken.approve(address(factory), type(uint256).max);

        _matchGatedExpectRevert(
            _lenderMTokenBalance(),
            uint64(block.timestamp + INTERVAL),
            address(goldToken),
            goldAmt,
            CreditMarketplaceFactory.InsufficientCollateral.selector
        );
    }
}
