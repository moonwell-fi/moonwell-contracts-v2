// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import {IWormholeTrustedSender} from "@protocol/Governance/IWormholeTrustedSender.sol";

/// @notice A contract that manages Wormhole trusted senders
/// Used to allow only certain trusted senders on external chains
/// to pass messages to this contract.
contract WormholeTrustedSender is IWormholeTrustedSender {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// ------------- EVENT -------------

    /// @notice Emitted when a trusted sender is updated
    event TrustedSenderUpdated(uint16 chainId, address addr, bool added);

    /// ------------- MAPPING -----------

    /// @notice Map of chain id => trusted sender
    mapping(uint16 => EnumerableSet.Bytes32Set) private trustedSenders;

    /// ------------- STRUCTS -------------

    /// @notice A trusted sender is a contract that is allowed to emit VAAs
    struct TrustedSender {
        uint16 chainId;
        address addr;
    }

    /// ------------- INTERNAL HELPERS -------------

    /// @dev Updates the list of trusted senders
    /// @param _trustedSenders The list of trusted senders, allowing one
    /// trusted sender per chain id
    function _addTrustedSenders(
        TrustedSender[] memory _trustedSenders
    ) internal virtual {
        unchecked {
            for (uint256 i = 0; i < _trustedSenders.length; i++) {
                _addTrustedSender(
                    _trustedSenders[i].addr,
                    _trustedSenders[i].chainId
                );
            }
        }
    }

    /// @notice Adds a trusted sender to the list
    /// @param trustedSender The trusted sender to add
    /// @param chainId The chain id of the trusted sender to add
    function _addTrustedSender(address trustedSender, uint16 chainId) internal {
        require(
            trustedSenders[chainId].add(addressToBytes(trustedSender)),
            "WormholeTrustedSender: already in list"
        );

        emit TrustedSenderUpdated(
            chainId,
            trustedSender,
            true /// added to list
        );
    }

    /// @notice remove a trusted sender
    /// @param trustedSender The trusted sender to remove
    /// @param chainId The chain id of the trusted sender to remove
    function _removeTrustedSender(
        address trustedSender,
        uint16 chainId
    ) internal {
        require(
            trustedSenders[chainId].remove(addressToBytes(trustedSender)),
            "WormholeTrustedSender: not in list"
        );

        emit TrustedSenderUpdated(
            chainId,
            trustedSender,
            false /// removed from list
        );
    }

    /// @dev Removes trusted senders from the list
    /// @param _trustedSenders The list of trusted senders to remove
    function _removeTrustedSenders(
        TrustedSender[] memory _trustedSenders
    ) internal virtual {
        unchecked {
            for (uint256 i = 0; i < _trustedSenders.length; i++) {
                _removeTrustedSender(
                    _trustedSenders[i].addr,
                    _trustedSenders[i].chainId
                );
            }
        }
    }

    /// ------------- VIEW ONLY API -------------

    /// @notice returns whether or not the address is in the trusted senders list for a given chain
    /// @param chainId The wormhole chain id to check
    /// @param addr The address to check
    function isTrustedSender(
        uint16 chainId,
        bytes32 addr
    ) public view override returns (bool) {
        return trustedSenders[chainId].contains(addr);
    }

    /// @notice returns whether or not the address is in the trusted senders list for a given chain
    /// @param chainId The wormhole chain id to check
    /// @param addr The address to check
    function isTrustedSender(
        uint16 chainId,
        address addr
    ) public view override returns (bool) {
        return isTrustedSender(chainId, addressToBytes(addr));
    }

    /// @notice returns the list of trusted senders for a given chain
    /// @param chainId The wormhole chain id to check
    /// @return The list of trusted senders
    function allTrustedSenders(
        uint16 chainId
    ) external view override returns (bytes32[] memory) {
        bytes32[] memory trustedSendersList = new bytes32[](
            trustedSenders[chainId].length()
        );

        unchecked {
            for (uint256 i = 0; i < trustedSendersList.length; i++) {
                trustedSendersList[i] = trustedSenders[chainId].at(i);
            }
        }

        return trustedSendersList;
    }

    /// @notice Wormhole addresses are denominated in 32 byte chunks. Converting the address to a bytes20
    /// then to a bytes32 *left* aligns it, so we right shift to get the proper data
    /// @param addr The address to convert
    /// @return The address as a bytes32
    function addressToBytes(
        address addr
    ) public pure override returns (bytes32) {
        return bytes32(bytes20(addr)) >> 96;
    }
}
