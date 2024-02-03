pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {IWormholeReceiver} from "@protocol/wormhole/IWormholeReceiver.sol";

/// @notice Wormhole xERC20 Token Bridge adapter
contract WormholeRelayerAdapter is Test {
    uint256 public nonce;

    bool public shouldRevert;

    uint256 public nativePriceQuote = 0.01 ether;

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    /// @notice Publishes an instruction for the default delivery provider
    /// to relay a payload to the address `targetAddress`
    /// `targetAddress` must implement the IWormholeReceiver interface
    ///
    /// @param targetAddress address to call on targetChain (that implements IWormholeReceiver)
    /// @param payload arbitrary bytes to pass in as parameter in call to `targetAddress`
    /// @return sequence sequence number of published VAA containing delivery instructions
    function sendPayloadToEvm(
        uint16 chainId,
        address targetAddress,
        bytes memory payload,
        uint256, /// shhh
        uint256 /// shhh
    ) external payable returns (uint64) {
        if (shouldRevert) {
            revert("revert");
        }

        require(
            msg.value == nativePriceQuote,
            "WormholeRelayerAdapter: incorrect payment"
        );

        /// immediately call the target
        IWormholeReceiver(targetAddress).receiveWormholeMessages(
            payload,
            new bytes[](0),
            bytes32(uint256(uint160(msg.sender))),
            chainId == 16 ? 30 : 16, // flip chainId since this has to be the sender
            // chain not the target chain
            bytes32(++nonce)
        );

        return uint64(nonce);
    }

    /// @notice Retrieve the price for relaying messages to another chain
    /// currently hardcoded to 0.01 ether
    function quoteEVMDeliveryPrice(
        uint16,
        uint256,
        uint256
    )
        external
        view
        returns (uint256 nativePrice, uint256 targetChainRefundPerGasUnused)
    {
        nativePrice = nativePriceQuote;
        targetChainRefundPerGasUnused = 0;
    }
}

contract WormholeRelayerAdapterRevert {
    function sendPayloadToEvm(
        uint16,
        address,
        bytes memory,
        uint256,
        uint256
    ) external payable returns (uint64) {
        revert("revert");
    }
}
