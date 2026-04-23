// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin-contracts/contracts/security/Pausable.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

import {ICreditMarketplaceFactory} from "@protocol/marketplace/ICreditMarketplaceFactory.sol";
import {ICreditLoan} from "@protocol/marketplace/ICreditLoan.sol";
import {CreditTypeHashes} from "@protocol/marketplace/CreditTypeHashes.sol";
import {InitParams, Offer, Request, BackendTerms} from "@protocol/marketplace/CreditTypes.sol";

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
    error OnlyOwnerOrGuardian();

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
        sentinel.factory = address(this);
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

    function postOffer(
        Offer calldata,
        bytes calldata
    ) external pure override returns (uint256) {
        revert NotImplemented();
    }

    function postRequest(
        Request calldata,
        bytes calldata
    ) external pure override returns (uint256) {
        revert NotImplemented();
    }

    function cancelOffer(uint256, bytes calldata) external pure override {
        revert NotImplemented();
    }

    function cancelRequest(uint256, bytes calldata) external pure override {
        revert NotImplemented();
    }

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

    function getOffer(uint256) external pure override returns (Offer memory) {
        revert NotImplemented();
    }

    function getRequest(
        uint256
    ) external pure override returns (Request memory) {
        revert NotImplemented();
    }

    function getLoan(uint256) external pure override returns (address) {
        revert NotImplemented();
    }

    function isNonceUsed(
        address,
        uint256
    ) external pure override returns (bool) {
        revert NotImplemented();
    }

    function setBackendSigner(address) external pure override {
        revert NotImplemented();
    }

    function setCreditLoanImplementation(address) external pure override {
        revert NotImplemented();
    }

    function whitelistMToken(address, bool) external pure override {
        revert NotImplemented();
    }

    function whitelistCollateralToken(
        address,
        AggregatorV3Interface
    ) external pure override {
        revert NotImplemented();
    }

    function removeCollateralToken(address) external pure override {
        revert NotImplemented();
    }

    function whitelistPrincipalToken(
        address,
        AggregatorV3Interface
    ) external pure override {
        revert NotImplemented();
    }

    function removePrincipalToken(address) external pure override {
        revert NotImplemented();
    }

    function setStalenessWindow(uint32) external pure override {
        revert NotImplemented();
    }

    function setMinOriginationLtvBufferBps(uint16) external pure override {
        revert NotImplemented();
    }

    function setDefaultParams(
        uint32,
        uint16,
        uint16,
        uint16
    ) external pure override {
        revert NotImplemented();
    }

    function setFeeRecipient(address) external pure override {
        revert NotImplemented();
    }

    function setPauseGuardian(address) external pure override {
        revert NotImplemented();
    }
}
