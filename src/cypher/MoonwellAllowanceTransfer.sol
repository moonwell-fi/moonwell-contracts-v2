// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {IERC4626} from "@forge-std/interfaces/IERC4626.sol";
import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {PermitHash} from "./libraries/PermitHash.sol";
import {SignatureVerification} from "./libraries/SignatureVerification.sol";
import {EIP712} from "./EIP712.sol";
import {IRateLimitAllowance} from "./interfaces/IRateLimitAllowance.sol";
import {SignatureExpired, InvalidNonce} from "./PermitErrors.sol";
import {Allowance} from "./libraries/Allowance.sol";

abstract contract RateLimitedAllowance is IRateLimitAllowance, EIP712 {
    using SignatureVerification for bytes;
    using SafeTransferLib for ERC20;
    using PermitHash for PermitSingle;
    using PermitHash for PermitBatch;
    using Allowance for PackedAllowance;

    /// @notice Maps users to tokens to spender addresses and information about the approval on the token
    /// @dev Indexed in the order of token owner address, token address, spender address
    /// @dev The stored word saves the allowed amount, expiration on the allowance, and nonce
    mapping(address => mapping(address => mapping(address => PackedAllowance)))
        public allowance;

    mapping(address => mapping(address => mapping(address => PackedAllowance)))
        public allowance;



    /// @inheritdoc IRateLimitAllowance
    function approve(
        address token,
        address spender,
        uint160 amount,
        uint48 expiration,
        uint48 period
    ) external {
        PackedAllowance storage allowed = allowance[msg.sender][token][spender];
        // If the inputted expiration is 0, the allowance only lasts the duration of the block.
        allowed.expiration = expiration == 0
            ? uint48(block.timestamp)
            : expiration;
        allowed.amount = amount;
        allowed.period = period;
        allowed.lastUpdatedTimestamp = block.timestamp;

        emit Approval(msg.sender, token, spender, amount, expiration);
    }

    /// @inheritdoc IAllowanceTransfer
    function transferFrom(
        address from,
        address to,
        uint160 amount,
        address token
    ) external {
        _transfer(from, to, amount, token);
    }

    function withdraw(
        uint160 amount,
        address receiver,
        address owner,
        address vault
    ) external {
        PackedAllowance storage allowed = allowance[owner][vault][msg.sender];

        if (block.timestamp > allowed.expiration)
            revert AllowanceExpired(allowed.expiration);

        uint256 maxAmount = allowed.amount;
        if (maxAmount != type(uint160).max) {
            if (amount > maxAmount) {
                revert InsufficientAllowance(maxAmount);
            } else {
                unchecked {
                    allowed.amount = uint160(maxAmount) - amount;
                }
            }
        }

        IERC4626(vault).withdraw(uint256(amount), receiver, owner);
    }

    /// @notice Internal function for transferring tokens using stored allowances
    /// @dev Will fail if the allowed timeframe has passed
    function _transfer(
        address from,
        address to,
        uint160 amount,
        address token
    ) private {
        PackedAllowance storage allowed = allowance[from][token][msg.sender];

        if (block.timestamp > allowed.expiration)
            revert AllowanceExpired(allowed.expiration);

        uint256 maxAmount = allowed.amount;
        uint256 period = allowed.period;

        if (allowed.lastUpdatedTimestamp + period > block.timestamp) {
            allowed.lastUpdatedTimestamp
        }
            if (maxAmount != type(uint160).max) {
                if (amount > maxAmount) {
                    revert InsufficientAllowance(maxAmount);
                } else {
                    unchecked {
                        allowed.amount = uint160(maxAmount) - amount;
                    }
                }
            }

        // Transfer the tokens from the from address to the recipient.
        ERC20(token).safeTransferFrom(from, to, amount);
    }

    /// @inheritdoc IAllowanceTransfer
    function lockdown(TokenSpenderPair[] calldata approvals) external {
        address owner = msg.sender;
        // Revoke allowances for each pair of spenders and tokens.
        unchecked {
            uint256 length = approvals.length;
            for (uint256 i = 0; i < length; ++i) {
                address token = approvals[i].token;
                address spender = approvals[i].spender;

                allowance[owner][token][spender].amount = 0;
                emit Lockdown(owner, token, spender);
            }
        }
    }

    /// @inheritdoc IAllowanceTransfer
    function invalidateNonces(
        address token,
        address spender,
        uint48 newNonce
    ) external {
        uint48 oldNonce = allowance[msg.sender][token][spender].nonce;

        if (newNonce <= oldNonce) revert InvalidNonce();

        // Limit the amount of nonces that can be invalidated in one transaction.
        unchecked {
            uint48 delta = newNonce - oldNonce;
            if (delta > type(uint16).max) revert ExcessiveInvalidation();
        }

        allowance[msg.sender][token][spender].nonce = newNonce;
        emit NonceInvalidation(msg.sender, token, spender, newNonce, oldNonce);
    }

    /// @notice Sets the new values for amount, expiration, and nonce.
    /// @dev Will check that the signed nonce is equal to the current nonce and then incrememnt the nonce value by 1.
    /// @dev Emits a Permit event.
    function _updateApproval(
        PermitDetails memory details,
        address owner,
        address spender
    ) private {
        uint48 nonce = details.nonce;
        address token = details.token;
        uint160 amount = details.amount;
        uint48 expiration = details.expiration;
        PackedAllowance storage allowed = allowance[owner][token][spender];

        if (allowed.nonce != nonce) revert InvalidNonce();

        allowed.updateAll(amount, expiration, nonce);
        emit Permit(owner, token, spender, amount, expiration, nonce);
    }
}
