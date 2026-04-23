// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

import {Offer, Request, BackendTerms} from "@protocol/marketplace/CreditTypes.sol";

interface ICreditMarketplaceFactory {
    function postOffer(
        Offer calldata offer,
        bytes calldata signature
    ) external returns (uint256 offerId);

    function postRequest(
        Request calldata request,
        bytes calldata signature
    ) external returns (uint256 requestId);

    function cancelOffer(
        uint256 offerId,
        bytes calldata cancelSignature
    ) external;

    function cancelRequest(
        uint256 requestId,
        bytes calldata cancelSignature
    ) external;

    function createLoan(
        uint256 offerId,
        uint256 requestId,
        BackendTerms calldata terms,
        bytes calldata offerSig,
        bytes calldata requestSig,
        bytes calldata backendSig
    ) external returns (uint256 loanId, address loanAddress);

    function getOffer(uint256 offerId) external view returns (Offer memory);

    function getRequest(
        uint256 requestId
    ) external view returns (Request memory);

    function getLoan(uint256 loanId) external view returns (address);

    function isNonceUsed(
        address signer,
        uint256 nonce
    ) external view returns (bool);

    function setBackendSigner(address newSigner) external;

    function setCreditLoanImplementation(address newImpl) external;

    function whitelistMToken(address mToken, bool allowed) external;

    function whitelistCollateralToken(
        address token,
        AggregatorV3Interface feed
    ) external;

    function removeCollateralToken(address token) external;

    function whitelistPrincipalToken(
        address token,
        AggregatorV3Interface feed
    ) external;

    function removePrincipalToken(address token) external;

    function setStalenessWindow(uint32 seconds_) external;

    function setMinOriginationLtvBufferBps(uint16 bufferBps) external;

    function setDefaultParams(
        uint32 gracePeriod,
        uint16 overSeizureBps,
        uint16 consecutiveMissesForDefault,
        uint16 marketplaceFeeBps
    ) external;

    function setFeeRecipient(address recipient) external;

    function setPauseGuardian(address newGuardian) external;

    function pause() external;

    function unpause() external;
}
