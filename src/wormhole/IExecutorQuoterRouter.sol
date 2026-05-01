// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

/// @notice Local copy of Wormhole Executor interfaces.
/// @dev The SDK's IExecutor.sol uses file-scoped events (Solidity ^0.8.22 feature)
/// which is incompatible with our 0.8.19 pragma. This file contains only the
/// interfaces we need, without file-scoped events.

/// @notice Wormhole Executor interface for off-chain quote flow.
/// The caller obtains a signed quote off-chain from the executor API and
/// passes it when requesting execution.
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

/// @notice On-chain quoting + execution router for the Wormhole Executor framework.
/// Available on chains with a deployed quoter (Base, Optimism, Ethereum).
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

/// @notice Required interface for receiving MultiSig (V1) VAAs from the Executor
interface IVaaV1Receiver {
    function executeVAAv1(bytes memory multiSigVaa) external payable;
}
