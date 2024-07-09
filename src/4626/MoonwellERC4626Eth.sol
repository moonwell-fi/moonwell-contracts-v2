// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ReentrancyGuard} from
    "@openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {MoonwellERC4626} from "@protocol/4626/MoonwellERC4626.sol";
import {Comptroller as IMoontroller} from "@protocol/Comptroller.sol";
import {MErc20} from "@protocol/MErc20.sol";

/// @title MoonwellERC4626Eth contract.
/// Allows for deposit WETH into Moonwell by wrapping into WETH then calling
/// mint.
/// @author Elliot Friedman
/// @notice ERC4626 wrapper for Moonwell Finance
contract MoonwellERC4626Eth is MoonwellERC4626, ReentrancyGuard {
    using SafeTransferLib for address;

    /// @param asset_ The underlying asset of the Moonwell mToken.
    /// @param mToken_ The corresponding Moonwell mToken.
    /// @param rewardRecipient_ The address to receive rewards.
    /// @param moontroller_ The Moonwell Moontroller.
    constructor(
        ERC20 asset_,
        MErc20 mToken_,
        address rewardRecipient_,
        IMoontroller moontroller_
    ) MoonwellERC4626(asset_, mToken_, rewardRecipient_, moontroller_) {
        require(
            address(asset_) == address(MErc20(mToken_).underlying()),
            "ASSET_MISMATCH"
        );
    }

    /// @notice checks effects interactions are followed, so no need to use
    /// reentrancy locks, as the contract is safe from reentrancy attacks.
    /// however out of an abundance of caution, reentrancy locks are used.
    /// @param assets The amount of assets to deposit.
    /// @param receiver The address to receive the shares.
    function deposit(uint256 assets, address receiver)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        shares = super.deposit(assets, receiver);
    }

    /// @notice checks effects interactions are followed, so no need to use
    /// reentrancy locks, as the contract is safe from reentrancy attacks.
    /// however out of an abundance of caution, reentrancy locks are used.
    /// @param shares The number of shares to mint.
    /// @param receiver The address to receive the shares.
    function mint(uint256 shares, address receiver)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        assets = super.mint(shares, receiver);
    }

    /// @notice checks effects interactions are followed, so no need to use
    /// reentrancy locks, as the contract is safe from reentrancy attacks.
    /// however out of an abundance of caution, reentrancy locks are used.
    /// @param assets The amount of assets to withdraw.
    /// @param receiver The address to receive the ETH.
    /// @param owner The address of the account to withdraw from.
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) {
                allowance[owner][msg.sender] = allowed - shares;
            }
        }

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        receiver.safeTransferETH(assets);
    }

    /// @notice checks effects interactions are followed, so no need to use
    /// reentrancy locks, as the contract is safe from reentrancy attacks.
    /// however out of an abundance of caution, reentrancy locks are used.
    /// @param shares The number of shares to redeem.
    /// @param receiver The address to receive the ETH.
    /// @param owner The address of the account to redeem from.
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) {
                allowance[owner][msg.sender] = allowed - shares;
            }
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        receiver.safeTransferETH(assets);
    }

    /// @notice callable only by the mToken
    receive() external payable {}
}
