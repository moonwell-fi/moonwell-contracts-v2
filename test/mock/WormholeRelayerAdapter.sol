pragma solidity 0.8.19;

import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {IWormholeReceiver} from "@protocol/wormhole/IWormholeReceiver.sol";

/// @notice Wormhole xERC20 Token Bridge adapter
contract WormholeRelayerAdapter {
    uint256 public nonce;

    /**
     * @notice Publishes an instruction for the default delivery provider
     * to relay a payload to the address `targetAddress`
     * `targetAddress` must implement the IWormholeReceiver interface
     *
     * @param targetAddress address to call on targetChain (that implements IWormholeReceiver)
     * @param payload arbitrary bytes to pass in as parameter in call to `targetAddress`
     * @return sequence sequence number of published VAA containing delivery instructions
     */
    function sendPayloadToEvm(
        uint16 chainId,
        address targetAddress,
        bytes memory payload,
        uint256, /// shhh
        uint256 /// shhh
    ) external payable returns (uint64) {
        /// immediately call the target
        IWormholeReceiver(targetAddress).receiveWormholeMessages(
            payload,
            new bytes[](0),
            bytes32(uint256(uint160(msg.sender))),
            chainId,
            bytes32(++nonce)
        );

        return uint64(nonce);
    }

    function quoteEVMDeliveryPrice(
        uint16,
        uint256,
        uint256
    )
        external
        view
        returns (
            uint256 nativePriceQuote,
            uint256 targetChainRefundPerGasUnused
        )
    {
        nativePriceQuote = 0.01 ether;
        targetChainRefundPerGasUnused = 0;
    }
}
