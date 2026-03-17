// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Vm} from "@forge-std/Vm.sol";
import {ICoreBridge, CoreBridgeVM, GuardianSet, GuardianSignature} from "wormhole-sdk/interfaces/ICoreBridge.sol";
import {IVaaV1Receiver} from "@protocol/wormhole/IExecutorCompat.sol";
import {toUniversalAddress, fromUniversalAddress} from "wormhole-sdk/Utils.sol";

// Devnet guardian private key used in Wormhole local/test environments
uint256 constant DEVNET_GUARDIAN_PRIVATE_KEY =
    0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0;

/// @notice Mock Core Bridge for unit tests.
/// Implements publishMessage and parseAndVerifyVM using the devnet guardian key.
/// Does not require a fork — works entirely in-memory.
contract MockCoreBridge is ICoreBridge {
    Vm private constant vm =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint16 private _chainId;
    uint256 private _messageFee;
    uint32 private _guardianSetIndex;
    address private _guardian;
    mapping(address => uint64) private _sequences;

    /// @notice Published messages keyed by emitter+sequence for verification
    struct PublishedMsg {
        uint32 timestamp;
        uint32 nonce;
        uint16 emitterChainId;
        bytes32 emitterAddress;
        uint64 sequence;
        uint8 consistencyLevel;
        bytes payload;
    }

    /// @notice All published messages
    PublishedMsg[] public publishedMessages;

    constructor(uint16 wormholeChainId) {
        _chainId = wormholeChainId;
        _messageFee = 0;
        _guardianSetIndex = 0;
        _guardian = vm.addr(DEVNET_GUARDIAN_PRIVATE_KEY);
    }

    function setMessageFee(uint256 fee) external {
        _messageFee = fee;
    }

    // --- ICoreBridge ---

    function messageFee() external view override returns (uint256) {
        return _messageFee;
    }

    function publishMessage(
        uint32 nonce,
        bytes memory payload,
        uint8 consistencyLevel
    ) external payable override returns (uint64 sequence) {
        require(msg.value >= _messageFee, "insufficient fee");

        sequence = _sequences[msg.sender]++;

        publishedMessages.push(PublishedMsg({
            timestamp: uint32(block.timestamp),
            nonce: nonce,
            emitterChainId: _chainId,
            emitterAddress: toUniversalAddress(msg.sender),
            sequence: sequence,
            consistencyLevel: consistencyLevel,
            payload: payload
        }));

        emit LogMessagePublished(
            msg.sender,
            sequence,
            nonce,
            payload,
            consistencyLevel
        );
    }

    function parseAndVerifyVM(
        bytes calldata encodedVM
    ) external view override returns (CoreBridgeVM memory vm_, bool valid, string memory reason) {
        if (encodedVM.length < 6) return (vm_, false, "too short");
        if (uint8(encodedVM[0]) != 1) return (vm_, false, "invalid version");

        uint8 sigCount = uint8(encodedVM[5]);
        uint256 bodyStart = 6 + (uint256(sigCount) * 66);
        if (encodedVM.length < bodyStart + 51) return (vm_, false, "body too short");

        // Parse body fields directly into vm_ struct
        bytes calldata body = encodedVM[bodyStart:];
        vm_.version = 1;
        vm_.guardianSetIndex = uint32(bytes4(encodedVM[1:5]));
        vm_.timestamp = uint32(bytes4(body[0:4]));
        vm_.nonce = uint32(bytes4(body[4:8]));
        vm_.emitterChainId = uint16(bytes2(body[8:10]));
        vm_.emitterAddress = bytes32(body[10:42]);
        vm_.sequence = uint64(bytes8(body[42:50]));
        vm_.consistencyLevel = uint8(body[50]);
        vm_.payload = body[51:];
        vm_.hash = keccak256(abi.encodePacked(keccak256(body)));

        // Verify first signature against guardian
        if (sigCount == 0) return (vm_, false, "no signatures");

        {
            bytes32 r = bytes32(encodedVM[7:39]);
            bytes32 s = bytes32(encodedVM[39:71]);
            uint8 v = uint8(encodedVM[71]);
            if (ecrecover(vm_.hash, v, r, s) != _guardian)
                return (vm_, false, "invalid signature");
        }

        valid = true;
        reason = "";
    }

    function chainId() external view override returns (uint16) {
        return _chainId;
    }

    function nextSequence(address emitter) external view override returns (uint64) {
        return _sequences[emitter];
    }

    function getGuardianSet(uint32) external view override returns (GuardianSet memory gs) {
        gs.keys = new address[](1);
        gs.keys[0] = _guardian;
        gs.expirationTime = 0;
    }

    function getCurrentGuardianSetIndex() external view override returns (uint32) {
        return _guardianSetIndex;
    }

    // --- Helpers ---

    function publishedMessagesLength() external view returns (uint256) {
        return publishedMessages.length;
    }
}

