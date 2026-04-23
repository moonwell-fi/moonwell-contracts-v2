// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin-contracts/contracts/security/Pausable.sol";
import {ECDSA} from "@openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

import {ICreditMarketplaceFactory} from "@protocol/marketplace/ICreditMarketplaceFactory.sol";
import {ICreditLoan} from "@protocol/marketplace/ICreditLoan.sol";
import {CreditTypeHashes} from "@protocol/marketplace/CreditTypeHashes.sol";
import {EIP712Lib} from "@protocol/marketplace/EIP712Lib.sol";
import {InitParams, Offer, Request, BackendTerms, OfferStatus, RequestStatus} from "@protocol/marketplace/CreditTypes.sol";

interface IComptrollerProbe {
    function getAllMarkets() external view returns (address[] memory);
}

contract CreditMarketplaceFactory is
    ICreditMarketplaceFactory,
    Ownable,
    Pausable
{
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
    error InvalidSignature(address expected, address recovered);
    error InvalidAprBounds();
    error InvalidTermBounds();
    error NotMTokenWhitelisted();
    error NotCollateralWhitelisted();
    error NotPrincipalTokenWhitelisted();

    event BackendSignerUpdated(
        address indexed previousSigner,
        address indexed newSigner
    );
    event CreditLoanImplementationUpdated(
        address indexed previous,
        address indexed updated
    );
    event MTokenWhitelisted(address indexed mToken, bool allowed);
    event CollateralWhitelisted(address indexed token, address indexed feed);
    event CollateralRemoved(address indexed token);
    event PrincipalTokenWhitelisted(
        address indexed token,
        address indexed feed
    );
    event PrincipalTokenRemoved(address indexed token);
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
    uint32 public defaultGracePeriod;
    uint16 public defaultOverSeizureBps;
    uint16 public defaultConsecutiveMissesForDefault;
    uint16 public defaultMarketplaceFeeBps;

    mapping(address => bool) public isMTokenWhitelisted;
    mapping(address => AggregatorV3Interface) public collateralFeeds;
    mapping(address => bool) public isCollateralWhitelisted;
    mapping(address => AggregatorV3Interface) public principalTokenFeeds;
    mapping(address => bool) public isPrincipalTokenWhitelisted;

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

    function whitelistMToken(
        address mToken,
        bool allowed
    ) external override onlyOwner {
        if (mToken == address(0)) revert ZeroAddress();
        isMTokenWhitelisted[mToken] = allowed;
        emit MTokenWhitelisted(mToken, allowed);
    }

    function whitelistCollateralToken(
        address token,
        AggregatorV3Interface feed
    ) external override onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (address(feed) == address(0)) revert ZeroAddress();
        _probeFeed(feed);
        collateralFeeds[token] = feed;
        isCollateralWhitelisted[token] = true;
        emit CollateralWhitelisted(token, address(feed));
    }

    function removeCollateralToken(address token) external override onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        delete collateralFeeds[token];
        isCollateralWhitelisted[token] = false;
        emit CollateralRemoved(token);
    }

    function whitelistPrincipalToken(
        address token,
        AggregatorV3Interface feed
    ) external override onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (address(feed) == address(0)) revert ZeroAddress();
        _probeFeed(feed);
        principalTokenFeeds[token] = feed;
        isPrincipalTokenWhitelisted[token] = true;
        emit PrincipalTokenWhitelisted(token, address(feed));
    }

    function removePrincipalToken(address token) external override onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        delete principalTokenFeeds[token];
        isPrincipalTokenWhitelisted[token] = false;
        emit PrincipalTokenRemoved(token);
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
        if (!isPrincipalTokenWhitelisted[offer.principalToken]) {
            revert NotPrincipalTokenWhitelisted();
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
        address recovered = ECDSA.recover(digest, signature);
        if (recovered != offer.lender) {
            revert InvalidSignature(offer.lender, recovered);
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
        if (!isPrincipalTokenWhitelisted[request.principalToken]) {
            revert NotPrincipalTokenWhitelisted();
        }
        if (!isCollateralWhitelisted[request.collateralToken]) {
            revert NotCollateralWhitelisted();
        }

        bytes32 digest = EIP712Lib.hash(
            DOMAIN_SEPARATOR,
            CreditTypeHashes.hashRequest(request)
        );
        address recovered = ECDSA.recover(digest, signature);
        if (recovered != request.borrower) {
            revert InvalidSignature(request.borrower, recovered);
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
        address recovered = ECDSA.recover(digest, cancelSignature);
        if (recovered != o.lender) {
            revert InvalidSignature(o.lender, recovered);
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
        address recovered = ECDSA.recover(digest, cancelSignature);
        if (recovered != r.borrower) {
            revert InvalidSignature(r.borrower, recovered);
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
    // Stubs (PR5: createLoan)
    // ────────────────────────────────────────────────────────────────

    function createLoan(
        uint256,
        uint256,
        BackendTerms calldata,
        bytes calldata,
        bytes calldata,
        bytes calldata
    ) external pure override returns (uint256, address) {
        revert NotImplemented();
    }

    function getLoan(uint256) external pure override returns (address) {
        revert NotImplemented();
    }
}
