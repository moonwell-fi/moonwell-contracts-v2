pragma solidity 0.8.19;

import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {IWormholeReceiver} from "@protocol/wormhole/IWormholeReceiver.sol";

/// @notice Wormhole xERC20 Token Bridge adapter
contract WormholeRelayerAdapter {

    uint64 public sequence;
    uint256 public nonce;

    /**
     * @notice Publishes an instruction for the default delivery provider
     * to relay a payload to the address `targetAddress`
     * `targetAddress` must implement the IWormholeReceiver interface
     *
     * @param targetAddress address to call on targetChain (that implements IWormholeReceiver)
     * @param payload arbitrary bytes to pass in as parameter in call to `targetAddress`
     * @param gasLimit gas limit for call to `targetAddress`
     * @return sequence sequence number of published VAA containing delivery instructions
     */
    function sendPayloadToEvm(
        uint16,
        address targetAddress,
        bytes memory payload,
        uint256,
        uint256 gasLimit
    ) external payable returns (uint64) {
        (bool success, ) = targetAddress.call{ gas: gasLimit }(payload);

        require(success, "WormholeRelayerAdapter: Call to targetAddress failed");

        return ++sequence;
    }

    /**
     * @notice Mock relayer calling `receiveWormholeMessages` into targetAddress 
     * `targetAddress` must implement the IWormholeReceiver interface
     *
     * @param targetAddress address to call on targetChain (that implements IWormholeReceiver)
     * @param payload arbitrary bytes to pass in as parameter in call to `targetAddress`
     */
    function forwardPayloadMessage(bytes memory payload, address senderAddress, uint16 senderChain, IWormholeReceiver targetAddress) external {
        bytes[] memory additionalVaas = new bytes[](0);

        targetAddress.receiveWormholeMessages(payload, additionalVaas, bytes32(uint256(uint160(senderAddress))), senderChain, bytes32(++nonce));

    }
}
 
