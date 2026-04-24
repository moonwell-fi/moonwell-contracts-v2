// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {IWormhole} from "@protocol/wormhole/IWormhole.sol";

/// @notice Mock Wormhole Core Bridge for xWELL WormholeBridgeAdapter tests.
/// Combines publishMessage + parseAndVerifyVM + messageFee + chainId.
contract MockCoreBridgeForAdapter {
    bool public valid = true;
    string public reason = "";
    uint16 public mockChainId;
    uint256 public mockMessageFee;
    uint64 public nextSequence;

    /// @notice storage for configuring parseAndVerifyVM response
    uint16 public vmEmitterChainId;
    bytes32 public vmEmitterAddress;
    uint64 public vmSequence;
    bytes public vmPayload;

    function setValid(bool _valid, string memory _reason) external {
        valid = _valid;
        reason = _reason;
    }

    function setChainId(uint16 _chainId) external {
        mockChainId = _chainId;
    }

    function setMessageFee(uint256 _fee) external {
        mockMessageFee = _fee;
    }

    /// @notice Configure what parseAndVerifyVM will return
    function setVmData(
        uint16 _emitterChainId,
        bytes32 _emitterAddress,
        uint64 _sequence,
        bytes memory _payload
    ) external {
        vmEmitterChainId = _emitterChainId;
        vmEmitterAddress = _emitterAddress;
        vmSequence = _sequence;
        vmPayload = _payload;
    }

    function chainId() external view returns (uint16) {
        return mockChainId;
    }

    function messageFee() external view returns (uint256) {
        return mockMessageFee;
    }

    function publishMessage(
        uint32,
        bytes memory,
        uint8
    ) external payable returns (uint64 sequence) {
        sequence = nextSequence;
        nextSequence++;
    }

    function parseAndVerifyVM(
        bytes calldata encodedVaa
    )
        external
        view
        returns (IWormhole.VM memory vm, bool _valid, string memory _reason)
    {
        vm.hash = keccak256(encodedVaa);
        vm.emitterChainId = vmEmitterChainId;
        vm.emitterAddress = vmEmitterAddress;
        vm.sequence = vmSequence;
        vm.payload = vmPayload;
        vm.consistencyLevel = 200;

        _valid = valid;
        _reason = reason;
    }
}
