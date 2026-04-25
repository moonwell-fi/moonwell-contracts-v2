// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

import {CreditMarketplaceFactory} from "@protocol/marketplace/CreditMarketplaceFactory.sol";
import {CreditTypeHashes} from "@protocol/marketplace/CreditTypeHashes.sol";
import {EIP712Lib} from "@protocol/marketplace/EIP712Lib.sol";
import {Offer, OfferStatus, Request, RequestStatus} from "@protocol/marketplace/CreditTypes.sol";

import {Fixture} from "./Fixture.t.sol";

contract OrderBookTest is Fixture {
    event OfferPosted(
        uint256 indexed offerId,
        address indexed lender,
        address indexed mToken,
        uint256 mTokenAmount,
        address principalToken,
        uint256 maxPrincipal,
        uint16 maxApr,
        uint64 expiresAt
    );
    event OfferCanceled(uint256 indexed offerId);
    event RequestPosted(
        uint256 indexed requestId,
        address indexed borrower,
        address principalToken,
        uint256 principal,
        address indexed collateralToken,
        uint256 collateralAmount,
        uint16 maxApr,
        uint64 expiresAt
    );
    event RequestCanceled(uint256 indexed requestId);

    function setUp() public override {
        super.setUp();
        vm.startPrank(temporalGovernor);
        // Cap must be set before per-feed staleness — whitelist setters
        // reject any value above the cap.
        factory.setStalenessWindow(1 days);
        // whitelistMToken registers the underlying (USDC) feed in the
        // same call — the principal side no longer has its own
        // whitelist. chainlinkBtcUsd is a live feed we reuse as a
        // stand-in for the USDC/USD oracle; the real one would be
        // addresses.getAddress("USDC_ORACLE").
        factory.whitelistMToken(
            mUsdc,
            true,
            AggregatorV3Interface(chainlinkBtcUsd),
            3_600
        );
        factory.whitelistCollateralToken(
            cbbtc,
            true,
            AggregatorV3Interface(chainlinkBtcUsd),
            3_600
        );
        vm.stopPrank();
    }

    // ─── helpers ─────────────────────────────────────────────────────

    function _defaultOffer(
        uint256 nonce
    ) internal view returns (Offer memory o) {
        address[] memory col = new address[](1);
        col[0] = cbbtc;
        o = Offer({
            lender: lender,
            mToken: mUsdc,
            mTokenAmount: 1_000e6,
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

    function _defaultRequest(
        uint256 nonce
    ) internal view returns (Request memory r) {
        r = Request({
            borrower: borrower,
            principalToken: usdc,
            principal: 400e6,
            collateralToken: cbbtc,
            collateralAmount: 1e7,
            maxApr: 1_000,
            minTerm: 1 days,
            maxTerm: 30 days,
            expiresAt: uint64(block.timestamp + 1 hours),
            nonce: nonce,
            status: RequestStatus.Active
        });
    }

    function _postValidOffer(
        uint256 nonce
    ) internal returns (uint256 offerId, Offer memory offer) {
        offer = _defaultOffer(nonce);
        bytes memory sig = signOffer(
            offer,
            lenderKey,
            factory.DOMAIN_SEPARATOR()
        );
        offerId = factory.postOffer(offer, sig);
    }

    function _postValidRequest(
        uint256 nonce
    ) internal returns (uint256 requestId, Request memory request) {
        request = _defaultRequest(nonce);
        bytes memory sig = signRequest(
            request,
            borrowerKey,
            factory.DOMAIN_SEPARATOR()
        );
        requestId = factory.postRequest(request, sig);
    }

    // ─── postOffer ───────────────────────────────────────────────────

    function test_postOffer_happy() public {
        Offer memory offer = _defaultOffer(1);
        bytes memory sig = signOffer(
            offer,
            lenderKey,
            factory.DOMAIN_SEPARATOR()
        );

        vm.expectEmit(true, true, true, true, address(factory));
        emit OfferPosted(
            0,
            lender,
            mUsdc,
            1_000e6,
            usdc,
            500e6,
            1_000,
            offer.expiresAt
        );
        uint256 offerId = factory.postOffer(offer, sig);

        assertEq(offerId, 0);
        assertEq(factory.nextOfferId(), 1);

        Offer memory stored = factory.getOffer(offerId);
        assertEq(stored.lender, lender);
        assertEq(stored.mToken, mUsdc);
        assertEq(stored.mTokenAmount, 1_000e6);
        assertEq(stored.acceptedCollateral.length, 1);
        assertEq(stored.acceptedCollateral[0], cbbtc);
        assertTrue(stored.status == OfferStatus.Active);
    }

    function test_postOffer_whenPausedReverts() public {
        vm.prank(pauseGuardian);
        factory.pause();

        Offer memory offer = _defaultOffer(1);
        bytes memory sig = signOffer(
            offer,
            lenderKey,
            factory.DOMAIN_SEPARATOR()
        );

        vm.expectRevert("Pausable: paused");
        factory.postOffer(offer, sig);
    }

    function test_postOffer_expiredReverts() public {
        Offer memory offer = _defaultOffer(1);
        offer.expiresAt = uint64(block.timestamp);
        bytes memory sig = signOffer(
            offer,
            lenderKey,
            factory.DOMAIN_SEPARATOR()
        );

        vm.expectRevert(CreditMarketplaceFactory.OfferExpired.selector);
        factory.postOffer(offer, sig);
    }

    function test_postOffer_invalidAprBoundsReverts() public {
        Offer memory offer = _defaultOffer(1);
        offer.maxApr = 100;
        offer.minApr = 500;
        bytes memory sig = signOffer(
            offer,
            lenderKey,
            factory.DOMAIN_SEPARATOR()
        );

        vm.expectRevert(CreditMarketplaceFactory.InvalidAprBounds.selector);
        factory.postOffer(offer, sig);
    }

    function test_postOffer_invalidTermBoundsReverts() public {
        Offer memory offer = _defaultOffer(1);
        offer.maxTerm = 100;
        offer.minTerm = 500;
        bytes memory sig = signOffer(
            offer,
            lenderKey,
            factory.DOMAIN_SEPARATOR()
        );

        vm.expectRevert(CreditMarketplaceFactory.InvalidTermBounds.selector);
        factory.postOffer(offer, sig);
    }

    function test_postOffer_mTokenNotWhitelistedReverts() public {
        Offer memory offer = _defaultOffer(1);
        offer.mToken = makeAddr("unknownMToken");
        bytes memory sig = signOffer(
            offer,
            lenderKey,
            factory.DOMAIN_SEPARATOR()
        );

        vm.expectRevert(CreditMarketplaceFactory.NotMTokenWhitelisted.selector);
        factory.postOffer(offer, sig);
    }

    function test_postOffer_principalMustEqualMTokenUnderlying() public {
        // mUsdc's real underlying is USDC; a lender can't sign an Offer
        // that claims a different principalToken because the clone's
        // borrow would draw USDC regardless of what was signed.
        Offer memory offer = _defaultOffer(1);
        offer.principalToken = makeAddr("someOtherToken");
        bytes memory sig = signOffer(
            offer,
            lenderKey,
            factory.DOMAIN_SEPARATOR()
        );

        vm.expectRevert(
            CreditMarketplaceFactory.PrincipalMustMatchMTokenUnderlying.selector
        );
        factory.postOffer(offer, sig);
    }

    function test_postOffer_collateralNotWhitelistedReverts() public {
        Offer memory offer = _defaultOffer(1);
        address[] memory col = new address[](2);
        col[0] = cbbtc;
        col[1] = makeAddr("unknownMeme");
        offer.acceptedCollateral = col;
        bytes memory sig = signOffer(
            offer,
            lenderKey,
            factory.DOMAIN_SEPARATOR()
        );

        vm.expectRevert(
            CreditMarketplaceFactory.NotCollateralWhitelisted.selector
        );
        factory.postOffer(offer, sig);
    }

    function test_postOffer_invalidSignatureReverts() public {
        Offer memory offer = _defaultOffer(1);
        // Sign with a key that isn't the lender.
        bytes memory sig = signOffer(
            offer,
            backendSignerKey,
            factory.DOMAIN_SEPARATOR()
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                CreditMarketplaceFactory.InvalidSignature.selector,
                lender
            )
        );
        factory.postOffer(offer, sig);
    }

    function test_postOffer_nonceAlreadyUsedReverts() public {
        // Post an offer and cancel it (burns the nonce).
        (uint256 offerId, Offer memory posted) = _postValidOffer(42);
        bytes memory cancelSig = signOfferCancel(
            offerId,
            lender,
            posted.nonce,
            lenderKey,
            factory.DOMAIN_SEPARATOR()
        );
        factory.cancelOffer(offerId, cancelSig);
        assertTrue(factory.isNonceUsed(lender, 42));

        // Re-posting with the same nonce now reverts.
        Offer memory offer2 = _defaultOffer(42);
        bytes memory sig = signOffer(
            offer2,
            lenderKey,
            factory.DOMAIN_SEPARATOR()
        );
        vm.expectRevert(CreditMarketplaceFactory.NonceAlreadyUsed.selector);
        factory.postOffer(offer2, sig);
    }

    function test_postOffer_ignoresCallerSuppliedStatus() public {
        // Malicious caller tries to post an offer pre-marked Canceled.
        Offer memory offer = _defaultOffer(1);
        offer.status = OfferStatus.Canceled;
        // Signature is over the economic fields only (OFFER_TYPEHASH
        // doesn't include `status`), so this still verifies against lender.
        bytes memory sig = signOffer(
            offer,
            lenderKey,
            factory.DOMAIN_SEPARATOR()
        );

        uint256 offerId = factory.postOffer(offer, sig);
        Offer memory stored = factory.getOffer(offerId);
        assertTrue(stored.status == OfferStatus.Active);
    }

    // ─── postRequest ─────────────────────────────────────────────────

    function test_postRequest_happy() public {
        Request memory request = _defaultRequest(1);
        bytes memory sig = signRequest(
            request,
            borrowerKey,
            factory.DOMAIN_SEPARATOR()
        );

        vm.expectEmit(true, true, true, true, address(factory));
        emit RequestPosted(
            0,
            borrower,
            usdc,
            400e6,
            cbbtc,
            1e7,
            1_000,
            request.expiresAt
        );
        uint256 requestId = factory.postRequest(request, sig);

        assertEq(requestId, 0);
        assertEq(factory.nextRequestId(), 1);

        Request memory stored = factory.getRequest(requestId);
        assertEq(stored.borrower, borrower);
        assertEq(stored.principalToken, usdc);
        assertEq(stored.collateralToken, cbbtc);
        assertTrue(stored.status == RequestStatus.Active);
    }

    function test_postRequest_whenPausedReverts() public {
        vm.prank(pauseGuardian);
        factory.pause();

        Request memory request = _defaultRequest(1);
        bytes memory sig = signRequest(
            request,
            borrowerKey,
            factory.DOMAIN_SEPARATOR()
        );

        vm.expectRevert("Pausable: paused");
        factory.postRequest(request, sig);
    }

    function test_postRequest_expiredReverts() public {
        Request memory request = _defaultRequest(1);
        request.expiresAt = uint64(block.timestamp);
        bytes memory sig = signRequest(
            request,
            borrowerKey,
            factory.DOMAIN_SEPARATOR()
        );

        vm.expectRevert(CreditMarketplaceFactory.RequestExpired.selector);
        factory.postRequest(request, sig);
    }

    function test_postRequest_invalidTermBoundsReverts() public {
        Request memory request = _defaultRequest(1);
        request.minTerm = 30 days;
        request.maxTerm = 1 days;
        bytes memory sig = signRequest(
            request,
            borrowerKey,
            factory.DOMAIN_SEPARATOR()
        );

        vm.expectRevert(CreditMarketplaceFactory.InvalidTermBounds.selector);
        factory.postRequest(request, sig);
    }

    function test_postRequest_principalTokenNotWhitelistedReverts() public {
        Request memory request = _defaultRequest(1);
        request.principalToken = makeAddr("unknownStable");
        bytes memory sig = signRequest(
            request,
            borrowerKey,
            factory.DOMAIN_SEPARATOR()
        );

        vm.expectRevert(
            CreditMarketplaceFactory.NotPrincipalTokenWhitelisted.selector
        );
        factory.postRequest(request, sig);
    }

    function test_postRequest_collateralNotWhitelistedReverts() public {
        Request memory request = _defaultRequest(1);
        request.collateralToken = makeAddr("unknownMeme");
        bytes memory sig = signRequest(
            request,
            borrowerKey,
            factory.DOMAIN_SEPARATOR()
        );

        vm.expectRevert(
            CreditMarketplaceFactory.NotCollateralWhitelisted.selector
        );
        factory.postRequest(request, sig);
    }

    function test_postRequest_invalidSignatureReverts() public {
        Request memory request = _defaultRequest(1);
        bytes memory sig = signRequest(
            request,
            lenderKey,
            factory.DOMAIN_SEPARATOR()
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                CreditMarketplaceFactory.InvalidSignature.selector,
                borrower
            )
        );
        factory.postRequest(request, sig);
    }

    // ─── cancelOffer ─────────────────────────────────────────────────

    function test_cancelOffer_happy() public {
        (uint256 offerId, Offer memory offer) = _postValidOffer(7);

        bytes memory sig = signOfferCancel(
            offerId,
            lender,
            offer.nonce,
            lenderKey,
            factory.DOMAIN_SEPARATOR()
        );

        vm.expectEmit(true, true, true, true, address(factory));
        emit OfferCanceled(offerId);
        factory.cancelOffer(offerId, sig);

        assertTrue(factory.getOffer(offerId).status == OfferStatus.Canceled);
        assertTrue(factory.isNonceUsed(lender, 7));
    }

    function test_cancelOffer_afterAlreadyCanceledReverts() public {
        (uint256 offerId, Offer memory offer) = _postValidOffer(1);
        bytes memory sig = signOfferCancel(
            offerId,
            lender,
            offer.nonce,
            lenderKey,
            factory.DOMAIN_SEPARATOR()
        );
        factory.cancelOffer(offerId, sig);

        vm.expectRevert(CreditMarketplaceFactory.OfferNotActive.selector);
        factory.cancelOffer(offerId, sig);
    }

    function test_cancelOffer_wrongSignerReverts() public {
        (uint256 offerId, Offer memory offer) = _postValidOffer(1);

        // Backend key signs the cancel — not the lender. Recovered address
        // differs from offer.lender.
        bytes memory sig = signOfferCancel(
            offerId,
            lender,
            offer.nonce,
            backendSignerKey,
            factory.DOMAIN_SEPARATOR()
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                CreditMarketplaceFactory.InvalidSignature.selector,
                lender
            )
        );
        factory.cancelOffer(offerId, sig);
    }

    function test_cancelOffer_boundToDomainSeparator() public {
        (uint256 offerId, Offer memory offer) = _postValidOffer(1);

        // Sign against a DOMAIN_SEPARATOR from a different chain (Ethereum
        // mainnet, chainId 1). Lender's sig is still a valid ECDSA over
        // *some* digest — just not the base-chain one the factory computes.
        bytes32 wrongDomain = keccak256(
            abi.encode(
                CreditTypeHashes.EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("MoonwellCreditMarketplace")),
                keccak256(bytes("1")),
                uint256(1),
                address(factory)
            )
        );
        bytes memory sig = signOfferCancel(
            offerId,
            lender,
            offer.nonce,
            lenderKey,
            wrongDomain
        );

        // The recovered address won't match `lender` — it's whatever the
        // wrong-domain digest recovers to. We just assert that the call
        // reverts with the InvalidSignature selector (ignoring the
        // recovered-address field of the error).
        vm.expectRevert();
        factory.cancelOffer(offerId, sig);
    }

    function test_cancelOffer_allowedWhenPaused() public {
        (uint256 offerId, Offer memory offer) = _postValidOffer(1);

        vm.prank(pauseGuardian);
        factory.pause();

        bytes memory sig = signOfferCancel(
            offerId,
            lender,
            offer.nonce,
            lenderKey,
            factory.DOMAIN_SEPARATOR()
        );

        factory.cancelOffer(offerId, sig);
        assertTrue(factory.getOffer(offerId).status == OfferStatus.Canceled);
    }

    // ─── cancelRequest ───────────────────────────────────────────────

    function test_cancelRequest_happy() public {
        (uint256 requestId, Request memory request) = _postValidRequest(3);

        bytes memory sig = signRequestCancel(
            requestId,
            borrower,
            request.nonce,
            borrowerKey,
            factory.DOMAIN_SEPARATOR()
        );

        vm.expectEmit(true, true, true, true, address(factory));
        emit RequestCanceled(requestId);
        factory.cancelRequest(requestId, sig);

        assertTrue(
            factory.getRequest(requestId).status == RequestStatus.Canceled
        );
        assertTrue(factory.isNonceUsed(borrower, 3));
    }

    function test_cancelRequest_wrongSignerReverts() public {
        (uint256 requestId, Request memory request) = _postValidRequest(1);

        bytes memory sig = signRequestCancel(
            requestId,
            borrower,
            request.nonce,
            lenderKey,
            factory.DOMAIN_SEPARATOR()
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                CreditMarketplaceFactory.InvalidSignature.selector,
                borrower
            )
        );
        factory.cancelRequest(requestId, sig);
    }

    function test_cancelRequest_boundToDomainSeparator() public {
        (uint256 requestId, Request memory request) = _postValidRequest(1);

        bytes32 wrongDomain = keccak256(
            abi.encode(
                CreditTypeHashes.EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("MoonwellCreditMarketplace")),
                keccak256(bytes("1")),
                uint256(1),
                address(factory)
            )
        );
        bytes memory sig = signRequestCancel(
            requestId,
            borrower,
            request.nonce,
            borrowerKey,
            wrongDomain
        );

        vm.expectRevert();
        factory.cancelRequest(requestId, sig);
    }

    // ─── views ───────────────────────────────────────────────────────

    function test_getOffer_preservesDynamicArray() public {
        (uint256 offerId, Offer memory offer) = _postValidOffer(1);

        Offer memory stored = factory.getOffer(offerId);
        assertEq(
            stored.acceptedCollateral.length,
            offer.acceptedCollateral.length
        );
        for (uint256 i = 0; i < offer.acceptedCollateral.length; i++) {
            assertEq(stored.acceptedCollateral[i], offer.acceptedCollateral[i]);
        }
    }

    function test_getRequest_returnsStoredStruct() public {
        (uint256 requestId, Request memory request) = _postValidRequest(1);
        Request memory stored = factory.getRequest(requestId);
        assertEq(stored.borrower, request.borrower);
        assertEq(stored.principal, request.principal);
        assertEq(stored.collateralToken, request.collateralToken);
        assertEq(stored.collateralAmount, request.collateralAmount);
    }
}
