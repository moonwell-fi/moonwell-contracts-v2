// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {AggregatorV3Interface} from "@protocol/core/Oracles/AggregatorV3Interface.sol";

/// @notice contract to combine multiple chainlink oracle prices together
/// allows combination of either 2 or 3 chainlink oracles
contract ChainlinkCompositeOracle {
    using SafeCast for *;

    /// @notice reference to a base price feed chainlink oracle
    /// in case of steth or cbeth this would be eth/usd
    address public immutable base;

    /// @notice reference to the first multiplier. in the case of wsteth or cbeth
    /// this is then eth/steth or eth/cbeth
    address public immutable multiplier;

    /// @notice reference to the second multiplier contract
    /// this should be the wsteth/eth conversion contract
    address public immutable secondMultiplier;

    /// @notice scaling factor applied to price, always 18 decimals to avoid additional
    /// logic in the chainlink oracle contract
    /// @dev this is also used for backwards compatability in the ChainlinkOracle.sol contract
    /// and makes that contract think this composite oracle is talking directly to chainlink
    uint8 public constant decimals = 18;

    /// @notice construct the contract
    /// @param baseAddress The base oracle address
    /// @param multiplierAddress The multiplier oracle address
    /// @param secondMultiplierAddress The second multiplier oracle address
    constructor(
        address baseAddress,
        address multiplierAddress,
        address secondMultiplierAddress
    ) {
        base = baseAddress;
        multiplier = multiplierAddress;
        secondMultiplier = secondMultiplierAddress;
    }

    /// @notice Get the latest price of a base/quote pair
    /// interface for compatabililty with getChainlinkPrice function in ChainlinkOracle.sol
    function latestRoundData()
        external
        view
        returns (
            uint80, /// roundId always 0, value unused in ChainlinkOracle.sol
            int256, /// the composite price
            uint256, /// startedAt always 0, value unused in ChainlinkOracle.sol
            uint256, /// always block.timestamp
            uint80 /// answeredInRound always 0, value unused in ChainlinkOracle.sol
        )
    {
        if (secondMultiplier == address(0)) {
            /// if there is only one multiplier, just use that
            return (
                0,
                /// fetch uint256, then cast back to int256, this cast to uint256 is a sanity check
                /// that chainlink did not return a negative value
                getDerivedPrice(base, multiplier, decimals).toInt256(),
                0,
                block.timestamp, /// return current block timestamp
                0
            );
        }

        /// if there is a second multiplier apply it
        return (
            0, /// unused
            getDerivedPriceThreeOracles(
                base,
                multiplier,
                secondMultiplier,
                decimals
            ).toInt256(),
            0, /// unused
            block.timestamp, /// return current block timestamp
            0 /// unused
        );
    }

    /// @notice Get the derived price of a base/quote pair with price data
    /// @param basePrice The price of the base token
    /// @param priceMultiplier The price of the quote token
    /// @param scalingFactor The expected decimals of the derived price scaled up by 10 ** decimals
    function calculatePrice(
        int256 basePrice,
        int256 priceMultiplier,
        int256 scalingFactor
    ) public pure returns (uint256) {
        return ((basePrice * priceMultiplier) / scalingFactor).toUint256();
    }

    /// @notice Get the derived price of a base/quote pair
    /// @param baseAddress The base oracle address
    /// @param multiplierAddress The multiplier oracle address
    /// @param expectedDecimals The expected decimals of the derived price
    /// @dev always returns positive, otherwise reverts as comptroller only accepts positive oracle values
    function getDerivedPrice(
        address baseAddress,
        address multiplierAddress,
        uint8 expectedDecimals
    ) public view returns (uint256) {
        require(
            expectedDecimals > uint8(0) && expectedDecimals <= uint8(18),
            "CLCOracle: Invalid expected decimals"
        );

        int256 scalingFactor = int256(10 ** uint256(expectedDecimals)); /// calculate expected decimals for end quote

        int256 basePrice = getPriceAndScale(baseAddress, expectedDecimals);
        int256 quotePrice = getPriceAndScale(
            multiplierAddress,
            expectedDecimals
        );

        /// both quote and base price should be scaled up to 18 decimals by now if expectedDecimals is 18
        return calculatePrice(basePrice, quotePrice, scalingFactor);
    }

    //// fetch ETH price, multiply by stETH-ETH exchange rate,
    /// then multiply by wstETH-stETH exchange rate
    /// @param usdBaseAddress The base oracle address that gets the base asset price
    /// @param multiplierAddress The multiplier oracle address that gets the multiplier asset price
    /// @param secondMultiplierAddress The second oracle address that gets the second asset price
    /// @param expectedDecimals The amount of decimals the price should have
    /// @return the derived price from all three oracles. Multiply the base price by the multiplier
    /// price, then multiply by the second multiplier price
    function getDerivedPriceThreeOracles(
        address usdBaseAddress,
        address multiplierAddress,
        address secondMultiplierAddress,
        uint8 expectedDecimals
    ) public view returns (uint256) {
        require(
            expectedDecimals > uint8(0) && expectedDecimals <= uint8(18),
            "CLCOracle: Invalid expected decimals"
        );

        /// should never overflow as should return 1e36
        int256 scalingFactor = int256(10 ** uint256(expectedDecimals * 2)); /// calculate expected decimals for end quote

        int256 firstPrice = getPriceAndScale(usdBaseAddress, expectedDecimals);
        int256 secondPrice = getPriceAndScale(
            multiplierAddress,
            expectedDecimals
        );
        int256 thirdPrice = getPriceAndScale(
            secondMultiplierAddress,
            expectedDecimals
        );

        return
            ((firstPrice * secondPrice * thirdPrice) / scalingFactor)
                .toUint256();
    }

    /// @notice Get the price of a base/quote pair
    /// and then scale up to the expected decimals amount
    /// @param oracleAddress The oracle address
    /// @param expectedDecimals The amount of decimals the price should have
    function getPriceAndScale(
        address oracleAddress,
        uint8 expectedDecimals
    ) public view returns (int256) {
        (int256 price, uint8 actualDecimals) = getPriceAndDecimals(
            oracleAddress
        );
        return scalePrice(price, actualDecimals, expectedDecimals);
    }

    /// @notice helper function to retrieve price from chainlink
    /// @param oracleAddress The address of the chainlink oracle
    /// returns the price and then the decimals of the given asset
    /// reverts if price is 0 or if the oracle data is invalid
    function getPriceAndDecimals(
        address oracleAddress
    ) public view returns (int256, uint8) {
        (
            uint80 roundId,
            int256 price,
            ,
            ,
            uint80 answeredInRound
        ) = AggregatorV3Interface(oracleAddress).latestRoundData();
        bool valid = price > 0 && answeredInRound == roundId;
        require(valid, "CLCOracle: Oracle data is invalid");
        uint8 oracleDecimals = AggregatorV3Interface(oracleAddress).decimals();

        return (price, oracleDecimals); /// price always gt 0 at this point
    }

    /// @notice scale price up or down to the desired amount of decimals
    /// @param price The price to scale
    /// @param priceDecimals The amount of decimals the price has
    /// @param expectedDecimals The amount of decimals the price should have
    /// @return the scaled price
    function scalePrice(
        int256 price,
        uint8 priceDecimals,
        uint8 expectedDecimals
    ) public pure returns (int256) {
        if (priceDecimals < expectedDecimals) {
            return
                price * (10 ** uint256(expectedDecimals - priceDecimals)).toInt256();
        } else if (priceDecimals > expectedDecimals) {
            return
                price / (10 ** uint256(priceDecimals - expectedDecimals)).toInt256();
        }

        /// if priceDecimals == expectedDecimals, return price without any changes

        return price;
    }
}
