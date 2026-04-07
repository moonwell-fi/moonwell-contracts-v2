pragma solidity 0.8.19;

import {Vm} from "@forge-std/Vm.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";

/// @notice Shared helper for delivering BridgeOutSuccess events via processVAA.
///         Used by both unit tests (MultichainBaseTest) and integration tests
///         (MultichainProposalIntegration) after any call that triggers
///         _bridgeOutAll (e.g. governor.propose, voteCollection.emitVotes).
///
///         Usage:
///         ```
///         vm.recordLogs();
///         governor.propose{value: cost}(...);
///         BridgeOutHelper.deliverBridgeOutEvents(vm, adapter, address(governor));
///         ```
library BridgeOutHelper {
    bytes32 private constant BRIDGE_OUT_SUCCESS_TOPIC =
        keccak256("BridgeOutSuccess(uint16,uint256,address,bytes)");

    /// @notice Parse recorded BridgeOutSuccess events and deliver each via processVAA
    /// @param _vm       Foundry VM cheatcode instance
    /// @param adapter   The WormholeRelayerAdapter mock (serves as wormhole core)
    /// @param emitter   The address that published the message (governor or voteCollection)
    function deliverBridgeOutEvents(
        Vm _vm,
        WormholeRelayerAdapter adapter,
        address emitter
    ) internal {
        Vm.Log[] memory logs = _vm.getRecordedLogs();

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == BRIDGE_OUT_SUCCESS_TOPIC) {
                (uint16 dstChainId, , address dst, bytes memory payload) = abi
                    .decode(logs[i].data, (uint16, uint256, address, bytes));

                /// _bridgeOutAll publishes abi.encode(targetChain, targetAddr, payload)
                /// but BridgeOutSuccess emits the raw inner payload. Re-wrap so
                /// the receiver's _bridgeIn can decode the (uint16, address, bytes) envelope.
                bytes memory wrappedPayload = abi.encode(
                    dstChainId,
                    dst,
                    payload
                );
                adapter.deliverBridgeOut(
                    dstChainId,
                    dst,
                    wrappedPayload,
                    emitter
                );
            }
        }
    }
}
