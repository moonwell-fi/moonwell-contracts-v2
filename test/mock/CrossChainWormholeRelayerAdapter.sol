pragma solidity 0.8.19;

import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {IWormholeReceiver} from "@protocol/wormhole/IWormholeReceiver.sol";
import {IMultichainProposal} from "@proposals/proposalTypes/IMultichainProposal.sol";

import "@forge-std/Test.sol";

/// @notice Wormhole Token Relayer Adapter
abstract contract CrossChainWormholeRelayerAdapter is
    IMultichainProposal,
    Test
{
    /// @notice fork ID for base
    uint256 public baseForkId;

    /// @notice fork ID for moonbeam
    uint256 public moonbeamForkId;

    uint256 public nonce;

    uint16 public senderChainId;

    uint256 public nativePriceQuote = 0.01 ether;

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

    /// @notice proposal's actions all happen on base
    function primaryForkId() public view override returns (uint256) {
        return baseForkId;
    }

    function setForkIds(uint256 _baseForkId, uint256 _moonbeamForkId) external {
        require(
            baseForkId == 0 && moonbeamForkId == 0,
            "setForkIds: fork IDs already set"
        );
        require(
            _baseForkId != _moonbeamForkId,
            "setForkIds: fork IDs cannot be the same"
        );

        baseForkId = _baseForkId;
        moonbeamForkId = _moonbeamForkId;

        /// no events as this is tooling and never deployed onchain
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

        uint256 senderFork = vm.activeFork();
        uint16 senderChain = senderFork == moonbeamForkId ? 16 : 30;
        uint256 flipFork = senderFork == moonbeamForkId
            ? baseForkId
            : moonbeamForkId;

        vm.selectFork(flipFork);

        /// immediately call the target
        IWormholeReceiver(targetAddress).receiveWormholeMessages(
            payload,
            new bytes[](0),
            bytes32(uint256(uint160(msg.sender))),
            senderChain, // chain not the target chain
            bytes32(++nonce)
        );

        vm.selectFork(senderFork);

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
