// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

/// @notice Local compatibility interfaces for Wormhole Executor.
/// The SDK's IExecutor.sol uses file-scope events which require Solidity 0.8.22+.
/// These interfaces are identical to the SDK versions but without the file-scope events.

interface IExecutor {
    function requestExecution(
        uint16 dstChain,
        bytes32 dstAddr,
        address refundAddr,
        bytes calldata signedQuote,
        bytes calldata requestBytes,
        bytes calldata relayInstructions
    ) external payable;
}

interface IVaaV1Receiver {
    function executeVAAv1(bytes memory multiSigVaa) external payable;
}

interface IExecutorQuoter {
    function requestQuote(
        uint16 dstChain,
        bytes32 dstAddr,
        address refundAddr,
        bytes calldata requestBytes,
        bytes calldata relayInstructions
    ) external view returns (uint256 requiredMsgValue);

    function requestExecutionQuote(
        uint16 dstChain,
        bytes32 dstAddr,
        address refundAddr,
        bytes calldata requestBytes,
        bytes calldata relayInstructions
    ) external returns (
        uint256 requiredMsgValue,
        bytes32 payee,
        bytes32 quoteBody
    );
}

interface IExecutorQuoterRouter {
    function quoteExecution(
        uint16 dstChain,
        bytes32 dstAddr,
        address refundAddr,
        address quoterAddr,
        bytes calldata requestBytes,
        bytes calldata relayInstructions
    ) external view returns (uint256);

    function requestExecution(
        uint16 dstChain,
        bytes32 dstAddr,
        address refundAddr,
        address quoterAddr,
        bytes calldata requestBytes,
        bytes calldata relayInstructions
    ) external payable;
}
