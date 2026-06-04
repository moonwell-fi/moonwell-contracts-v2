// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

/// @title IOEVWrapperFeed
/// @notice Minimal interface exposed by Moonwell OEV wrappers so that
///         consumers can dereference a registered feed to its underlying
///         raw Chainlink aggregator.
/// @dev Both ChainlinkOEVWrapper and ChainlinkOEVMorphoWrapper already
///      satisfy this interface via their public `priceFeed` state variable.
interface IOEVWrapperFeed {
    function priceFeed() external view returns (AggregatorV3Interface);
}
