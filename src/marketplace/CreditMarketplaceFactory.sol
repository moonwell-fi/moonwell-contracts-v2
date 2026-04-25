// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin-contracts/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {SignatureChecker} from "@openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol";
import {Clones} from "@openzeppelin-contracts/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

import {ICreditMarketplaceFactory} from "@protocol/marketplace/ICreditMarketplaceFactory.sol";
import {ICreditLoan} from "@protocol/marketplace/ICreditLoan.sol";
import {CreditTypeHashes} from "@protocol/marketplace/CreditTypeHashes.sol";
import {EIP712Lib} from "@protocol/marketplace/EIP712Lib.sol";
import {PriceLib} from "@protocol/marketplace/PriceLib.sol";
import {InitParams, Offer, Request, BackendTerms, OfferStatus, RequestStatus} from "@protocol/marketplace/CreditTypes.sol";

interface IComptrollerProbe {
    function getAllMarkets() external view returns (address[] memory);
}

interface IMErc20Underlying {
    function underlying() external view returns (address);
}

interface IMTokenBorrowRate {
    /// Compound v2 / Moonwell per-timestamp borrow rate, scaled to 1e18.
    function borrowRatePerTimestamp() external view returns (uint256);
}

contract CreditMarketplaceFactory is
    ICreditMarketplaceFactory,
    Ownable,
    Pausable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    error NotImplemented();
    error ZeroAddress();
    error InvalidComptroller();
    error InvalidImplementation();
    error InvalidOraclePrice();
    error StaleOraclePrice();
    error InvalidStalenessWindow();
    error InvalidBufferBps();
    error InvalidGracePeriod();
    error InvalidOverSeizureBps();
    error InvalidConsecutiveMisses();
    error InvalidMarketplaceFeeBps();
    error InvalidFeedDecimals();
    error NonceAlreadyUsed();
    error OnlyOwnerOrGuardian();
    error OfferNotActive();
    error RequestNotActive();
    error OfferExpired();
    error RequestExpired();
    error InvalidSignature(address signer);
    error InvalidAprBounds();
    error InvalidTermBounds();
    error NotMTokenWhitelisted();
    error NotCollateralWhitelisted();
    error NotPrincipalTokenWhitelisted();
    error PrincipalMustMatchMTokenUnderlying();
    error BackendTermsExpired();
    error WrongChain();
    error WrongFactory();
    error InsufficientLenderBalance();
    error InsufficientCollateral(uint256 haveUsd1e18, uint256 requiredUsd1e18);
    error BoundsViolation(bytes32 which);
    error MarketplaceAprBelowMoonwellFloor(
        uint256 marketplaceRatePerSec,
        uint256 minRequiredRatePerSec
    );

    event BackendSignerUpdated(
        address indexed previousSigner,
        address indexed newSigner
    );
    event CreditLoanImplementationUpdated(
        address indexed previous,
        address indexed updated
    );
    event MTokenWhitelisted(
        address indexed mToken,
        bool allowed,
        address indexed feed
    );
    event CollateralWhitelisted(
        address indexed token,
        bool allowed,
        address indexed feed
    );
    event StalenessWindowUpdated(uint32 seconds_);
    event MinOriginationLtvBufferBpsUpdated(uint16 previous, uint16 updated);
    event DefaultParamsUpdated(
        uint32 gracePeriod,
        uint16 overSeizureBps,
        uint16 consecutiveMissesForDefault,
        uint16 marketplaceFeeBps
    );
    event FeeRecipientUpdated(
        address indexed previous,
        address indexed updated
    );
    event PauseGuardianUpdated(
        address indexed previousGuardian,
        address indexed newGuardian
    );
    event AprFloorBufferBpsUpdated(uint16 previous, uint16 updated);
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
    event LoanCreated(
        uint256 indexed loanId,
        address indexed loanAddress,
        address indexed lender,
        address borrower,
        uint256 principal,
        uint16 apr,
        uint32 term
    );

    /// Max age accepted from a Chainlink feed at whitelist time. Not the
    /// per-loan staleness budget — that's the governance-tunable
    /// `stalenessWindow`. This constant exists purely to catch a dead feed
    /// at proposal execution rather than at first match.
    uint256 internal constant FEED_LIVENESS_AT_WHITELIST = 1 days;

    uint32 internal constant MAX_STALENESS_WINDOW = 7 days;
    uint16 internal constant MAX_OVER_SEIZURE_BPS = 5_000;
    uint32 internal constant MAX_GRACE_PERIOD = 7 days;
    uint16 internal constant MAX_MARKETPLACE_FEE_BPS = 2_000;
    uint16 internal constant MAX_CONSECUTIVE_MISSES = 10;
    uint16 internal constant MIN_LTV_BUFFER_BPS = 100;
    uint16 internal constant MAX_LTV_BUFFER_BPS = 10_000;

    bytes32 public immutable DOMAIN_SEPARATOR;
    address public immutable comptroller;
    address public immutable temporalGovernor;

    address public creditLoanImplementation;
    address public backendSigner;
    address public feeRecipient;
    address public pauseGuardian;

    uint32 public stalenessWindow;
    uint16 public minOriginationLtvBufferBps;
    /// Required margin between marketplace APR and Moonwell's borrow APR
    /// at match time, in bps. Marketplace per-second rate must be at
    /// least `moonwellRate * (10_000 + bufferBps) / 10_000` for a match
    /// to succeed; otherwise `_settle` would risk reverting
    /// InsufficientPrincipalForRepay over the loan term.
    uint16 public aprFloorBufferBps;
    uint32 public defaultGracePeriod;
    uint16 public defaultOverSeizureBps;
    uint16 public defaultConsecutiveMissesForDefault;
    uint16 public defaultMarketplaceFeeBps;

    mapping(address => bool) public isMTokenWhitelisted;
    mapping(address => AggregatorV3Interface) public collateralFeeds;
    mapping(address => bool) public isCollateralWhitelisted;
    /// Feed for the principal side of each match, keyed by the mToken's
    /// underlying. Populated via `whitelistMToken` — the principal token
    /// is always `IMErc20(mToken).underlying()`, so it's not its own
    /// whitelist surface.
    mapping(address => AggregatorV3Interface) public principalTokenFeeds;

    mapping(uint256 => Offer) public offers;
    mapping(uint256 => Request) public requests;
    uint256 public nextOfferId;
    uint256 public nextRequestId;

    mapping(uint256 => address) public loans;
    uint256 public nextLoanId;

    mapping(address => mapping(uint256 => bool)) public usedNonces;

    constructor(
        address _temporalGovernor,
        address _comptroller,
        address _creditLoanImplementation,
        address _backendSigner,
        address _feeRecipient,
        address _pauseGuardian
    ) {
        if (_temporalGovernor == address(0)) revert ZeroAddress();
        if (_comptroller == address(0)) revert ZeroAddress();
        if (_creditLoanImplementation == address(0)) revert ZeroAddress();
        if (_backendSigner == address(0)) revert ZeroAddress();
        if (_feeRecipient == address(0)) revert ZeroAddress();
        if (_pauseGuardian == address(0)) revert ZeroAddress();

        /// Cheap sanity probe: callers must pass the Unitroller (proxy) — a
        /// live comptroller always has ≥1 listed market. The `COMPTROLLER`
        /// implementation address has no state, so this catches the common
        /// operator error of passing impl instead of proxy.
        if (IComptrollerProbe(_comptroller).getAllMarkets().length == 0) {
            revert InvalidComptroller();
        }

        comptroller = _comptroller;
        temporalGovernor = _temporalGovernor;
        creditLoanImplementation = _creditLoanImplementation;
        backendSigner = _backendSigner;
        feeRecipient = _feeRecipient;
        pauseGuardian = _pauseGuardian;

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                CreditTypeHashes.EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("MoonwellCreditMarketplace")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );

        /// Lock the CreditLoan implementation so no one can call
        /// initialize on the impl directly. See spec §6.3.
        InitParams memory sentinel;
        ICreditLoan(_creditLoanImplementation).initialize(sentinel);

        _transferOwnership(_temporalGovernor);
    }

    modifier onlyOwnerOrGuardian() {
        if (msg.sender != owner() && msg.sender != pauseGuardian) {
            revert OnlyOwnerOrGuardian();
        }
        _;
    }

    function pause() external override onlyOwnerOrGuardian {
        _pause();
    }

    function unpause() external override onlyOwner {
        _unpause();
    }

    // ────────────────────────────────────────────────────────────────
    // Admin setters (onlyOwner = Temporal Governor)
    // ────────────────────────────────────────────────────────────────

    function setBackendSigner(address newSigner) external override onlyOwner {
        if (newSigner == address(0)) revert ZeroAddress();
        address previous = backendSigner;
        backendSigner = newSigner;
        emit BackendSignerUpdated(previous, newSigner);
    }

    /// Rotates the CreditLoan implementation used for NEW loans. Existing
    /// clones keep their old logic forever. The new impl must be a fresh
    /// unlocked contract — the setter locks it via initialize(sentinel)
    /// here, reverting AlreadyInitialized if someone pre-locked it.
    function setCreditLoanImplementation(
        address newImpl
    ) external override onlyOwner {
        if (newImpl == address(0)) revert ZeroAddress();
        if (newImpl.code.length == 0) revert InvalidImplementation();

        InitParams memory sentinel;
        ICreditLoan(newImpl).initialize(sentinel);

        address previous = creditLoanImplementation;
        creditLoanImplementation = newImpl;
        emit CreditLoanImplementationUpdated(previous, newImpl);
    }

    /// Whitelist (or un-whitelist) an mToken. When enabling, the caller
    /// must supply a Chainlink feed for the mToken's underlying; that
    /// feed is stored in `principalTokenFeeds` so createLoan's LTV
    /// check can price the borrower's principal. Disabling clears the
    /// per-mToken flag but leaves the underlying's feed intact, because
    /// multiple mTokens can share an underlying and we don't want a
    /// removal to brick their still-live whitelist entries.
    function whitelistMToken(
        address mToken,
        bool allowed,
        AggregatorV3Interface underlyingFeed
    ) external override onlyOwner {
        if (mToken == address(0)) revert ZeroAddress();
        if (allowed) {
            if (address(underlyingFeed) == address(0)) revert ZeroAddress();
            _probeFeed(underlyingFeed);
            isMTokenWhitelisted[mToken] = true;
            principalTokenFeeds[
                IMErc20Underlying(mToken).underlying()
            ] = underlyingFeed;
        } else {
            isMTokenWhitelisted[mToken] = false;
        }
        emit MTokenWhitelisted(mToken, allowed, address(underlyingFeed));
    }

    /// Whitelist (or un-whitelist) a collateral token plus its Chainlink
    /// feed. Disabling clears both the flag and the feed entry because
    /// collateral is a 1:1 token-to-feed relationship (unlike mTokens
    /// which can share an underlying).
    function whitelistCollateralToken(
        address token,
        bool allowed,
        AggregatorV3Interface feed
    ) external override onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (allowed) {
            if (address(feed) == address(0)) revert ZeroAddress();
            _probeFeed(feed);
            collateralFeeds[token] = feed;
            isCollateralWhitelisted[token] = true;
        } else {
            delete collateralFeeds[token];
            isCollateralWhitelisted[token] = false;
        }
        emit CollateralWhitelisted(token, allowed, address(feed));
    }

    function setStalenessWindow(uint32 seconds_) external override onlyOwner {
        if (seconds_ == 0 || seconds_ > MAX_STALENESS_WINDOW) {
            revert InvalidStalenessWindow();
        }
        stalenessWindow = seconds_;
        emit StalenessWindowUpdated(seconds_);
    }

    function setMinOriginationLtvBufferBps(
        uint16 bufferBps
    ) external override onlyOwner {
        if (bufferBps < MIN_LTV_BUFFER_BPS || bufferBps > MAX_LTV_BUFFER_BPS) {
            revert InvalidBufferBps();
        }
        uint16 previous = minOriginationLtvBufferBps;
        minOriginationLtvBufferBps = bufferBps;
        emit MinOriginationLtvBufferBpsUpdated(previous, bufferBps);
    }

    /// Capped at 10_000 bps (100%) — marketplace APR must be no more
    /// than 2× Moonwell's borrow APR. 0 disables the floor (allow
    /// marketplace APR == Moonwell APR, which would still typically
    /// settle but with razor-thin margin).
    function setAprFloorBufferBps(
        uint16 bufferBps
    ) external override onlyOwner {
        if (bufferBps > MAX_LTV_BUFFER_BPS) revert InvalidBufferBps();
        uint16 previous = aprFloorBufferBps;
        aprFloorBufferBps = bufferBps;
        emit AprFloorBufferBpsUpdated(previous, bufferBps);
    }

    function setDefaultParams(
        uint32 gracePeriod,
        uint16 overSeizureBps,
        uint16 consecutiveMissesForDefault,
        uint16 marketplaceFeeBps
    ) external override onlyOwner {
        if (gracePeriod > MAX_GRACE_PERIOD) revert InvalidGracePeriod();
        if (overSeizureBps > MAX_OVER_SEIZURE_BPS) {
            revert InvalidOverSeizureBps();
        }
        if (
            consecutiveMissesForDefault == 0 ||
            consecutiveMissesForDefault > MAX_CONSECUTIVE_MISSES
        ) {
            revert InvalidConsecutiveMisses();
        }
        if (marketplaceFeeBps > MAX_MARKETPLACE_FEE_BPS) {
            revert InvalidMarketplaceFeeBps();
        }

        defaultGracePeriod = gracePeriod;
        defaultOverSeizureBps = overSeizureBps;
        defaultConsecutiveMissesForDefault = consecutiveMissesForDefault;
        defaultMarketplaceFeeBps = marketplaceFeeBps;
        emit DefaultParamsUpdated(
            gracePeriod,
            overSeizureBps,
            consecutiveMissesForDefault,
            marketplaceFeeBps
        );
    }

    function setFeeRecipient(address recipient) external override onlyOwner {
        if (recipient == address(0)) revert ZeroAddress();
        address previous = feeRecipient;
        feeRecipient = recipient;
        emit FeeRecipientUpdated(previous, recipient);
    }

    function setPauseGuardian(address newGuardian) external override onlyOwner {
        if (newGuardian == address(0)) revert ZeroAddress();
        address previous = pauseGuardian;
        pauseGuardian = newGuardian;
        emit PauseGuardianUpdated(previous, newGuardian);
    }

    // ────────────────────────────────────────────────────────────────
    // Views
    // ────────────────────────────────────────────────────────────────

    function isNonceUsed(
        address signer,
        uint256 nonce
    ) external view override returns (bool) {
        return usedNonces[signer][nonce];
    }

    // ────────────────────────────────────────────────────────────────
    // Internal helpers
    // ────────────────────────────────────────────────────────────────

    /// Burns a nonce for `signer`; reverts if already consumed. Used by
    /// cancelOffer/cancelRequest (§7.2) and createLoan (§7.3).
    function _consumeNonce(address signer, uint256 nonce) internal {
        if (usedNonces[signer][nonce]) revert NonceAlreadyUsed();
        usedNonces[signer][nonce] = true;
    }

    function _probeFeed(AggregatorV3Interface feed) internal view {
        /// PriceLib.valueToUsd1e18 scales via `10 ** (18 - feedDecimals)`,
        /// which reverts on underflow. Catch that at whitelist time so a
        /// misconfigured feed fails at the proposal instead of at first
        /// match. Chainlink on Base uses 8 or 18, so this is purely
        /// defensive.
        if (feed.decimals() > 18) revert InvalidFeedDecimals();

        (, int256 answer, , uint256 updatedAt, ) = feed.latestRoundData();
        if (answer <= 0) revert InvalidOraclePrice();
        if (block.timestamp - updatedAt > FEED_LIVENESS_AT_WHITELIST) {
            revert StaleOraclePrice();
        }
    }

    // ────────────────────────────────────────────────────────────────
    // Order book (§7.1, §7.2)
    // ────────────────────────────────────────────────────────────────

    function postOffer(
        Offer calldata offer,
        bytes calldata signature
    ) external override whenNotPaused returns (uint256 offerId) {
        if (offer.expiresAt <= block.timestamp) revert OfferExpired();
        if (offer.maxApr < offer.minApr) revert InvalidAprBounds();
        if (offer.maxTerm < offer.minTerm) revert InvalidTermBounds();
        if (!isMTokenWhitelisted[offer.mToken]) {
            revert NotMTokenWhitelisted();
        }
        /// principalToken is derivable from the mToken, so it must match
        /// or the lender signed something the clone can't deliver: the
        /// clone's `borrow(principal)` always draws `mToken.underlying()`.
        if (
            offer.principalToken != IMErc20Underlying(offer.mToken).underlying()
        ) {
            revert PrincipalMustMatchMTokenUnderlying();
        }
        for (uint256 i = 0; i < offer.acceptedCollateral.length; i++) {
            if (!isCollateralWhitelisted[offer.acceptedCollateral[i]]) {
                revert NotCollateralWhitelisted();
            }
        }

        bytes32 digest = EIP712Lib.hash(
            DOMAIN_SEPARATOR,
            CreditTypeHashes.hashOffer(offer)
        );
        if (
            !SignatureChecker.isValidSignatureNow(
                offer.lender,
                digest,
                signature
            )
        ) {
            revert InvalidSignature(offer.lender);
        }

        if (usedNonces[offer.lender][offer.nonce]) revert NonceAlreadyUsed();
        /// Nonce is NOT consumed here — only at cancel or successful match
        /// (§7.1). Lets a lender re-post a canceled offer under a new nonce.

        offerId = nextOfferId++;
        offers[offerId] = offer;
        /// Override any caller-supplied status (e.g. a malicious `Canceled`)
        /// so fresh posts are always Active.
        offers[offerId].status = OfferStatus.Active;

        emit OfferPosted(
            offerId,
            offer.lender,
            offer.mToken,
            offer.mTokenAmount,
            offer.principalToken,
            offer.maxPrincipal,
            offer.maxApr,
            offer.expiresAt
        );
    }

    function postRequest(
        Request calldata request,
        bytes calldata signature
    ) external override whenNotPaused returns (uint256 requestId) {
        if (request.expiresAt <= block.timestamp) revert RequestExpired();
        if (request.maxTerm < request.minTerm) revert InvalidTermBounds();
        /// The borrower's principalToken only matches if some whitelisted
        /// mToken has it as its underlying (feed was registered via
        /// whitelistMToken). Gatekeep here so dead requests don't clog
        /// the order book.
        if (
            address(principalTokenFeeds[request.principalToken]) == address(0)
        ) {
            revert NotPrincipalTokenWhitelisted();
        }
        if (!isCollateralWhitelisted[request.collateralToken]) {
            revert NotCollateralWhitelisted();
        }

        bytes32 digest = EIP712Lib.hash(
            DOMAIN_SEPARATOR,
            CreditTypeHashes.hashRequest(request)
        );
        if (
            !SignatureChecker.isValidSignatureNow(
                request.borrower,
                digest,
                signature
            )
        ) {
            revert InvalidSignature(request.borrower);
        }

        if (usedNonces[request.borrower][request.nonce]) {
            revert NonceAlreadyUsed();
        }

        requestId = nextRequestId++;
        requests[requestId] = request;
        requests[requestId].status = RequestStatus.Active;

        emit RequestPosted(
            requestId,
            request.borrower,
            request.principalToken,
            request.principal,
            request.collateralToken,
            request.collateralAmount,
            request.maxApr,
            request.expiresAt
        );
    }

    function cancelOffer(
        uint256 offerId,
        bytes calldata cancelSignature
    ) external override {
        Offer storage o = offers[offerId];
        if (o.status != OfferStatus.Active) revert OfferNotActive();

        bytes32 digest = EIP712Lib.hash(
            DOMAIN_SEPARATOR,
            CreditTypeHashes.hashOfferCancel(offerId, o.lender, o.nonce)
        );
        if (
            !SignatureChecker.isValidSignatureNow(
                o.lender,
                digest,
                cancelSignature
            )
        ) {
            revert InvalidSignature(o.lender);
        }

        _consumeNonce(o.lender, o.nonce);
        o.status = OfferStatus.Canceled;
        emit OfferCanceled(offerId);
    }

    function cancelRequest(
        uint256 requestId,
        bytes calldata cancelSignature
    ) external override {
        Request storage r = requests[requestId];
        if (r.status != RequestStatus.Active) revert RequestNotActive();

        bytes32 digest = EIP712Lib.hash(
            DOMAIN_SEPARATOR,
            CreditTypeHashes.hashRequestCancel(requestId, r.borrower, r.nonce)
        );
        if (
            !SignatureChecker.isValidSignatureNow(
                r.borrower,
                digest,
                cancelSignature
            )
        ) {
            revert InvalidSignature(r.borrower);
        }

        _consumeNonce(r.borrower, r.nonce);
        r.status = RequestStatus.Canceled;
        emit RequestCanceled(requestId);
    }

    function getOffer(
        uint256 offerId
    ) external view override returns (Offer memory) {
        return offers[offerId];
    }

    function getRequest(
        uint256 requestId
    ) external view override returns (Request memory) {
        return requests[requestId];
    }

    // ────────────────────────────────────────────────────────────────
    // Match flow (§7.3)
    // ────────────────────────────────────────────────────────────────

    function createLoan(
        uint256 offerId,
        uint256 requestId,
        BackendTerms calldata terms,
        bytes calldata offerSig,
        bytes calldata requestSig,
        bytes calldata backendSig
    )
        external
        override
        whenNotPaused
        nonReentrant
        returns (uint256 loanId, address loanAddress)
    {
        /// All validation, signature verification, nonce burn, bounds, and
        /// LTV checks happen in one helper to keep the outer stack shallow
        /// under optimizer_runs = 1.
        _preValidateMatch(
            offerId,
            requestId,
            terms,
            offerSig,
            requestSig,
            backendSig
        );

        Offer storage o = offers[offerId];
        Request storage r = requests[requestId];

        /// Deterministic salt = keccak256(loanNonce). loanNonce is part
        /// of the signed BackendTerms and unique per match, so the
        /// clone's address is reorg-stable: a re-execution after a chain
        /// reorg lands at the same address. Indexers can rely on the
        /// LoanCreated event's `loanAddress` instead of recomputing.
        loanAddress = Clones.cloneDeterministic(
            creditLoanImplementation,
            keccak256(abi.encode(terms.loanNonce))
        );
        ICreditLoan(loanAddress).initialize(_buildInitParams(o, r, terms));

        IERC20(o.mToken).safeTransferFrom(
            o.lender,
            loanAddress,
            o.mTokenAmount
        );
        IERC20(r.collateralToken).safeTransferFrom(
            r.borrower,
            loanAddress,
            r.collateralAmount
        );

        ICreditLoan(loanAddress).activate();

        o.status = OfferStatus.Consumed;
        r.status = RequestStatus.Consumed;
        loanId = nextLoanId++;
        loans[loanId] = loanAddress;

        _emitLoanCreated(loanId, loanAddress, o, r, terms);
    }

    function _emitLoanCreated(
        uint256 loanId,
        address loanAddress,
        Offer storage o,
        Request storage r,
        BackendTerms calldata terms
    ) private {
        emit LoanCreated(
            loanId,
            loanAddress,
            o.lender,
            r.borrower,
            terms.principal,
            terms.apr,
            terms.term
        );
    }

    function getLoan(uint256 loanId) external view override returns (address) {
        return loans[loanId];
    }

    // ────────────────────────────────────────────────────────────────
    // Match internal helpers
    // ────────────────────────────────────────────────────────────────

    function _preValidateMatch(
        uint256 offerId,
        uint256 requestId,
        BackendTerms calldata terms,
        bytes calldata offerSig,
        bytes calldata requestSig,
        bytes calldata backendSig
    ) private {
        Offer storage o = offers[offerId];
        Request storage r = requests[requestId];
        if (o.status != OfferStatus.Active) revert OfferNotActive();
        if (r.status != RequestStatus.Active) revert RequestNotActive();
        if (o.expiresAt <= block.timestamp) revert OfferExpired();
        if (r.expiresAt <= block.timestamp) revert RequestExpired();

        /// Re-check the mToken whitelist at match time. postOffer already
        /// gates it, but governance can remove an mToken between post and
        /// match (e.g. Moonwell pauses a market, collateral factor drops,
        /// asset develops a risk concern) — stale offers against a
        /// de-whitelisted mToken must not become matchable. Collateral
        /// and principal tokens get the equivalent check via
        /// `collateralFeeds` / `principalTokenFeeds` inside
        /// `_checkOriginationLtv` (removal deletes the feed).
        if (!isMTokenWhitelisted[o.mToken]) revert NotMTokenWhitelisted();

        _verifySignatures(o, r, terms, offerSig, requestSig, backendSig);

        if (terms.validUntil <= block.timestamp) revert BackendTermsExpired();
        if (terms.chainId != block.chainid) revert WrongChain();
        if (terms.factory != address(this)) revert WrongFactory();

        _consumeNonce(o.lender, o.nonce);
        _consumeNonce(r.borrower, r.nonce);
        _consumeNonce(backendSigner, terms.loanNonce);

        _checkTermsBounds(o, r, terms);

        if (IERC20(o.mToken).balanceOf(o.lender) < o.mTokenAmount) {
            revert InsufficientLenderBalance();
        }

        _checkOriginationLtv(o, r, terms);
        _checkAprFloor(o.mToken, terms.apr);
    }

    /// Marketplace per-second rate must clear Moonwell's current borrow
    /// rate plus `aprFloorBufferBps`. Without this, a loan can run the
    /// full term and still revert at `_settle` because the clone's
    /// principalToken balance is short of `borrowBalanceCurrent` —
    /// recoverable via `forceDefault` + the unwind helpers, but ugly UX.
    function _checkAprFloor(
        address mToken,
        uint16 marketplaceAprBps
    ) private view {
        uint256 moonwellRatePerSec = IMTokenBorrowRate(mToken)
            .borrowRatePerTimestamp();
        /// Convert marketplace APR (bps, annual) → per-second rate
        /// scaled to 1e18: bps × 1e14 ÷ secondsPerYear.
        uint256 marketplaceRatePerSec = (uint256(marketplaceAprBps) * 1e14) /
            365 days;
        uint256 minRequired = (moonwellRatePerSec *
            (10_000 + aprFloorBufferBps)) / 10_000;
        if (marketplaceRatePerSec < minRequired) {
            revert MarketplaceAprBelowMoonwellFloor(
                marketplaceRatePerSec,
                minRequired
            );
        }
    }

    /// Split out of createLoan to keep the stack shallow under
    /// optimizer_runs = 1 (§13.1).
    function _verifySignatures(
        Offer storage o,
        Request storage r,
        BackendTerms calldata terms,
        bytes calldata offerSig,
        bytes calldata requestSig,
        bytes calldata backendSig
    ) private view {
        bytes32 d;

        d = EIP712Lib.hash(DOMAIN_SEPARATOR, CreditTypeHashes.hashOffer(o));
        if (!SignatureChecker.isValidSignatureNow(o.lender, d, offerSig)) {
            revert InvalidSignature(o.lender);
        }

        d = EIP712Lib.hash(DOMAIN_SEPARATOR, CreditTypeHashes.hashRequest(r));
        if (!SignatureChecker.isValidSignatureNow(r.borrower, d, requestSig)) {
            revert InvalidSignature(r.borrower);
        }

        d = EIP712Lib.hash(
            DOMAIN_SEPARATOR,
            CreditTypeHashes.hashBackendTerms(terms)
        );
        if (
            !SignatureChecker.isValidSignatureNow(backendSigner, d, backendSig)
        ) {
            revert InvalidSignature(backendSigner);
        }
    }

    function _checkTermsBounds(
        Offer storage o,
        Request storage r,
        BackendTerms calldata terms
    ) private view {
        if (terms.lender != o.lender) revert BoundsViolation("lender");
        if (terms.borrower != r.borrower) revert BoundsViolation("borrower");
        if (terms.mToken != o.mToken) revert BoundsViolation("mToken");
        if (terms.mTokenAmount != o.mTokenAmount) {
            revert BoundsViolation("mTokenAmount");
        }
        if (terms.principalToken != o.principalToken) {
            revert BoundsViolation("principalToken.offer");
        }
        if (terms.principalToken != r.principalToken) {
            revert BoundsViolation("principalToken.request");
        }
        if (terms.principal > o.maxPrincipal) {
            revert BoundsViolation("principal.max");
        }
        if (terms.principal != r.principal) {
            revert BoundsViolation("principal.request");
        }
        if (terms.collateralToken != r.collateralToken) {
            revert BoundsViolation("collateralToken");
        }
        if (terms.collateralAmount != r.collateralAmount) {
            revert BoundsViolation("collateralAmount");
        }
        if (terms.apr < o.minApr || terms.apr > o.maxApr) {
            revert BoundsViolation("apr.offer");
        }
        if (terms.apr > r.maxApr) revert BoundsViolation("apr.request");
        if (terms.term < o.minTerm || terms.term > o.maxTerm) {
            revert BoundsViolation("term.offer");
        }
        if (terms.term < r.minTerm || terms.term > r.maxTerm) {
            revert BoundsViolation("term.request");
        }
        if (!_containsCollateral(o.acceptedCollateral, r.collateralToken)) {
            revert BoundsViolation("collateral.notAccepted");
        }
        if (terms.borrowerCreditTier < o.minBorrowerCreditTier) {
            revert BoundsViolation("creditTier");
        }
    }

    function _containsCollateral(
        address[] memory list,
        address token
    ) private pure returns (bool) {
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == token) return true;
        }
        return false;
    }

    function _checkOriginationLtv(
        Offer storage o,
        Request storage r,
        BackendTerms calldata terms
    ) private view {
        AggregatorV3Interface principalFeed = principalTokenFeeds[
            o.principalToken
        ];
        AggregatorV3Interface collateralFeed = collateralFeeds[
            r.collateralToken
        ];
        if (address(principalFeed) == address(0)) {
            revert NotPrincipalTokenWhitelisted();
        }
        if (address(collateralFeed) == address(0)) {
            revert NotCollateralWhitelisted();
        }

        uint256 collateralUsd1e18 = PriceLib.valueToUsd1e18(
            r.collateralToken,
            r.collateralAmount,
            collateralFeed,
            stalenessWindow
        );
        uint256 principalUsd1e18 = PriceLib.valueToUsd1e18(
            o.principalToken,
            terms.principal,
            principalFeed,
            stalenessWindow
        );
        uint256 requiredUsd1e18 = (principalUsd1e18 *
            (10_000 + minOriginationLtvBufferBps)) / 10_000;
        if (collateralUsd1e18 < requiredUsd1e18) {
            revert InsufficientCollateral(collateralUsd1e18, requiredUsd1e18);
        }
    }

    function _buildInitParams(
        Offer storage o,
        Request storage r,
        BackendTerms calldata terms
    ) private view returns (InitParams memory p) {
        p.lender = o.lender;
        p.borrower = r.borrower;
        p.mToken = o.mToken;
        p.mTokenAmount = o.mTokenAmount;
        p.principalToken = o.principalToken;
        p.principal = terms.principal;
        p.collateralToken = r.collateralToken;
        p.collateralChainlinkFeed = collateralFeeds[r.collateralToken];
        p.principalChainlinkFeed = principalTokenFeeds[o.principalToken];
        p.collateralAmount = r.collateralAmount;
        p.apr = terms.apr;
        p.term = terms.term;
        p.schedule = terms.schedule;
        p.gracePeriod = terms.gracePeriod;
        p.overSeizureBps = terms.overSeizureBps;
        p.consecutiveMissesForDefault = terms.consecutiveMissesForDefault;
        p.marketplaceFeeBps = terms.marketplaceFeeBps;
        p.feeRecipient = terms.feeRecipient;
        p.backendSignerAtOrigination = backendSigner;
        p.stalenessWindow = stalenessWindow;
        p.comptrollerAddr = comptroller;
    }
}
