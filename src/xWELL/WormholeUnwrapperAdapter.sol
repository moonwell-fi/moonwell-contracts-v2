// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {XERC20Lockbox} from "@protocol/xWELL/XERC20Lockbox.sol";

/// @notice Wormhole Unwrapper xERC20 Token Bridge adapter
/// Allows users coming from an external chain back to Moonbeam
/// to unwrap their xWELL tokens into the underling WELL token.
contract WormholeUnwrapperAdapter is WormholeBridgeAdapter {
    /// @notice lockbox for xERC20, can only be set one time
    address public lockbox;

    /// @notice emitted when the lockbox is set
    /// @param lockbox address of the lockbox
    event LockboxSet(address lockbox);

    /// @notice set the lockbox contract address
    /// @param _lockbox address of the lockbox
    function setLockbox(address _lockbox) external onlyOwner {
        require(
            lockbox == address(0),
            "WormholeUnwrapperAdapter: lockbox already set"
        );
        lockbox = _lockbox;

        emit LockboxSet(_lockbox);
    }

    /// @notice Bridge in funds from the chain to the given user
    /// by minting tokens to this contract, then using those tokens to withdraw from the lockbox
    /// @param chainId chain id funds are bridged from
    /// @param user to bridge in funds to
    /// @param amount of xERC20 tokens to bridge in
    function _bridgeIn(uint256 chainId, address user, uint256 amount)
        internal
        override
    {
        /// mint tokens to this address
        super._bridgeIn(chainId, address(this), amount);

        /// approve lockbox to burn tokens from this address
        IERC20(address(xERC20)).approve(lockbox, amount);

        /// withdraw tokens to the user
        XERC20Lockbox(lockbox).withdrawTo(user, amount);
    }
}
