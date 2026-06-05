// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

import {CreditLoan} from "@protocol/marketplace/CreditLoan.sol";
import {CreditMarketplaceFactory} from "@protocol/marketplace/CreditMarketplaceFactory.sol";
import {Offer, OfferStatus, Request, RequestStatus, BackendTerms, PaymentSchedule, LoanStatus} from "@protocol/marketplace/CreditTypes.sol";

import {Fixture} from "./Fixture.t.sol";

/// Minimal Moonwell stand-ins so these unit tests exercise the factory's
/// match logic without hitting real Moonwell collateral / borrow caps /
/// interest accrual. Real-Moonwell integration lands in PR9.
contract MockComptroller {
    address public listedMarket;
    constructor(address _listedMarket) {
        listedMarket = _listedMarket;
    }
    function getAllMarkets() external view returns (address[] memory out) {
        out = new address[](1);
        out[0] = listedMarket;
    }
    function enterMarkets(
        address[] calldata
    ) external pure returns (uint256[] memory errs) {
        errs = new uint256[](1);
    }
}

contract MockMToken is ERC20 {
    address public immutable underlying;
    constructor(address _underlying) ERC20("MockMToken", "mMOCK") {
        underlying = _underlying;
    }
    function mintTo(address to, uint256 amount) external {
        _mint(to, amount);
    }
    function borrow(uint256 amount) external returns (uint256) {
        IERC20(underlying).transfer(msg.sender, amount);
        return 0;
    }
    /// Floor check needs a per-second borrow rate. Returning 0 means
    /// any positive marketplace APR clears the floor — fine for unit
    /// tests that don't exercise the floor branch.
    function borrowRatePerTimestamp() external pure returns (uint256) {
        return 0;
    }
}

contract MockPriceFeed {
    int256 public immutable answer;
    uint8 internal immutable _decimals;
    constructor(int256 _answer, uint8 d) {
        answer = _answer;
        _decimals = d;
    }
    function decimals() external view returns (uint8) {
        return _decimals;
    }
    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (0, answer, 0, block.timestamp, 0);
    }
}

