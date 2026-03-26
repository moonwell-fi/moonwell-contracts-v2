pragma solidity 0.8.19;

import "@protocol/utils/ChainIds.sol";
import {console} from "@forge-std/console.sol";
import {Vm} from "@forge-std/Vm.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {IWormholeReceiver} from "@protocol/wormhole/IWormholeReceiver.sol";

interface IProcessVAA {
    function processVAA(bytes calldata signedVAA) external;
}

/// @notice Mock Wormhole Relayer + Core Bridge adapter for testing.
///         Implements both the legacy relayer interface (sendPayloadToEvm,
///         quoteEVMDeliveryPrice) and the IWormhole core bridge interface
///         (publishMessage, parseAndVerifyVM, messageFee, chainId) so it can
///         serve as both `wormholeRelayer` and `_wormhole()` in tests.
///
///         When `isMultichainTest=true`, publishMessage auto-delivers by
///         switching forks and calling processVAA on the target contract.
contract WormholeRelayerAdapter {
    using ChainIds for *;

    Vm private constant vm =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 public nonce;

    uint16 public senderChainId;

    /// @notice we need this flag because there are tests where the target is
    /// in the same chain and we need to skip the fork selection
    bool public isMultichainTest;

    // @notice some tests need to silence the failure while others expect it to revert
    // e.g of silence failure: check for refunds
    bool public silenceFailure;

    /// @notice Mapping of wormhole chain ID to native price quote
    mapping(uint16 => uint256) public nativePriceQuotes;

    /// @notice Default price quote for backwards compatibility (used when no specific price is set)
    uint256 public constant DEFAULT_NATIVE_PRICE_QUOTE = 0.1 ether;

    uint256 public callCounter;

    /// ---------------------------------------------------------
    /// ----- IWormhole mock state (for processVAA delivery) ----
    /// ---------------------------------------------------------

    /// @notice The wormhole chain ID this mock represents
    uint16 public mockChainId;

    /// @notice Stored by publishMessage, returned by parseAndVerifyVM
    bytes public lastPublishedPayload;

    /// @notice Address that called publishMessage (used as emitter)
    address public lastPublisher;

    /// @notice Nonce of the last publishMessage call (for unique hashes)
    uint256 public lastPublishNonce;

    /// @notice Mapping of wormhole chain ID to shouldRevert flag
    mapping(uint256 chainId => bool shouldRevert) public shouldRevertAtChain;

    mapping(uint16 chainId => bool shouldRevert)
        public shouldRevertQuoteAtChain;

    /// @notice When true, publishMessage reverts (simulates Wormhole core failure)
    bool public shouldRevertPublishMessage;

    /// @notice Constructor - accepts empty arrays for backwards compatibility
    /// @param chainIds Array of wormhole chain IDs (can be empty for default behavior)
    /// @param prices Array of native prices for each chain (can be empty for default behavior)
    constructor(uint16[] memory chainIds, uint256[] memory prices) {
        require(
            chainIds.length == prices.length,
            "WormholeRelayerAdapter: array length mismatch"
        );
        for (uint256 i = 0; i < chainIds.length; i++) {
            nativePriceQuotes[chainIds[i]] = prices[i];
        }
    }

    /// @notice Get the default native price quote (for backwards compatibility)
    function nativePriceQuote() public pure returns (uint256) {
        return DEFAULT_NATIVE_PRICE_QUOTE;
    }

    event MockWormholeRelayerError(string reason);

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

    function setSilenceFailure(bool _silenceFailure) external {
        silenceFailure = _silenceFailure;
    }

    function setSenderChainId(uint16 _senderChainId) external {
        senderChainId = _senderChainId;
    }

    function setIsMultichainTest(bool _isMultichainTest) external {
        isMultichainTest = _isMultichainTest;
    }

    function setMockChainId(uint16 _chainId) external {
        mockChainId = _chainId;
    }

    /// ---------------------------------------------------------
    /// ------------ Legacy relayer interface --------------------
    /// ---------------------------------------------------------

    /// @notice Legacy sendPayloadToEvm — delivers via receiveWormholeMessages
    ///         on the target (the old relayer receiver interface). This is used
    ///         by pre-upgrade contracts that still call wormholeRelayer.sendPayloadToEvm.
    function sendPayloadToEvm(
        uint16 dstChainId,
        address targetAddress,
        bytes memory payload,
        uint256, /// shhh
        uint256 /// shhh
    ) external payable returns (uint64) {
        if (shouldRevertAtChain[dstChainId]) {
            revert("WormholeBridgeAdapter: sendPayloadToEvm revert");
        }

        uint256 expectedValue = nativePriceQuotes[dstChainId];
        if (expectedValue == 0) {
            expectedValue = DEFAULT_NATIVE_PRICE_QUOTE;
        }
        require(msg.value == expectedValue, "incorrect value");

        require(senderChainId != 0, "senderChainId not set");

        ++nonce;

        uint256 initialFork;
        uint256 timestamp = block.timestamp;

        if (isMultichainTest) {
            initialFork = vm.activeFork();
            vm.selectFork(dstChainId.toChainId().toForkId());
            vm.warp(timestamp);
        }

        /// Deliver via receiveWormholeMessages (old relayer path).
        /// Pre-upgrade contracts expect this interface, not processVAA.
        bytes32 senderAddr = bytes32(uint256(uint160(msg.sender)));
        bytes32 deliveryHash = keccak256(
            abi.encode(payload, nonce, block.timestamp)
        );

        if (silenceFailure) {
            try
                IWormholeReceiver(targetAddress).receiveWormholeMessages(
                    payload,
                    new bytes[](0),
                    senderAddr,
                    senderChainId,
                    deliveryHash
                )
            {
                // success
            } catch Error(string memory reason) {
                emit MockWormholeRelayerError(reason);
            }
        } else {
            IWormholeReceiver(targetAddress).receiveWormholeMessages(
                payload,
                new bytes[](0),
                senderAddr,
                senderChainId,
                deliveryHash
            );
        }

        if (isMultichainTest) {
            vm.selectFork(initialFork);
            vm.warp(timestamp);
        }

        return uint64(nonce);
    }

    /// @notice Retrieve the price for relaying messages to another chain
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

        nativePrice = nativePriceQuotes[targetChain];
        if (nativePrice == 0) {
            nativePrice = DEFAULT_NATIVE_PRICE_QUOTE;
        }
        targetChainRefundPerGasUnused = 0;
    }

    /// ---------------------------------------------------------
    /// ------------ IWormhole core bridge interface -------------
    /// ---------------------------------------------------------

    /// @notice Returns the wormhole chain ID for this mock
    function chainId() external view returns (uint16) {
        return mockChainId;
    }

    /// @notice Returns 0 message fee (matches most chains)
    function messageFee() external pure returns (uint256) {
        return 0;
    }

    /// @notice Mock publishMessage — just stores the payload and emitter info.
    ///         Does NOT auto-deliver. Tests should use vm.recordLogs() to capture
    ///         BridgeOutSuccess events from _bridgeOutAll, then call deliverBridgeOut()
    ///         with the (targetChain, targetAddress, payload) from the event.
    function setShouldRevertPublishMessage(bool _shouldRevert) external {
        shouldRevertPublishMessage = _shouldRevert;
    }

    function publishMessage(
        uint32,
        bytes memory payload,
        uint8
    ) external payable returns (uint64) {
        require(
            !shouldRevertPublishMessage,
            "WormholeRelayerAdapter: publishMessage revert"
        );

        lastPublishedPayload = payload;
        lastPublisher = msg.sender;
        lastPublishNonce = ++nonce;

        return uint64(nonce);
    }

    /// @notice Deliver a governance message via processVAA on the target contract.
    ///         Called by test infrastructure after capturing BridgeOutSuccess events.
    ///         The payload/emitter stored by publishMessage is used by parseAndVerifyVM
    ///         when the target's processVAA calls back into this mock.
    /// @param targetChain Wormhole chain ID of the destination (from BridgeOutSuccess event)
    /// @param targetAddr Address to call processVAA on (from BridgeOutSuccess event)
    /// @param payload The governance payload (from BridgeOutSuccess event)
    /// @param emitter The address that published the message (governor or voteCollection)
    function deliverBridgeOut(
        uint16 targetChain,
        address targetAddr,
        bytes memory payload,
        address emitter
    ) external {
        /// Set up state so parseAndVerifyVM returns the right data
        lastPublishedPayload = payload;
        lastPublisher = emitter;
        lastPublishNonce = ++nonce;

        uint256 initialFork;
        uint256 timestamp = block.timestamp;

        if (isMultichainTest) {
            initialFork = vm.activeFork();
            vm.selectFork(targetChain.toChainId().toForkId());
            vm.warp(timestamp);
        }

        /// Temporarily set mockChainId to the target chain
        uint16 savedChainId = mockChainId;
        mockChainId = targetChain;

        bytes memory mockVAA = abi.encode(
            "mock-vaa",
            lastPublishNonce,
            block.timestamp
        );

        if (silenceFailure) {
            try IProcessVAA(targetAddr).processVAA(mockVAA) {
                // success
            } catch Error(string memory reason) {
                emit MockWormholeRelayerError(reason);
            }
        } else {
            IProcessVAA(targetAddr).processVAA(mockVAA);
        }

        mockChainId = savedChainId;

        if (isMultichainTest) {
            vm.selectFork(initialFork);
            vm.warp(timestamp);
        }
    }

    /// @notice Mock parseAndVerifyVM — returns the last published payload
    ///         with the publisher as emitter. Always returns valid=true.
    ///         Called by the target contract's processVAA → _wormhole().parseAndVerifyVM()
    function parseAndVerifyVM(
        bytes calldata VAA
    )
        external
        view
        returns (IWormhole.VM memory _vm, bool valid, string memory reason)
    {
        /// Use a unique hash combining the VAA bytes and publish nonce
        /// to ensure replay protection works correctly
        _vm.hash = keccak256(abi.encode(VAA, lastPublishNonce));
        _vm.emitterChainId = senderChainId;
        _vm.emitterAddress = bytes32(uint256(uint160(lastPublisher)));
        _vm.payload = lastPublishedPayload;

        valid = true;
        reason = "";
    }
}
