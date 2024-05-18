pragma solidity 0.8.19;

import {MoonwellERC4626Eth} from "@protocol/4626/MoonwellERC4626Eth.sol";
import {WETH9} from "@protocol/router/IWETH.sol";

/// @title ERC4626EthRouter contract.
/// @notice immutable router contract for ERC4626 vaults.
/// takes ETH in, wraps to WETH, and calls mint/deposit on the vault.
/// Any excess WETH is refunded back to the sender.
contract ERC4626EthRouter {
    ///
    /// ------------------------------------------------
    /// ------------------------------------------------
    /// ------------ KEY CONTRACT INVARIANTS -----------
    /// ------------------------------------------------
    /// ------------------------------------------------

    /// 1). contract never has any ether balance left over
    /// after a deposit or mint call

    /// 2). contract never has any WETH balance left over
    /// after a deposit or mint call

    /// 3). contract never has any WETH allowance to any
    /// address after a deposit or mint call

    /// ------------------------------------------------
    /// ------------------------------------------------
    /// ------------------ IMMUTABLES ------------------
    /// ------------------------------------------------
    /// ------------------------------------------------

    /// @notice The WETH9 contract
    WETH9 public immutable weth;

    /// @notice construct the 4626 router
    /// @param _weth The WETH9 contract
    constructor(WETH9 _weth) {
        weth = _weth;
    }

    /// @notice wrap eth and approve WETH to be spent by the
    /// given vault.
    /// @notice refund any excess weth back to the sender
    /// a malicious vault could not drain this contract because
    /// approvals are revoked after each function call.
    /// @param vault The ERC4626 vault to deposit assets to.
    /// @param vault The ERC4626 vault to zero approval to.
    modifier wrapApproveRefundRevoke(address vault) {
        /// 1. wrap eth -> weth
        weth.deposit{value: msg.value}();

        /// 2. approve weth to be spent by vault
        require(weth.approve(vault, msg.value), "APPROVAL_FAILED");

        /// 3. execute the function
        _;

        /// 4. revoke weth approval
        require(weth.approve(vault, 0), "ZEROING_APPROVAL_FAILED");

        /// 5. refund any remaining weth
        uint256 wethBalance = weth.balanceOf(address(this));
        if (wethBalance != 0) {
            require(
                weth.transfer(msg.sender, weth.balanceOf(address(this))),
                "WETH_REFUND_FAILED"
            );
        }
    }

    /// @param vault The ERC4626 vault to mint shares from.
    /// @param to The address to mint shares to.
    /// @param shares The number of shares to mint.
    /// @param maxAmountIn The maximum amount of underlying
    /// assets required for the mint to succeed.
    function mint(
        MoonwellERC4626Eth vault,
        address to,
        uint256 shares,
        uint256 maxAmountIn
    )
        public
        payable
        wrapApproveRefundRevoke(address(vault))
        returns (uint256 amountIn)
    {
        require(
            (amountIn = vault.mint(shares, to)) <= maxAmountIn,
            "MINT_FAILED"
        );
    }

    /// @param vault The ERC4626 vault to deposit assets into.
    /// @param to The address to mint shares to.
    /// @param amount The amount of assets to deposit.
    /// @param minSharesOut The minimum number of shares required for the deposit to succeed.
    function deposit(
        MoonwellERC4626Eth vault,
        address to,
        uint256 amount,
        uint256 minSharesOut
    )
        public
        payable
        wrapApproveRefundRevoke(address(vault))
        returns (uint256 sharesOut)
    {
        require(
            (sharesOut = vault.deposit(amount, to)) >= minSharesOut,
            "DEPOSIT_FAILED"
        );
    }
}
