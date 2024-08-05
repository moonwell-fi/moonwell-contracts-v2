pragma solidity 0.8.19;

import "@protocol/utils/ChainIds.sol";
import {console} from "@forge-std/console.sol";
import {Vm} from "@forge-std/Vm.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {IWormholeReceiver} from "@protocol/wormhole/IWormholeReceiver.sol";

/// @notice Wormhole Token Relayer Adapter
contract WormholeRelayerAdapter {
    using ChainIds for *;

    Vm private constant vm =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 public nonce;

    uint16 public senderChainId;

    /// @notice we need this flag because there are tests where the target is
    /// in the same chain and we need to skip the fork selection
    bool public isMultichainTest;

    uint256 public nativePriceQuote = 1 ether;

    uint256 public callCounter;

    mapping(uint256 chainId => bool shouldRevert) public shouldRevertAtChain;

    mapping(uint16 chainId => bool shouldRevert)
        public shouldRevertQuoteAtChain;

    function setShouldRevertQuoteAtChain(
        uint16[] memory chainIds,
        bool shouldRevert
    ) external {
        for (uint16 i = 0; i < chainIds.length; i++) {
            shouldRevertQuoteAtChain[chainIds[i]] = shouldRevert;
        }
    }

    function setShouldRevertAtChain(
        uint16[] memory chainIds,
        bool _shouldRevert
    ) external {
        for (uint16 i = 0; i < chainIds.length; i++) {
            shouldRevertAtChain[chainIds[i]] = _shouldRevert;
        }
    }

    function setSenderChainId(uint16 _senderChainId) external {
        senderChainId = _senderChainId;
    }

    function setIsMultichainTest(bool _isMultichainTest) external {
        isMultichainTest = _isMultichainTest;
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
        if (shouldRevertAtChain[chainId]) {
            revert("WormholeBridgeAdapter: sendPayloadToEvm revert");
        }

        require(msg.value == nativePriceQuote, "incorrect value");

        uint256 initialFork;

        if (isMultichainTest) {
            initialFork = vm.activeFork();
            vm.selectFork(chainId.toChainId().toForkId());
        }

        // TODO naming;
        require(senderChainId != 0, "senderChainId not set");

        /// immediately call the target
        IWormholeReceiver(targetAddress).receiveWormholeMessages(
            payload,
            new bytes[](0),
            bytes32(uint256(uint160(msg.sender))),
            senderChainId, // chain not the target chain
            bytes32(++nonce)
        );

        if (isMultichainTest) {
            vm.selectFork(initialFork);
        }

        return uint64(nonce);
    }

    /// @notice Retrieve the price for relaying messages to another chain
    /// currently hardcoded to 0.01 ether
    function quoteEVMDeliveryPrice(
        uint16 targetChain,
        uint256,
        uint256
    )
        public
        view
        returns (uint256 nativePrice, uint256 targetChainRefundPerGasUnused)
    {
        if (shouldRevertQuoteAtChain[targetChain]) {
            revert("WormholeBridgeAdapter: quoteEVMDeliveryPrice revert");
        }

        nativePrice = nativePriceQuote;
        targetChainRefundPerGasUnused = 0;
    }
}
