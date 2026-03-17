// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Vm} from "@forge-std/Vm.sol";
import {ICoreBridge} from "wormhole-sdk/interfaces/ICoreBridge.sol";
import {toUniversalAddress} from "wormhole-sdk/Utils.sol";
import {DEVNET_GUARDIAN_PRIVATE_KEY} from "@test/mock/MockCoreBridgeExecutor.sol";

/// @notice Helper library to construct and sign valid VAAs for testing
/// using the devnet guardian private key.
library VaaHelper {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Set up a real (forked) core bridge by replacing its guardian set
    /// with one controlled by the devnet guardian key.
    function setUpGuardianOverride(ICoreBridge coreBridge) internal {
        address guardian = vm.addr(DEVNET_GUARDIAN_PRIVATE_KEY);
        uint32 currentIndex = coreBridge.getCurrentGuardianSetIndex();
        uint32 newIndex = currentIndex + 1;

        // Storage slot 3: guardianSetIndex
        vm.store(
            address(coreBridge),
            bytes32(uint256(3)),
            bytes32(uint256(newIndex))
        );

        // Storage slot for guardianSets[newIndex]: keccak256(abi.encode(newIndex, 2))
        bytes32 setSlot = keccak256(abi.encode(uint256(newIndex), uint256(2)));

        // Set keys array length = 1
        vm.store(address(coreBridge), setSlot, bytes32(uint256(1)));

        // Set keys[0] = guardian address
        bytes32 keysDataSlot = keccak256(abi.encode(setSlot));
        vm.store(address(coreBridge), keysDataSlot, bytes32(uint256(uint160(guardian))));

        // expirationTime = 0 (valid)
        vm.store(address(coreBridge), bytes32(uint256(setSlot) + 1), bytes32(uint256(0)));

        // Expire old set
        bytes32 oldSetSlot = keccak256(abi.encode(uint256(currentIndex), uint256(2)));
        vm.store(address(coreBridge), bytes32(uint256(oldSetSlot) + 1), bytes32(uint256(1)));
    }

    /// @notice Craft a signed VAA
    function craftVaa(
        ICoreBridge coreBridge,
        uint16 emitterChainId,
        bytes32 emitterAddress,
        uint64 sequence,
        bytes memory payload
    ) internal view returns (bytes memory) {
        return _encodeAndSign(
            coreBridge.getCurrentGuardianSetIndex(),
            uint32(block.timestamp),
            emitterChainId,
            emitterAddress,
            sequence,
            200, // finalized
            payload
        );
    }

    /// @notice Convenience overload with address emitter
    function craftVaa(
        ICoreBridge coreBridge,
        uint16 emitterChainId,
        address emitterAddress,
        uint64 sequence,
        bytes memory payload
    ) internal view returns (bytes memory) {
        return craftVaa(
            coreBridge,
            emitterChainId,
            toUniversalAddress(emitterAddress),
            sequence,
            payload
        );
    }

    function _encodeAndSign(
        uint32 guardianSetIndex,
        uint32 timestamp,
        uint16 emitterChainId,
        bytes32 emitterAddress,
        uint64 sequence,
        uint8 consistencyLevel,
        bytes memory payload
    ) private view returns (bytes memory) {
        bytes memory body = abi.encodePacked(
            timestamp,
            uint32(0), // nonce
            emitterChainId,
            emitterAddress,
            sequence,
            consistencyLevel,
            payload
        );

        bytes32 bodyHash = keccak256(abi.encodePacked(keccak256(body)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DEVNET_GUARDIAN_PRIVATE_KEY, bodyHash);

        return abi.encodePacked(
            uint8(1),           // version
            guardianSetIndex,
            uint8(1),           // sig count
            uint8(0),           // guardian index
            r, s, v,
            body
        );
    }
}
