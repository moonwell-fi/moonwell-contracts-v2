// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

/// @notice Interface for the wstETH contract's stEthPerToken function
interface IWstETH {
    /// @notice Returns the amount of stETH for 1 wstETH
    function stEthPerToken() external view returns (uint256);
}

/// @notice Adapter that wraps the wstETH canonical exchange rate (stEthPerToken)
/// into a Chainlink AggregatorV3Interface. This allows the ChainlinkCompositeOracle
/// to use the on-chain wstETH/stETH rate as a third feed in the 3-oracle composition:
///   wstETH/USD = ETH/USD × stETH/ETH × wstETH/stETH(adapter)
///
/// On L2s (Base, Optimism), Chainlink provides a native wstETH/stETH feed.
/// On Ethereum mainnet, no such feed exists, so this adapter reads the canonical
/// rate directly from the wstETH contract.
contract WstETHExchangeRateAdapter is AggregatorV3Interface {
    /// @notice The wstETH contract address
    IWstETH public immutable wstETH;

    /// @notice Thrown when stEthPerToken returns 0
    error InvalidExchangeRate();

    constructor(address _wstETH) {
        wstETH = IWstETH(_wstETH);
    }

    /// @notice Returns 18, matching the wstETH exchange rate decimals
    function decimals() external pure override returns (uint8) {
        return 18;
    }

    /// @notice Human-readable description of this adapter
    function description() external pure override returns (string memory) {
        return "wstETH/stETH Exchange Rate";
    }

    /// @notice Returns version 1
    function version() external pure override returns (uint256) {
        return 1;
    }

    /// @notice Returns the latest wstETH/stETH exchange rate
    /// @dev roundId and answeredInRound are both set to 1 to satisfy
    /// ChainlinkCompositeOracle's validation: answeredInRound == roundId
    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        uint256 rate = wstETH.stEthPerToken();
        if (rate == 0) revert InvalidExchangeRate();

        return (
            1, // roundId
            int256(rate), // answer (18 decimals)
            block.timestamp, // startedAt
            block.timestamp, // updatedAt
            1 // answeredInRound == roundId
        );
    }

    /// @notice Delegates to latestRoundData regardless of the requested roundId
    function getRoundData(
        uint80
    )
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return this.latestRoundData();
    }

    /// @notice Returns 1 (single perpetual round)
    function latestRound() external pure override returns (uint256) {
        return 1;
    }
}
