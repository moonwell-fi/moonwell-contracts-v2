// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {MTokenInterface, MErc20Interface} from "./MTokenInterfaces.sol";
import {EIP20Interface} from "./EIP20Interface.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title OEVProtocolFeeRedeemer
 * @notice This contract collects OEV fees from liquidations and allows anyone to trigger redemptions or adding to the
 * mToken reserves. Contract calls are permissionless.
 * @dev This contract receives fees from ChainlinkOEVWrapper and ChainlinkOEVMorphoWrapper. Handles mToken,
 * underlying token, and native ETH balances.
 */
contract OEVProtocolFeeRedeemer is Ownable {
    event ReservesAddedFromOEV(address indexed mToken, uint256 amount);
    event MarketWhitelisted(address indexed market, bool whitelisted);

    modifier onlyWhitelistedMarkets(address _market) {
        require(
            whitelistedMarkets[_market],
            "OEVProtocolFeeRedeemer: not whitelisted market"
        );
        _;
    }

    mapping(address => bool) public whitelistedMarkets;

    address public immutable MOONWELL_WETH;

    /**
     * @notice Contract constructor
     * @param _moonwellWETH Address for WETH mToken
     */
    constructor(address _moonwellWETH) {
        require(
            _moonwellWETH != address(0),
            "OEVProtocolFeeRedeemer: MOONWELL_WETH cannot be zero address"
        );

        MOONWELL_WETH = _moonwellWETH;
        whitelistedMarkets[_moonwellWETH] = true;

        _transferOwnership(msg.sender);
    }

    /**
     * @notice Allows the contract owner to whitelist or unwhitelist a market
     * @param _market Address of the mToken to whitelist or unwhitelist
     * @param _whitelisted Whether to whitelist the market
     */
    function whitelistMarket(
        address _market,
        bool _whitelisted
    ) external onlyOwner {
        whitelistedMarkets[_market] = _whitelisted;
        emit MarketWhitelisted(_market, _whitelisted);
    }

    /**
     * @notice Allows anyone to redeem this contract's mTokens and add the reserves to the mToken
     * @param _mToken Address of the mToken to redeem and add reserves to
     */
    function redeemAndAddReserves(
        address _mToken
    ) external onlyWhitelistedMarkets(_mToken) {
        (
            MErc20Interface mToken,
            EIP20Interface underlyingToken
        ) = _getMTokenAndUnderlying(_mToken);

        uint256 nativeBalanceBefore = address(this).balance;
        uint256 underlyingBalanceBefore = underlyingToken.balanceOf(
            address(this)
        );
        uint256 mTokenBalance = EIP20Interface(_mToken).balanceOf(
            address(this)
        );

        // Note: mWETH will unwrap to native ETH via WETH_UNWRAPPER
        require(
            mToken.redeem(mTokenBalance) == 0,
            "OEVProtocolFeeRedeemer: redemption failed"
        );

        // If we received native ETH (from mWETH), wrap it back to WETH
        uint256 nativeDelta = address(this).balance - nativeBalanceBefore;
        _wrapNativeToWETH(underlyingToken, nativeDelta);

        uint256 amount = underlyingToken.balanceOf(address(this)) -
            underlyingBalanceBefore;
        _addReservesToMToken(mToken, underlyingToken, amount);
    }

    /**
     * @notice Add reserves from underlying token balance
     * @param _mToken Address of the mToken to add reserves to
     */
    function addReserves(
        address _mToken
    ) external onlyWhitelistedMarkets(_mToken) {
        (
            MErc20Interface mToken,
            EIP20Interface underlyingToken
        ) = _getMTokenAndUnderlying(_mToken);

        uint256 amount = underlyingToken.balanceOf(address(this));
        require(amount > 0, "OEVProtocolFeeRedeemer: no underlying balance");

        _addReservesToMToken(mToken, underlyingToken, amount);
    }

    /**
     * @notice Add reserves from native ETH balance
     */
    function addReservesNative() external {
        (
            MErc20Interface mToken,
            EIP20Interface underlyingToken
        ) = _getMTokenAndUnderlying(MOONWELL_WETH);

        uint256 amount = address(this).balance;
        require(amount > 0, "OEVProtocolFeeRedeemer: no native balance");

        _wrapNativeToWETH(underlyingToken, amount);
        _addReservesToMToken(mToken, underlyingToken, amount);
    }

    /**
     * @dev Get and validate mToken and underlying token
     * @param _mToken Address of the mToken
     * @return mToken The validated mToken interface
     * @return underlyingToken The underlying token interface
     */
    function _getMTokenAndUnderlying(
        address _mToken
    )
        internal
        view
        returns (MErc20Interface mToken, EIP20Interface underlyingToken)
    {
        mToken = MErc20Interface(_mToken);
        underlyingToken = EIP20Interface(
            MTokenInterface(_mToken).underlying()
        );
    }

    /**
     * @dev Wrap native ETH to WETH (if needed)
     * @param underlyingToken The underlying token (should be WETH)
     * @param amount The amount of native ETH to wrap
     */
    function _wrapNativeToWETH(
        EIP20Interface underlyingToken,
        uint256 amount
    ) internal {
        if (amount > 0) {
            (bool success, ) = address(underlyingToken).call{value: amount}(
                abi.encodeWithSignature("deposit()")
            );
            require(success, "OEVProtocolFeeRedeemer: WETH deposit failed");
        }
    }

    /**
     * @dev Add reserves to mToken + emit event
     * @param mToken The mToken to add reserves to
     * @param underlyingToken The underlying token to approve
     * @param amount The amount to add as reserves
     */
    function _addReservesToMToken(
        MErc20Interface mToken,
        EIP20Interface underlyingToken,
        uint256 amount
    ) internal {
        underlyingToken.approve(address(mToken), amount);
        require(
            mToken._addReserves(amount) == 0,
            "OEVProtocolFeeRedeemer: add reserves failed"
        );
        emit ReservesAddedFromOEV(address(mToken), amount);
    }

    receive() external payable {}
}
