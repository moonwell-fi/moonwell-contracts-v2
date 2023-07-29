pragma solidity 0.8.19;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {WETH9} from "@protocol/core/router/IWETH.sol";
import {MErc20} from "@protocol/core/MErc20.sol";

/// @notice WETH router for depositing raw ETH into Moonwell by wrapping into WETH then calling mint
/// allows for a single transaction to remove ETH from Moonwell
contract WETHRouter {
    using SafeERC20 for IERC20;

    /// @notice The WETH9 contract
    WETH9 public immutable weth;

    /// @notice The mToken contract
    MErc20 public immutable mToken;

    /// @notice construct the WETH router
    /// @param _weth The WETH9 contract
    /// @param _mToken The mToken contract
    constructor(WETH9 _weth, MErc20 _mToken) {
        weth = _weth;
        mToken = _mToken;
        _weth.approve(address(_mToken), type(uint256).max);
    }

    /// @notice Deposit ETH into the Moonwell protocol
    /// @param recipient The address to receive the mToken
    function mint(address recipient) external payable {
        weth.deposit{value: msg.value}();

        require(mToken.mint(msg.value) == 0, "WETHRouter: mint failed");

        IERC20(address(mToken)).safeTransfer(
            recipient,
            mToken.balanceOf(address(this))
        );
    }

    /// @notice Redeem mToken for ETH
    /// @param mTokenRedeemAmount The amount of mToken to redeem
    /// @param recipient The address to receive the ETH
    function redeem(uint256 mTokenRedeemAmount, address recipient) external {
        IERC20(address(mToken)).safeTransferFrom(
            msg.sender,
            address(this),
            mTokenRedeemAmount
        );

        require(
            mToken.redeem(mTokenRedeemAmount) == 0,
            "WETHRouter: redeem failed"
        );

        weth.withdraw(weth.balanceOf(address(this)));

        (bool success, ) = payable(recipient).call{
            value: address(this).balance
        }("");
        require(success, "WETHRouter: ETH transfer failed");
    }

    receive() external payable {
        require(msg.sender == address(weth), "WETHRouter: not weth");   // only accept ETH via fallback from the WETH contract
    }
}
