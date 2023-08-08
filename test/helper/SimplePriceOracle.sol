// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "@protocol/MErc20.sol";
import "@protocol/Oracles/PriceOracle.sol";

contract SimplePriceOracle is PriceOracle {
    mapping(address => uint) prices;
    event PricePosted(address asset, uint previousPriceMantissa, uint requestedPriceMantissa, uint newPriceMantissa);

    address public admin;

    constructor() {
        admin = msg.sender;
    }

    function getUnderlyingPrice(MToken mToken) override public view returns (uint) {
        if (compareStrings(mToken.symbol(), "mGLMR")) {
            return 1e18;
        } else {
            return prices[address(MErc20(address(mToken)).underlying())];
        }
    }

    function setUnderlyingPrice(MToken mToken, uint underlyingPriceMantissa) public {
        require(msg.sender == admin, "Only admin can set the price");

        address asset = address(MErc20(address(mToken)).underlying());
        emit PricePosted(asset, prices[asset], underlyingPriceMantissa, underlyingPriceMantissa);
        prices[asset] = underlyingPriceMantissa;
    }

    function setDirectPrice(address asset, uint price) public {
        require(msg.sender == admin, "Only admin can set the price");

        emit PricePosted(asset, prices[asset], price, price);
        prices[asset] = price;
    }

    // v1 price oracle interface for use as backing of proxy
    function assetPrices(address asset) external view returns (uint) {
        return prices[asset];
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}
