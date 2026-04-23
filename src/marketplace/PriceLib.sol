// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20Metadata} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

library PriceLib {
    error InvalidOraclePrice();
    error StaleOraclePrice();

    function valueToUsd1e18(
        address token,
        uint256 amount,
        AggregatorV3Interface feed,
        uint32 maxAge
    ) internal view returns (uint256) {
        (, int256 answer, , uint256 updatedAt, ) = feed.latestRoundData();
        if (answer <= 0) revert InvalidOraclePrice();
        if (block.timestamp - updatedAt > maxAge) revert StaleOraclePrice();

        uint256 feedDecimals = feed.decimals();
        uint256 tokenDecimals = IERC20Metadata(token).decimals();
        uint256 pricePerTokenUsd1e18 = uint256(answer) *
            (10 ** (18 - feedDecimals));
        return (amount * pricePerTokenUsd1e18) / (10 ** tokenDecimals);
    }
}
