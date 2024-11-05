// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IAllowanceTransfer} from "../interfaces/IAllowanceTransfer.sol";

library PermitHash {
    bytes32 public constant _PERMIT_DETAILS_TYPEHASH =
        keccak256(
            "PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
        );

    bytes32 public constant _PERMIT_SINGLE_TYPEHASH =
        keccak256(
            "PermitSingle(PermitDetails details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
        );

    bytes32 public constant _PERMIT_BATCH_TYPEHASH =
        keccak256(
            "PermitBatch(PermitDetails[] details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
        );

    function hash(
        IAllowanceTransfer.PermitSingle memory permitSingle
    ) internal pure returns (bytes32) {
        bytes32 permitHash = _hashPermitDetails(permitSingle.details);
        return
            keccak256(
                abi.encode(
                    _PERMIT_SINGLE_TYPEHASH,
                    permitHash,
                    permitSingle.spender,
                    permitSingle.sigDeadline
                )
            );
    }

    function hash(
        IAllowanceTransfer.PermitBatch memory permitBatch
    ) internal pure returns (bytes32) {
        uint256 numPermits = permitBatch.details.length;
        bytes32[] memory permitHashes = new bytes32[](numPermits);
        for (uint256 i = 0; i < numPermits; ++i) {
            permitHashes[i] = _hashPermitDetails(permitBatch.details[i]);
        }
        return
            keccak256(
                abi.encode(
                    _PERMIT_BATCH_TYPEHASH,
                    keccak256(abi.encodePacked(permitHashes)),
                    permitBatch.spender,
                    permitBatch.sigDeadline
                )
            );
    }

    function _hashPermitDetails(
        IAllowanceTransfer.PermitDetails memory details
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(_PERMIT_DETAILS_TYPEHASH, details));
    }
}