contract CreateLoanTest is Fixture {
    event LoanCreated(
        uint256 indexed loanId,
        address indexed loanAddress,
        address indexed lender,
        address borrower,
        address mToken,
        uint256 mTokenAmount,
        address principalToken,
        uint256 principal,
        address collateralToken,
        uint256 collateralAmount,
        uint16 apr,
        uint32 term,
        uint16 marketplaceFeeBps,
        uint64 principalDueAt
    );

    MockComptroller internal mockComptroller;
    MockMToken internal mockMToken;
    MockPriceFeed internal usdcFeed;
    MockPriceFeed internal cbbtcFeed;
    CreditLoan internal localImpl;
    CreditMarketplaceFactory internal localFactory;

    /// In 1e18 USD space: collateral value must be ≥ principal * 110 / 100.
    /// Using amount=1e7 cbBTC at $100k ($10_000 value) and principal=400 USDC
    /// ($400 value), so collateral:principal = 25:1, well above the 1.1 floor.
    uint256 internal constant M_TOKEN_AMOUNT = 1_000e6;
    uint256 internal constant PRINCIPAL = 400e6;
    uint256 internal constant COLLATERAL_AMOUNT = 1e7;

    function setUp() public override {
        super.setUp();

        mockComptroller = new MockComptroller(mUsdc);
        mockMToken = new MockMToken(usdc);
        usdcFeed = new MockPriceFeed(1e8, 8); // $1 USDC
        cbbtcFeed = new MockPriceFeed(1e13, 8); // $100_000 cbBTC

        localImpl = new CreditLoan();
        localFactory = new CreditMarketplaceFactory(
            temporalGovernor,
            address(mockComptroller),
            address(localImpl),
            backendSignerEOA,
            feeRecipient,
            pauseGuardian,
            address(tierRegistry)
        );

        vm.startPrank(temporalGovernor);
        // setStalenessWindow first because whitelist setters reject any
        // per-feed staleness above the global cap.
        localFactory.setStalenessWindow(3_600);
        // whitelistMToken also registers the underlying's feed — one
        // call where the old interface needed two.
        localFactory.whitelistMToken(
            address(mockMToken),
            true,
            AggregatorV3Interface(address(usdcFeed)),
            3_600
        );
        localFactory.whitelistCollateralToken(
            cbbtc,
            true,
            AggregatorV3Interface(address(cbbtcFeed)),
            3_600
        );
        localFactory.setMinOriginationLtvBufferBps(1_000);
        vm.stopPrank();

        // Fund participants + mock mToken's borrow pool.
        mockMToken.mintTo(lender, M_TOKEN_AMOUNT);
        deal(cbbtc, borrower, COLLATERAL_AMOUNT);
        deal(usdc, address(mockMToken), PRINCIPAL * 10);

        vm.prank(lender);
        IERC20(address(mockMToken)).approve(
            address(localFactory),
            type(uint256).max
        );
        vm.prank(borrower);
        IERC20(cbbtc).approve(address(localFactory), type(uint256).max);
    }

    // ─── helpers ─────────────────────────────────────────────────────

    function _offer(uint256 nonce) internal view returns (Offer memory o) {
        address[] memory col = new address[](1);
        col[0] = cbbtc;
        o = Offer({
            lender: lender,
            mToken: address(mockMToken),
            mTokenAmount: M_TOKEN_AMOUNT,
            principalToken: usdc,
            maxPrincipal: 500e6,
            maxApr: 1_000,
            minApr: 500,
            minTerm: 1 days,
            maxTerm: 30 days,
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
            maxTerm: 30 days,
            expiresAt: uint64(block.timestamp + 1 hours),
            nonce: nonce,
            status: RequestStatus.Active
        });
    }

    function _terms(
        uint256 loanNonce
    ) internal view returns (BackendTerms memory t) {
        PaymentSchedule memory s;
        s.numInterestPayments = 4;
        s.intervalSeconds = 7 days;
        s.firstInterestDueAt = uint64(block.timestamp + 7 days);
        s.principalDueAt = uint64(block.timestamp + 35 days);
        s.interestAmountPerPayment = 10e6;
        s.finalPaymentAmount = PRINCIPAL + 10e6;

        t = BackendTerms({
            chainId: block.chainid,
            factory: address(localFactory),
            loanNonce: loanNonce,
            lender: lender,
            borrower: borrower,
            mToken: address(mockMToken),
            mTokenAmount: M_TOKEN_AMOUNT,
            principalToken: usdc,
            principal: PRINCIPAL,
            collateralToken: cbbtc,
            collateralAmount: COLLATERAL_AMOUNT,
            apr: 800,
            term: 30 days,
            schedule: s,
            gracePeriod: 1 days,
            overSeizureBps: 2_000,
            consecutiveMissesForDefault: 2,
            marketplaceFeeBps: 500,
            feeRecipient: feeRecipient,
            borrowerCreditTier: 0,
            issuedAt: uint64(block.timestamp),
            validUntil: uint64(block.timestamp + 1 hours)
        });
    }

    function _postMatchable(
        uint256 offerNonce,
        uint256 requestNonce
    )
        internal
        returns (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        )
    {
        o = _offer(offerNonce);
        r = _request(requestNonce);
        offerId = localFactory.postOffer(
            o,
            signOffer(o, lenderKey, localFactory.DOMAIN_SEPARATOR())
        );
        requestId = localFactory.postRequest(
            r,
            signRequest(r, borrowerKey, localFactory.DOMAIN_SEPARATOR())
        );
    }

    function _signedTerms(
        BackendTerms memory t
    ) internal view returns (bytes memory) {
        return
            signBackendTerms(
                t,
                backendSignerKey,
                localFactory.DOMAIN_SEPARATOR()
            );
    }

    function _offerSig(Offer memory o) internal view returns (bytes memory) {
        return signOffer(o, lenderKey, localFactory.DOMAIN_SEPARATOR());
    }

    function _requestSig(
        Request memory r
    ) internal view returns (bytes memory) {
        return signRequest(r, borrowerKey, localFactory.DOMAIN_SEPARATOR());
    }

    // ─── tests ───────────────────────────────────────────────────────

    function test_createLoan_happyPath() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);

        uint256 borrowerUsdcBefore = IERC20(usdc).balanceOf(borrower);

        (uint256 loanId, address loanAddr) = localFactory.createLoan(
            offerId,
            requestId,
            t,
            _offerSig(o),
            _requestSig(r),
            _signedTerms(t)
        );

        assertEq(loanId, 0);
        assertEq(localFactory.getLoan(loanId), loanAddr);
        assertEq(localFactory.nextLoanId(), 1);

        CreditLoan clone = CreditLoan(loanAddr);
        assertTrue(clone.status() == LoanStatus.Active);
        assertEq(clone.lender(), lender);
        assertEq(clone.borrower(), borrower);
        assertEq(clone.mToken(), address(mockMToken));
        assertEq(clone.principal(), PRINCIPAL);
        assertEq(clone.factory(), address(localFactory));
        assertEq(
            IERC20(address(mockMToken)).balanceOf(loanAddr),
            M_TOKEN_AMOUNT
        );
        assertEq(IERC20(cbbtc).balanceOf(loanAddr), COLLATERAL_AMOUNT);
        assertEq(
            IERC20(usdc).balanceOf(borrower) - borrowerUsdcBefore,
            PRINCIPAL
        );

        assertTrue(
            localFactory.getOffer(offerId).status == OfferStatus.Consumed
        );
        assertTrue(
            localFactory.getRequest(requestId).status == RequestStatus.Consumed
        );
        assertTrue(localFactory.isNonceUsed(lender, 1));
        assertTrue(localFactory.isNonceUsed(borrower, 2));
        assertTrue(localFactory.isNonceUsed(backendSignerEOA, 3));
    }

    function test_createLoan_emitsLoanCreated() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);

        // The signatures are computed (as args to the helper below) BEFORE the
        // helper's `expectEmit`. The sig helpers call the EIP-712 hashers, now
        // `public` deployed-library functions reached via delegatecall — i.e.
        // external calls. Evaluated inline after a pending expectEmit they would
        // be consumed by it (same gotcha as expectRevert + sig helpers), so the
        // emit would bind to a sig-helper call instead of createLoan. Routing
        // through `_expectLoanCreated` also moves the 14-arg emit into its own
        // frame, keeping this function under the optimizer_runs=1 stack limit.
        _expectLoanCreated(
            offerId,
            requestId,
            t,
            MatchSigs(_offerSig(o), _requestSig(r), _signedTerms(t))
        );
    }

    /// Carries the three match signatures as one stack slot so the
    /// emit-assertion helper stays under the optimizer_runs=1 stack limit.
    struct MatchSigs {
        bytes offer;
        bytes request;
        bytes backend;
    }

    /// Asserts `createLoan` emits `LoanCreated` with the matched offer/request
    /// data. The sigs in `s` are pre-evaluated by the caller (before this
    /// frame's `expectEmit`), so the expectation binds to `createLoan`, not a
    /// sig helper's delegatecall.
    function _expectLoanCreated(
        uint256 offerId,
        uint256 requestId,
        BackendTerms memory t,
        MatchSigs memory s
    ) internal {
        // Match all topics (loanId, loanAddress, lender) and full data:
        // mToken, mTokenAmount, principalToken, principal, collateralToken,
        // collateralAmount, apr, term, marketplaceFeeBps, principalDueAt.
        // loanAddress is the deterministic clone — match-by-topic with
        // checkData=true only when we know the address; here we leave
        // topic[1] unchecked and rely on the structural match elsewhere.
        vm.expectEmit(true, false, true, true, address(localFactory));
        emit LoanCreated(
            0,
            address(0), // unchecked (topic[1] not matched)
            lender,
            borrower,
            address(mockMToken),
            M_TOKEN_AMOUNT,
            usdc,
            PRINCIPAL,
            cbbtc,
            COLLATERAL_AMOUNT,
            800,
            30 days,
            500,
            t.schedule.principalDueAt
        );

        localFactory.createLoan(
            offerId,
            requestId,
            t,
            s.offer,
            s.request,
            s.backend
        );
    }

    function test_createLoan_whenPausedReverts() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        vm.prank(pauseGuardian);
        localFactory.pause();

        vm.expectRevert("Pausable: paused");
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    function test_createLoan_offerNotActiveReverts() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        bytes memory cancelSig = signOfferCancel(
            offerId,
            lender,
            o.nonce,
            lenderKey,
            localFactory.DOMAIN_SEPARATOR()
        );
        localFactory.cancelOffer(offerId, cancelSig);

        BackendTerms memory t = _terms(3);
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        vm.expectRevert(CreditMarketplaceFactory.OfferNotActive.selector);
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    function test_createLoan_requestNotActiveReverts() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        bytes memory cancelSig = signRequestCancel(
            requestId,
            borrower,
            r.nonce,
            borrowerKey,
            localFactory.DOMAIN_SEPARATOR()
        );
        localFactory.cancelRequest(requestId, cancelSig);

        BackendTerms memory t = _terms(3);
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        vm.expectRevert(CreditMarketplaceFactory.RequestNotActive.selector);
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    function test_createLoan_offerExpiredReverts() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        vm.warp(block.timestamp + 2 hours);

        vm.expectRevert(CreditMarketplaceFactory.OfferExpired.selector);
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    function test_createLoan_backendTermsExpiredReverts() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);
        t.validUntil = uint64(block.timestamp);
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        vm.expectRevert(CreditMarketplaceFactory.BackendTermsExpired.selector);
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    function test_createLoan_wrongChainReverts() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);
        t.chainId = 1;
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        vm.expectRevert(CreditMarketplaceFactory.WrongChain.selector);
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    function test_createLoan_wrongFactoryReverts() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);
        t.factory = makeAddr("notThisFactory");
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        vm.expectRevert(CreditMarketplaceFactory.WrongFactory.selector);
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    function test_createLoan_invalidBackendSigReverts() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = signBackendTerms(
            t,
            lenderKey,
            localFactory.DOMAIN_SEPARATOR()
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                CreditMarketplaceFactory.InvalidSignature.selector,
                backendSignerEOA
            )
        );
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    function test_createLoan_termsAprOutOfOfferBoundsReverts() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);
        t.apr = 2_000;
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        vm.expectRevert(
            abi.encodeWithSelector(
                CreditMarketplaceFactory.BoundsViolation.selector,
                bytes32("apr.offer")
            )
        );
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    function test_createLoan_principalExceedsMaxReverts() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);
        t.principal = 1_000e6;
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        vm.expectRevert(
            abi.encodeWithSelector(
                CreditMarketplaceFactory.BoundsViolation.selector,
                bytes32("principal.max")
            )
        );
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    function test_createLoan_creditTierBelowMinReverts() public {
        Offer memory o = _offer(1);
        o.minBorrowerCreditTier = 5;
        uint256 offerId = localFactory.postOffer(o, _offerSig(o));

        Request memory r = _request(2);
        uint256 requestId = localFactory.postRequest(r, _requestSig(r));

        BackendTerms memory t = _terms(3);
        t.borrowerCreditTier = 0;
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        vm.expectRevert(
            abi.encodeWithSelector(
                CreditMarketplaceFactory.BoundsViolation.selector,
                bytes32("creditTier")
            )
        );
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    /// Backend signs a higher tier than the registry holds for the
    /// borrower. Factory must reject — this is the post-backend-compromise
    /// mitigation: even with a stolen signing key, an attacker can't elevate
    /// a borrower beyond their registry tier without also compromising the
    /// registry owner.
    function test_createLoan_borrowerTierAboveRegistryReverts() public {
        // Registry holds tier=3 for borrower; backend signs tier=10.
        vm.prank(tierRegistryOwner);
        tierRegistry.setTier(borrower, 3);

        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);
        t.borrowerCreditTier = 10;

        // Precompute sigs BEFORE expectRevert — argument evaluation
        // would otherwise consume the "next call" the cheatcode is
        // watching for and the assertion would fire on a static call.
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        vm.expectRevert(
            abi.encodeWithSelector(
                CreditMarketplaceFactory.BorrowerTierMismatch.selector,
                uint16(10),
                uint16(3)
            )
        );
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    /// Registry tier matches signed tier and clears the offer minimum →
    /// match succeeds. Verifies the registry path doesn't break the
    /// happy case when wired correctly.
    function test_createLoan_borrowerTierMatchesRegistryAndOfferMin() public {
        vm.prank(tierRegistryOwner);
        tierRegistry.setTier(borrower, 7);

        Offer memory o = _offer(1);
        o.minBorrowerCreditTier = 5; // registry's 7 clears this
        uint256 offerId = localFactory.postOffer(o, _offerSig(o));

        Request memory r = _request(2);
        uint256 requestId = localFactory.postRequest(r, _requestSig(r));

        BackendTerms memory t = _terms(3);
        t.borrowerCreditTier = 7;

        (uint256 loanId, ) = localFactory.createLoan(
            offerId,
            requestId,
            t,
            _offerSig(o),
            _requestSig(r),
            _signedTerms(t)
        );
        assertEq(loanId, 0);
    }

    function test_createLoan_undercollateralizedReverts() public {
        MockPriceFeed cheapFeed = new MockPriceFeed(1e6, 8); // $0.01
        vm.prank(temporalGovernor);
        localFactory.whitelistCollateralToken(
            cbbtc,
            true,
            AggregatorV3Interface(address(cheapFeed)),
            3_600
        );

        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        vm.expectRevert();
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    function test_createLoan_aprBelowMoonwellFloor_reverts() public {
        // Governance sets a 10% margin requirement.
        vm.prank(temporalGovernor);
        localFactory.setAprFloorBufferBps(1_000);

        // Mock the mToken to return a borrow rate equal to the
        // marketplace's APR — fails the 10% buffer.
        uint256 marketplaceRatePerSec = (uint256(800) * 1e14) / 365 days;
        vm.mockCall(
            address(mockMToken),
            abi.encodeWithSignature("borrowRatePerTimestamp()"),
            abi.encode(marketplaceRatePerSec)
        );

        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        vm.expectRevert(
            abi.encodeWithSelector(
                CreditMarketplaceFactory
                    .MarketplaceAprBelowMoonwellFloor
                    .selector,
                marketplaceRatePerSec,
                (marketplaceRatePerSec * 11_000) / 10_000
            )
        );
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    function test_createLoan_mTokenDeWhitelistedBetweenPostAndMatch_reverts()
        public
    {
        // Offer posted against the current whitelist…
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        // …then governance yanks the mToken (e.g. Moonwell pauses the
        // market). The stale offer must not be matcheable.
        vm.prank(temporalGovernor);
        localFactory.whitelistMToken(
            address(mockMToken),
            false,
            AggregatorV3Interface(address(0)),
            0
        );

        vm.expectRevert(CreditMarketplaceFactory.NotMTokenWhitelisted.selector);
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    function test_createLoan_insufficientLenderBalanceReverts() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        vm.prank(lender);
        IERC20(address(mockMToken)).transfer(makeAddr("sink"), M_TOKEN_AMOUNT);

        vm.expectRevert(
            CreditMarketplaceFactory.InsufficientLenderBalance.selector
        );
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    function test_createLoan_secondLoanIncrementsId() public {
        (
            uint256 offerId1,
            Offer memory o1,
            uint256 requestId1,
            Request memory r1
        ) = _postMatchable(1, 2);
        BackendTerms memory t1 = _terms(3);
        localFactory.createLoan(
            offerId1,
            requestId1,
            t1,
            _offerSig(o1),
            _requestSig(r1),
            _signedTerms(t1)
        );

        mockMToken.mintTo(lender, M_TOKEN_AMOUNT);
        deal(cbbtc, borrower, COLLATERAL_AMOUNT);

        (
            uint256 offerId2,
            Offer memory o2,
            uint256 requestId2,
            Request memory r2
        ) = _postMatchable(11, 12);
        BackendTerms memory t2 = _terms(13);
        (uint256 loanId2, ) = localFactory.createLoan(
            offerId2,
            requestId2,
            t2,
            _offerSig(o2),
            _requestSig(r2),
            _signedTerms(t2)
        );

        assertEq(loanId2, 1);
        assertEq(localFactory.nextLoanId(), 2);
    }

    /// Regression guardrail (§14.4). Cap is intentionally loose —
    /// observed ~800-900k with mocked Moonwell; 1M leaves headroom for
    /// small tweaks while catching a true blowup.
    function test_gas_createLoan_mockCap() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        uint256 before = gasleft();
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
        uint256 used = before - gasleft();

        assertLt(used, 1_000_000, "createLoan mock-gas regression");
    }

    function test_getLoan_defaultsZero() public view {
        assertEq(localFactory.getLoan(99), address(0));
    }

    // ─── backend operational-param bounds (audit MATCH-01 / F-03) ────
    // gracePeriod / overSeizureBps / consecutiveMissesForDefault /
    // marketplaceFeeBps / feeRecipient live ONLY in BackendTerms — the
    // lender and borrower never sign them. The setDefaultParams caps must
    // therefore be re-enforced at match time so a buggy or compromised
    // backend cannot sign out-of-bounds terms into a live clone.

    function test_createLoan_revertsExcessiveMarketplaceFee() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);
        t.marketplaceFeeBps = 2_001; // > MAX_MARKETPLACE_FEE_BPS (2_000)
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        vm.expectRevert(
            CreditMarketplaceFactory.InvalidMarketplaceFeeBps.selector
        );
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    function test_createLoan_revertsExcessiveOverSeizure() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);
        t.overSeizureBps = 5_001; // > MAX_OVER_SEIZURE_BPS (5_000)
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        vm.expectRevert(
            CreditMarketplaceFactory.InvalidOverSeizureBps.selector
        );
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    function test_createLoan_revertsZeroConsecutiveMisses() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);
        t.consecutiveMissesForDefault = 0; // would default on the first miss
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        vm.expectRevert(
            CreditMarketplaceFactory.InvalidConsecutiveMisses.selector
        );
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    function test_createLoan_revertsExcessiveConsecutiveMisses() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);
        t.consecutiveMissesForDefault = 11; // > MAX_CONSECUTIVE_MISSES (10)
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        vm.expectRevert(
            CreditMarketplaceFactory.InvalidConsecutiveMisses.selector
        );
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    function test_createLoan_revertsExcessiveGracePeriod() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);
        t.gracePeriod = 7 days + 1; // > MAX_GRACE_PERIOD (7 days)
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        vm.expectRevert(CreditMarketplaceFactory.InvalidGracePeriod.selector);
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    function test_createLoan_revertsZeroFeeRecipient() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);
        t.feeRecipient = address(0); // nonzero fee to address(0) bricks _settle
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        vm.expectRevert(CreditMarketplaceFactory.ZeroAddress.selector);
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    /// Boundary: terms exactly at the caps still originate.
    function test_createLoan_atOperationalCapsSucceeds() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        BackendTerms memory t = _terms(3);
        t.gracePeriod = 7 days; // == MAX_GRACE_PERIOD
        t.overSeizureBps = 5_000; // == MAX_OVER_SEIZURE_BPS
        t.consecutiveMissesForDefault = 10; // == MAX_CONSECUTIVE_MISSES
        t.marketplaceFeeBps = 2_000; // == MAX_MARKETPLACE_FEE_BPS
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        (, address loanAddr) = localFactory.createLoan(
            offerId,
            requestId,
            t,
            oSig,
            rSig,
            bSig
        );
        assertTrue(loanAddr != address(0));
    }

    // ─── credit-tier gate: every tier ────────────────────────────────

    function _createLoanAtTier(
        uint16 tierVal,
        uint256 baseNonce
    ) internal returns (address loanAddr) {
        vm.prank(tierRegistryOwner);
        tierRegistry.setTier(borrower, tierVal);
        // Re-fund for this iteration (the prior loan escrowed the lender's
        // mMOCK and the borrower's cbBTC).
        mockMToken.mintTo(lender, M_TOKEN_AMOUNT);
        deal(cbbtc, borrower, COLLATERAL_AMOUNT);

        Offer memory o = _offer(baseNonce);
        o.minBorrowerCreditTier = tierVal;
        Request memory r = _request(baseNonce + 1);
        BackendTerms memory t = _terms(baseNonce + 2);
        t.borrowerCreditTier = tierVal;

        uint256 offerId = localFactory.postOffer(o, _offerSig(o));
        uint256 requestId = localFactory.postRequest(r, _requestSig(r));
        (, loanAddr) = localFactory.createLoan(
            offerId,
            requestId,
            t,
            _offerSig(o),
            _requestSig(r),
            _signedTerms(t)
        );
    }

    /// A borrower registered at tier T matches an offer whose
    /// minBorrowerCreditTier == T, for every tier 1..4.
    function test_createLoan_gate_acceptsEveryTier() public {
        for (uint16 tierVal = 1; tierVal <= 4; tierVal++) {
            assertTrue(
                _createLoanAtTier(tierVal, uint256(tierVal) * 100) != address(0)
            );
        }
    }

    /// An offer requiring T+1 rejects a tier-T borrower, for every tier 1..4.
    function test_createLoan_gate_rejectsBelowEveryTier() public {
        for (uint16 tierVal = 1; tierVal <= 4; tierVal++) {
            vm.prank(tierRegistryOwner);
            tierRegistry.setTier(borrower, tierVal);

            Offer memory o = _offer(uint256(tierVal) * 1000);
            o.minBorrowerCreditTier = tierVal + 1; // above the borrower's tier
            Request memory r = _request(uint256(tierVal) * 1000 + 1);
            BackendTerms memory t = _terms(uint256(tierVal) * 1000 + 2);
            t.borrowerCreditTier = tierVal; // exact-matches the registry

            uint256 offerId = localFactory.postOffer(o, _offerSig(o));
            uint256 requestId = localFactory.postRequest(r, _requestSig(r));
            // Precompute sigs BEFORE expectRevert — the sig helpers call
            // vm.sign, which would otherwise consume the expectRevert.
            bytes memory oSig = _offerSig(o);
            bytes memory rSig = _requestSig(r);
            bytes memory bSig = _signedTerms(t);
            vm.expectRevert(
                abi.encodeWithSelector(
                    CreditMarketplaceFactory.BoundsViolation.selector,
                    bytes32("creditTier")
                )
            );
            localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
        }
    }

    /// The backend-signed tier must EXACTLY equal the registry tier.
    function test_createLoan_gate_exactTierMismatchReverts() public {
        vm.prank(tierRegistryOwner);
        tierRegistry.setTier(borrower, 3);

        Offer memory o = _offer(1);
        Request memory r = _request(2);
        BackendTerms memory t = _terms(3);
        t.borrowerCreditTier = 2; // != registry's 3

        uint256 offerId = localFactory.postOffer(o, _offerSig(o));
        uint256 requestId = localFactory.postRequest(r, _requestSig(r));
        // Precompute sigs BEFORE expectRevert (sig helpers call vm.sign).
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);
        vm.expectRevert(
            abi.encodeWithSelector(
                CreditMarketplaceFactory.BorrowerTierMismatch.selector,
                uint16(2),
                uint16(3)
            )
        );
        localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig);
    }

    // ─── schedule solvency vs Moonwell accrual (risk-report Axis C) ──

    bytes4 internal constant BORROW_RATE_SEL =
        bytes4(keccak256("borrowRatePerTimestamp()"));

    /// A schedule whose total interest can't cover the projected Moonwell
    /// borrow accrual over the term must be rejected at origination (else
    /// _settle reverts InsufficientPrincipalForRepay and the lender eats it).
    function test_createLoan_scheduleUndercoversMoonwell_reverts() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        // ~5% APR per-second rate: below the 8% apr field (so the APR floor
        // passes) but nonzero so accrual > 0.
        vm.mockCall(
            address(mockMToken),
            abi.encodeWithSelector(BORROW_RATE_SEL),
            abi.encode(uint256(1585e6))
        );
        BackendTerms memory t = _terms(3);
        t.schedule.interestAmountPerPayment = 0; // insolvent: no interest
        t.schedule.finalPaymentAmount = PRINCIPAL; // no trailing stub either
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        // try/catch selector compare — ScheduleUndercoversMoonwell carries
        // live-rate-dependent args, so match on the selector only.
        try
            localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig)
        returns (uint256, address) {
            revert("expected ScheduleUndercoversMoonwell");
        } catch (bytes memory reason) {
            assertEq(
                bytes4(reason),
                CreditMarketplaceFactory.ScheduleUndercoversMoonwell.selector
            );
        }
    }

    /// A schedule whose interest comfortably covers the projected accrual
    /// originates fine even at a nonzero Moonwell rate.
    function test_createLoan_solventScheduleAtNonzeroRate_succeeds() public {
        (
            uint256 offerId,
            Offer memory o,
            uint256 requestId,
            Request memory r
        ) = _postMatchable(1, 2);
        vm.mockCall(
            address(mockMToken),
            abi.encodeWithSelector(BORROW_RATE_SEL),
            abi.encode(uint256(1585e6))
        );
        BackendTerms memory t = _terms(3); // default ~$50 interest >> ~$2 accrual
        (, address loanAddr) = localFactory.createLoan(
            offerId,
            requestId,
            t,
            _offerSig(o),
            _requestSig(r),
            _signedTerms(t)
        );
        assertTrue(loanAddr != address(0));
    }

    // ─── per-collateral buffer floor (risk-report §5.1) ──────────────

    event CollateralBufferBpsUpdated(
        address indexed token,
        uint16 previous,
        uint16 updated
    );

    // cbBTC ($100k feed) units worth ~112% of the $400 principal: clears the
    // 10% global floor, but not a 30% per-collateral floor.
    uint256 internal constant TIGHT_COLLATERAL = 448_000; // 0.00448 cbBTC ≈ $448

    function test_setCollateralBufferBps_happy() public {
        vm.expectEmit(true, true, true, true, address(localFactory));
        emit CollateralBufferBpsUpdated(cbbtc, 0, 3000);
        vm.prank(temporalGovernor);
        localFactory.setCollateralBufferBps(cbbtc, 3000);
        assertEq(localFactory.collateralBufferBps(cbbtc), 3000);
    }

    function test_setCollateralBufferBps_onlyOwnerReverts() public {
        vm.prank(borrower);
        vm.expectRevert("Ownable: caller is not the owner");
        localFactory.setCollateralBufferBps(cbbtc, 3000);
    }

    function test_setCollateralBufferBps_capExceededReverts() public {
        vm.prank(temporalGovernor);
        vm.expectRevert(CreditMarketplaceFactory.InvalidBufferBps.selector);
        localFactory.setCollateralBufferBps(cbbtc, 10_001);
    }

    /// With a 30% per-collateral floor set, a ~112% collateralized loan (which
    /// clears the 10% global) is rejected.
    function test_createLoan_perCollateralBufferFloor_reverts() public {
        vm.prank(temporalGovernor);
        localFactory.setCollateralBufferBps(cbbtc, 3000);

        deal(cbbtc, borrower, TIGHT_COLLATERAL);
        Offer memory o = _offer(1);
        Request memory r = _request(2);
        r.collateralAmount = TIGHT_COLLATERAL;
        BackendTerms memory t = _terms(3);
        t.collateralAmount = TIGHT_COLLATERAL;
        uint256 offerId = localFactory.postOffer(o, _offerSig(o));
        uint256 requestId = localFactory.postRequest(r, _requestSig(r));
        bytes memory oSig = _offerSig(o);
        bytes memory rSig = _requestSig(r);
        bytes memory bSig = _signedTerms(t);

        try
            localFactory.createLoan(offerId, requestId, t, oSig, rSig, bSig)
        returns (uint256, address) {
            revert("expected InsufficientCollateral");
        } catch (bytes memory reason) {
            assertEq(
                bytes4(reason),
                CreditMarketplaceFactory.InsufficientCollateral.selector
            );
        }
    }

    /// The same ~112% loan with NO per-collateral floor (default 0) clears the
    /// 10% global and originates — proving the revert above is the buffer, not
    /// the collateral.
    function test_createLoan_perCollateralBuffer_zeroDefersToGlobal() public {
        deal(cbbtc, borrower, TIGHT_COLLATERAL);
        Offer memory o = _offer(1);
        Request memory r = _request(2);
        r.collateralAmount = TIGHT_COLLATERAL;
        BackendTerms memory t = _terms(3);
        t.collateralAmount = TIGHT_COLLATERAL;
        uint256 offerId = localFactory.postOffer(o, _offerSig(o));
        uint256 requestId = localFactory.postRequest(r, _requestSig(r));
        (, address loanAddr) = localFactory.createLoan(
            offerId,
            requestId,
            t,
            _offerSig(o),
            _requestSig(r),
            _signedTerms(t)
        );
        assertTrue(loanAddr != address(0));
    }
}