/// @notice Mock Executor for unit tests.
/// Captures requestExecution calls and can deliver VAAs to targets.
contract MockExecutor {
    Vm private constant vm =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    MockCoreBridge public coreBridge;
    uint16 public senderChainId;
    bool public isMultichainTest;
    bool public silenceFailure;

    mapping(uint16 => bool) public shouldRevertAtChain;

    struct ExecutionRequest {
        uint16 dstChain;
        bytes32 dstAddr;
        address refundAddr;
        bytes requestBytes;
        bytes relayInstructions;
        uint256 amtPaid;
    }

    ExecutionRequest[] public executionRequests;

    constructor(address _coreBridge) {
        coreBridge = MockCoreBridge(_coreBridge);
    }

    function setSenderChainId(uint16 _senderChainId) external {
        senderChainId = _senderChainId;
    }

    function setIsMultichainTest(bool _isMultichainTest) external {
        isMultichainTest = _isMultichainTest;
    }

    function setSilenceFailure(bool _silenceFailure) external {
        silenceFailure = _silenceFailure;
    }

    function setShouldRevertAtChain(
        uint16[] memory chainIds,
        bool _shouldRevert
    ) external {
        for (uint16 i = 0; i < chainIds.length; i++) {
            shouldRevertAtChain[chainIds[i]] = _shouldRevert;
        }
    }

    /// @notice Off-chain quote variant
    function requestExecution(
        uint16 dstChain,
        bytes32 dstAddr,
        address refundAddr,
        bytes calldata, /* signedQuote */
        bytes calldata requestBytes,
        bytes calldata relayInstructions
    ) external payable {
        if (shouldRevertAtChain[dstChain]) {
            revert("MockExecutor: revert at chain");
        }

        executionRequests.push(ExecutionRequest({
            dstChain: dstChain,
            dstAddr: dstAddr,
            refundAddr: refundAddr,
            requestBytes: requestBytes,
            relayInstructions: relayInstructions,
            amtPaid: msg.value
        }));

        // Auto-deliver: craft a signed VAA from the last published message and
        // call executeVAAv1 on the destination
        _autoDeliver(dstChain, dstAddr);
    }

    function _autoDeliver(uint16 dstChain, bytes32 dstAddr) internal {
        uint256 msgCount = coreBridge.publishedMessagesLength();
        if (msgCount == 0) return;

        // Get the most recently published message
        (
            uint32 timestamp,
            uint32 nonce,
            uint16 emitterChainId,
            bytes32 emitterAddress,
            uint64 sequence,
            uint8 consistencyLevel,
            bytes memory payload
        ) = coreBridge.publishedMessages(msgCount - 1);

        // Craft a signed VAA
        bytes memory vaa = _craftVaa(
            timestamp,
            nonce,
            emitterChainId,
            emitterAddress,
            sequence,
            consistencyLevel,
            payload
        );

        // Deliver to destination
        address target = fromUniversalAddress(dstAddr);

        if (silenceFailure) {
            try IVaaV1Receiver(target).executeVAAv1(vaa) {
                // success
            } catch {
                // silenced
            }
        } else {
            IVaaV1Receiver(target).executeVAAv1(vaa);
        }
    }

    function _craftVaa(
        uint32 timestamp,
        uint32 nonce,
        uint16 emitterChainId,
        bytes32 emitterAddress,
        uint64 sequence,
        uint8 consistencyLevel,
        bytes memory payload
    ) internal view returns (bytes memory) {
        uint32 guardianSetIndex = coreBridge.getCurrentGuardianSetIndex();

        // Encode body
        bytes memory body = abi.encodePacked(
            timestamp,
            nonce,
            emitterChainId,
            emitterAddress,
            sequence,
            consistencyLevel,
            payload
        );

        // Double hash for signing
        bytes32 bodyHash = keccak256(abi.encodePacked(keccak256(body)));

        // Sign
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DEVNET_GUARDIAN_PRIVATE_KEY, bodyHash);

        // Encode signature: guardianIndex(1) + r(32) + s(32) + v(1) = 66 bytes
        bytes memory sig = abi.encodePacked(uint8(0), r, s, v);

        // Full VAA: version(1) + guardianSetIndex(4) + sigCount(1) + sig(66) + body
        return abi.encodePacked(
            uint8(1),
            guardianSetIndex,
            uint8(1),
            sig,
            body
        );
    }

    function executionRequestsLength() external view returns (uint256) {
        return executionRequests.length;
    }

    /// @notice Needed to receive refunds
    receive() external payable {}
}

/// @notice On-chain quoter router mock
contract MockExecutorQuoterRouter {
    uint256 public constant DEFAULT_QUOTE = 0.1 ether;
    mapping(uint16 => uint256) public chainQuotes;
    mapping(uint16 => bool) public shouldRevertQuoteAtChain;

    MockExecutor public executor;

    constructor(address _executor) {
        executor = MockExecutor(payable(_executor));
    }

    function setChainQuote(uint16 chain, uint256 quote) external {
        chainQuotes[chain] = quote;
    }

    function setShouldRevertQuoteAtChain(
        uint16[] memory chainIds,
        bool shouldRevert
    ) external {
        for (uint16 i = 0; i < chainIds.length; i++) {
            shouldRevertQuoteAtChain[chainIds[i]] = shouldRevert;
        }
    }

    function quoteExecution(
        uint16 dstChain,
        bytes32,
        address,
        address,
        bytes calldata,
        bytes calldata
    ) external view returns (uint256) {
        if (shouldRevertQuoteAtChain[dstChain]) {
            revert("MockExecutorQuoterRouter: quote revert");
        }
        uint256 quote = chainQuotes[dstChain];
        return quote == 0 ? DEFAULT_QUOTE : quote;
    }

    function requestExecution(
        uint16 dstChain,
        bytes32 dstAddr,
        address refundAddr,
        address,
        bytes calldata requestBytes,
        bytes calldata relayInstructions
    ) external payable {
        // Delegate to executor for auto-delivery
        executor.requestExecution{value: msg.value}(
            dstChain,
            dstAddr,
            refundAddr,
            "", // empty signedQuote
            requestBytes,
            relayInstructions
        );
    }

    receive() external payable {}
}
