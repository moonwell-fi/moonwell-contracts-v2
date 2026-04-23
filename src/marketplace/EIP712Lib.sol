// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

library EIP712Lib {
    function hash(
        bytes32 domainSeparator,
        bytes32 structHash
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19\x01", domainSeparator, structHash)
            );
    }
}
