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
        uint256 principal,
        uint16 apr,
        uint32 term
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
            pauseGuardian
        );

        vm.startPrank(temporalGovernor);
        // whitelistMToken also registers the underlying's feed — one
        // call where the old interface needed two.
        localFactory.whitelistMToken(
            address(mockMToken),
            true,
            AggregatorV3Interface(address(usdcFeed))
        );
        localFactory.whitelistCollateralToken(
            cbbtc,
            true,
            AggregatorV3Interface(address(cbbtcFeed))
        );
        localFactory.setStalenessWindow(3_600);
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

        vm.expectEmit(true, false, true, false, address(localFactory));
        emit LoanCreated(
            0,
            address(0),
            lender,
            borrower,
            PRINCIPAL,
            800,
            30 days
        );

        localFactory.createLoan(
            offerId,
            requestId,
            t,
            _offerSig(o),
            _requestSig(r),
            _signedTerms(t)
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

    function test_createLoan_undercollateralizedReverts() public {
        MockPriceFeed cheapFeed = new MockPriceFeed(1e6, 8); // $0.01
        vm.prank(temporalGovernor);
        localFactory.whitelistCollateralToken(
            cbbtc,
            true,
            AggregatorV3Interface(address(cheapFeed))
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
            AggregatorV3Interface(address(0))
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
}
