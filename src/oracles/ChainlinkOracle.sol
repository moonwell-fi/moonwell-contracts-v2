// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "../EIP20Interface.sol";
import "../MErc20.sol";
import "../SafeMath.sol";
import "./AggregatorV3Interface.sol";
import "./PriceOracle.sol";

/// @notice contract that stores all chainlink oracle addresses for each respective underlying asset
contract ChainlinkOracle is PriceOracle {
    /// @dev redundant as used with solidity 0.8.0,
    /// but used to not make code changes around math
    using SafeMath for uint256;

    /// @notice Administrator for this contract
    address public admin;

    /// @notice this is deprecated and will not be used
    bytes32 public nativeToken;

    /// @notice overridden prices for assets, not used if unset
    mapping(address => uint256) internal prices;

    /// @notice chainlink feeds for assets, maps the hash of a
    /// token symbol to the corresponding chainlink feed
    mapping(bytes32 => AggregatorV3Interface) internal feeds;

    /// @notice emitted when a new price override by admin is posted
    event PricePosted(
        address asset,
        uint256 previousPriceMantissa,
        uint256 requestedPriceMantissa,
        uint256 newPriceMantissa
    );

    /// @notice emitted when a new admin is set
    event NewAdmin(address oldAdmin, address newAdmin);

    /// @notice emitted when a new feed is set
    event FeedSet(address feed, string symbol);

    /// @param _nativeToken The native token symbol, unused in this deployment so it can be anything
    constructor(string memory _nativeToken) {
        admin = msg.sender;
        nativeToken = keccak256(abi.encodePacked(_nativeToken));
    }

    /// @notice Admin only modifier
    modifier onlyAdmin() {
        require(msg.sender == admin, "only admin may call");
        _;
    }

    /// @notice Get the underlying price of a listed mToken asset
    /// @param mToken The mToken to get the underlying price of
    /// @return The underlying asset price mantissa scaled by 1e18
    function getUnderlyingPrice(MToken mToken)
        public
        view
        override
        returns (uint256)
    {
        string memory symbol = mToken.symbol();
        if (keccak256(abi.encodePacked(symbol)) == nativeToken) {
            /// @dev this branch should never get called as native tokens are not supported on this deployment
            return getChainlinkPrice(getFeed(symbol));
        } else {
            return getPrice(mToken);
        }
    }

    /// @notice Get the underlying price of a token
    /// @param mToken The mToken to get the underlying price of
    /// @return price The underlying asset price mantissa scaled by 1e18
    /// @dev if the admin sets the price override, this function will
    /// return that instead of the chainlink price
    function getPrice(MToken mToken) internal view returns (uint256 price) {
        EIP20Interface token =
            EIP20Interface(MErc20(address(mToken)).underlying());

        if (prices[address(token)] != 0) {
            price = prices[address(token)];
        } else {
            price = getChainlinkPrice(getFeed(token.symbol()));
        }

        uint256 decimalDelta = uint256(18).sub(uint256(token.decimals()));
        // Ensure that we don't multiply the result by 0
        if (decimalDelta > 0) {
            return price.mul(10 ** decimalDelta);
        } else {
            return price;
        }
    }

    /// @notice Get the price of a token from Chainlink
    /// @param feed The Chainlink feed to get the price of
    /// @return The price of the asset from Chainlink scaled by 1e18
    function getChainlinkPrice(AggregatorV3Interface feed)
        internal
        view
        returns (uint256)
    {
        (, int256 answer,, uint256 updatedAt,) =
            AggregatorV3Interface(feed).latestRoundData();
        require(answer > 0, "Chainlink price cannot be lower than 0");
        require(updatedAt != 0, "Round is in incompleted state");

        // Chainlink USD-denominated feeds store answers at 8 decimals
        uint256 decimalDelta = uint256(18).sub(feed.decimals());
        // Ensure that we don't multiply the result by 0
        if (decimalDelta > 0) {
            return uint256(answer).mul(10 ** decimalDelta);
        } else {
            return uint256(answer);
        }
    }

    /// @notice Set the price of an asset overriding the value returned from Chainlink
    /// @param mToken The mToken to set the price of
    /// @param underlyingPriceMantissa The price scaled by mantissa of the asset
    function setUnderlyingPrice(MToken mToken, uint256 underlyingPriceMantissa)
        external
        onlyAdmin
    {
        address asset = address(MErc20(address(mToken)).underlying());
        emit PricePosted(
            asset,
            prices[asset],
            underlyingPriceMantissa,
            underlyingPriceMantissa
        );
        prices[asset] = underlyingPriceMantissa;
    }

    /// @notice Set the price of an asset overriding the value returned from Chainlink
    /// @param asset The asset to set the price of
    /// @param price The price scaled by 1e18 of the asset
    function setDirectPrice(address asset, uint256 price) external onlyAdmin {
        emit PricePosted(asset, prices[asset], price, price);
        prices[asset] = price;
    }

    /// @notice Set the chainlink feed for a given token symbol
    /// @param symbol The symbol of the mToken's underlying token to set the feed for
    /// if the underlying token has symbol of MKR, the symbol would be "MKR"
    /// @param feed The address of the chainlink feed
    function setFeed(string calldata symbol, address feed) external onlyAdmin {
        require(
            feed != address(0) && feed != address(this), "invalid feed address"
        );
        emit FeedSet(feed, symbol);
        feeds[keccak256(abi.encodePacked(symbol))] = AggregatorV3Interface(feed);
    }

    /// @notice Get the chainlink feed for a given token symbol
    /// @param symbol The symbol of the mToken's underlying token to get the feed for
    /// @return The address of the chainlink feed
    function getFeed(string memory symbol)
        public
        view
        returns (AggregatorV3Interface)
    {
        return feeds[keccak256(abi.encodePacked(symbol))];
    }

    /// @notice Get the price of an asset from the override config
    /// @param asset The asset to get the price of
    /// @return The price of the asset scaled by 1e18
    function assetPrices(address asset) external view returns (uint256) {
        return prices[asset];
    }

    /// @notice Set the admin address
    /// @param newAdmin The new admin address
    function setAdmin(address newAdmin) external onlyAdmin {
        address oldAdmin = admin;
        admin = newAdmin;

        emit NewAdmin(oldAdmin, newAdmin);
    }
}
