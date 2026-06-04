// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {stdJson} from "@forge-std/StdJson.sol";
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

/// Phase 2a end-to-end on a forked Base with real Moonwell: a credit-bureau
/// EIP-712 `CreditAttestation` (minted off-chain by the moonwell-ai Worker)
/// is verified on-chain by `CreditTierRegistry.setTierFromAttestation`, which
/// writes the borrower's tier; the factory's existing tier-gate then lets a
/// tier-gated, overcollateralized loan originate and settle.
///
/// The committed fixture (`fixtures/credit_attestation.json`) is signed for a
/// FIXED `verifyingContract` (REGISTRY_ADDR) + chainId 8453 + attestor (anvil
/// #0), so the registry is deployed at that deterministic address via
/// `deployCodeTo` (which runs the constructor with `address(this) == where`,
/// making the registry's in-constructor DOMAIN_SEPARATOR match the fixture).
/// The borrower / attestation `subject` is anvil #2 so the test can sign its
/// Request. `test_control_*` re-proves the verify path with `vm.sign`,
/// independent of the off-chain fixture.
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

    uint16 internal constant GATE_TIER = 4; // prime

    Addresses internal addresses;

    CreditLoan internal loanImpl;
    CreditMarketplaceFactory internal factory;
    CreditTierRegistry internal tierRegistry;
    address internal tierRegistryOwner;

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

        deal(cbbtc, borrower, COLLATERAL_AMOUNT);

        vm.prank(lender);
        IERC20(mUsdc).approve(address(factory), type(uint256).max);
        vm.prank(borrower);
        IERC20(cbbtc).approve(address(factory), type(uint256).max);
    }

    // ─── helpers ─────────────────────────────────────────────────────

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

    function _lenderMTokenBalance() internal view returns (uint256) {
        return IERC20(mUsdc).balanceOf(lender);
    }

    function _offerTierGated(
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
            minBorrowerCreditTier: GATE_TIER, // ← only prime borrowers
            expiresAt: uint64(block.timestamp + 1 hours),
            nonce: 1,
            status: OfferStatus.Active
        });
    }

    function _request() internal view returns (Request memory r) {
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
            nonce: 2,
            status: RequestStatus.Active
        });
    }

    function _terms(
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
            loanNonce: 3,
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
            borrowerCreditTier: GATE_TIER, // must == registry tier (exact match)
            issuedAt: uint64(block.timestamp),
            validUntil: uint64(block.timestamp + 1 hours)
        });
    }

    /// Post the tier-gated offer + request + backend terms and match.
    /// Named sig locals mirror the sibling integration harness to stay under
    /// the stack limit at optimizer_runs=1.
    function _matchTierGated(
        uint256 mTokenAmount,
        uint64 firstDueAt
    ) internal returns (address loanAddr) {
        bytes32 domain = factory.DOMAIN_SEPARATOR();
        Offer memory o = _offerTierGated(mTokenAmount);
        Request memory r = _request();
        BackendTerms memory t = _terms(mTokenAmount, firstDueAt);

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

    // ─── tests ───────────────────────────────────────────────────────

    /// THE e2e test: API-minted attestation fixture → on-chain verify → tier
    /// written → tier-gated overcollateralized loan originates and settles.
    function test_attestationFixture_writesTier_andGatedLoanSettles() public {
        (CreditAttestation memory att, bytes memory sig) = _loadFixture();
        assertEq(att.subject, borrower, "fixture subject must equal borrower");
        assertEq(att.tier, GATE_TIER, "fixture tier must equal gate");
        // Fixture validity window [issuedAt, validUntil) must contain the
        // fork timestamp (wide window in the bootstrap fixture).
        assertLe(att.issuedAt, block.timestamp);
        assertGt(att.validUntil, block.timestamp);

        // 1) Verify the bureau signature on-chain and write the tier.
        tierRegistry.setTierFromAttestation(att, sig);
        assertEq(tierRegistry.tier(borrower), GATE_TIER);
        assertEq(tierRegistry.tierAttestedAt(borrower), att.issuedAt);

        // 2) A prime-only offer now matches this borrower and settles.
        uint256 mAmt = _lenderMTokenBalance();
        uint64 firstDueAt = uint64(block.timestamp + INTERVAL);
        CreditLoan clone = CreditLoan(_matchTierGated(mAmt, firstDueAt));
        assertTrue(clone.status() == LoanStatus.Active);
        assertEq(IERC20(usdc).balanceOf(borrower), PRINCIPAL, "principal sent");
        _runPaymentLoopToSettle(clone, firstDueAt);
        assertEq(
            IERC20(cbbtc).balanceOf(borrower),
            COLLATERAL_AMOUNT,
            "collateral returned on settle"
        );
    }

    /// Control: same flow but the attestation is signed in-test with
    /// vm.sign. Isolates contract correctness from the off-chain fixture —
    /// if the fixture test fails but this passes, the bug is in the
    /// off-chain domain inputs, not the contract.
    function test_control_vmSign_writesTier_andGatedLoanSettles() public {
        CreditAttestation memory att = CreditAttestation({
            subject: borrower,
            tier: GATE_TIER,
            score: 800,
            reportHash: keccak256("control-report"),
            issuedAt: uint64(block.timestamp),
            validUntil: uint64(block.timestamp + 1 hours)
        });
        bytes memory sig = signCreditAttestation(
            att,
            ATTESTOR_KEY,
            tierRegistry.DOMAIN_SEPARATOR()
        );

        tierRegistry.setTierFromAttestation(att, sig);
        assertEq(tierRegistry.tier(borrower), GATE_TIER);

        uint256 mAmt = _lenderMTokenBalance();
        uint64 firstDueAt = uint64(block.timestamp + INTERVAL);
        CreditLoan clone = CreditLoan(_matchTierGated(mAmt, firstDueAt));
        assertTrue(clone.status() == LoanStatus.Active);
        _runPaymentLoopToSettle(clone, firstDueAt);
    }

    /// Negative control: re-submitting the same fixture reverts (monotonic
    /// issuedAt guard) — a stale higher-tier attestation can't be replayed.
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

    /// Negative control: bumping the tier after signing breaks the signature.
    function test_fixtureTamperedTier_reverts() public {
        (CreditAttestation memory att, bytes memory sig) = _loadFixture();
        att.tier = att.tier + 1; // would be out of band anyway, but sig binds it
        vm.expectRevert();
        tierRegistry.setTierFromAttestation(att, sig);
    }
}
