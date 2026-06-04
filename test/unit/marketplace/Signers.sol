// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {CommonBase} from "@forge-std/Base.sol";

import {Offer, Request, BackendTerms, CreditAttestation} from "@protocol/marketplace/CreditTypes.sol";
import {CreditTypeHashes} from "@protocol/marketplace/CreditTypeHashes.sol";
import {EIP712Lib} from "@protocol/marketplace/EIP712Lib.sol";

/// Test signing helpers. Subsequent PRs inherit this so every marketplace
/// test produces EIP-712 signatures the exact same way the factory verifies
/// them — typehashes + domain-separator envelope both come from the
/// production libraries.
abstract contract Signers is CommonBase {
    function signOffer(
        Offer memory offer,
        uint256 privateKey,
        bytes32 domainSeparator
    ) internal pure returns (bytes memory) {
        bytes32 digest = EIP712Lib.hash(
            domainSeparator,
            CreditTypeHashes.hashOffer(offer)
        );
        return _sign(digest, privateKey);
    }

    function signRequest(
        Request memory request,
        uint256 privateKey,
        bytes32 domainSeparator
    ) internal pure returns (bytes memory) {
        bytes32 digest = EIP712Lib.hash(
            domainSeparator,
            CreditTypeHashes.hashRequest(request)
        );
        return _sign(digest, privateKey);
    }

    function signBackendTerms(
        BackendTerms memory terms,
        uint256 privateKey,
        bytes32 domainSeparator
    ) internal pure returns (bytes memory) {
        bytes32 digest = EIP712Lib.hash(
            domainSeparator,
            CreditTypeHashes.hashBackendTerms(terms)
        );
        return _sign(digest, privateKey);
    }

    function signCreditAttestation(
        CreditAttestation memory attestation,
        uint256 privateKey,
        bytes32 domainSeparator
    ) internal pure returns (bytes memory) {
        bytes32 digest = EIP712Lib.hash(
            domainSeparator,
            CreditTypeHashes.hashCreditAttestation(attestation)
        );
        return _sign(digest, privateKey);
    }

    function signOfferCancel(
        uint256 offerId,
        address lender,
        uint256 nonce,
        uint256 privateKey,
        bytes32 domainSeparator
    ) internal pure returns (bytes memory) {
        bytes32 digest = EIP712Lib.hash(
            domainSeparator,
            CreditTypeHashes.hashOfferCancel(offerId, lender, nonce)
        );
        return _sign(digest, privateKey);
    }

    function signRequestCancel(
        uint256 requestId,
        address borrower,
        uint256 nonce,
        uint256 privateKey,
        bytes32 domainSeparator
    ) internal pure returns (bytes memory) {
        bytes32 digest = EIP712Lib.hash(
            domainSeparator,
            CreditTypeHashes.hashRequestCancel(requestId, borrower, nonce)
        );
        return _sign(digest, privateKey);
    }

    function _sign(
        bytes32 digest,
        uint256 privateKey
    ) private pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
