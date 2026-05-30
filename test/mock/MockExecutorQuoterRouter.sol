// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

/// @notice Mock ExecutorQuoterRouter for xWELL WormholeBridgeAdapter tests.
contract MockExecutorQuoterRouter {
    uint256 public mockQuote;
    uint256 public lastRequestValue;
    uint16 public lastDstChain;
    uint256 public requestCount;

    function setQuote(uint256 _quote) external {
        mockQuote = _quote;
    }

    function quoteExecution(
        uint16,
        bytes32,
        address,
        address,
        bytes calldata,
        bytes calldata
    ) external view returns (uint256) {
        return mockQuote;
    }

    /// @notice On-chain quoting requestExecution (IExecutorQuoterRouter)
    function requestExecution(
        uint16 dstChain,
        bytes32,
        address,
        address,
        bytes calldata,
        bytes calldata
    ) external payable {
        lastRequestValue = msg.value;
        lastDstChain = dstChain;
        requestCount++;
    }

    /// @notice Off-chain quoting requestExecution (IExecutor)
    function requestExecution(
        uint16 dstChain,
        bytes32,
        address,
        bytes calldata,
        bytes calldata,
        bytes calldata
    ) external payable {
        lastRequestValue = msg.value;
        lastDstChain = dstChain;
        requestCount++;
    }
}
