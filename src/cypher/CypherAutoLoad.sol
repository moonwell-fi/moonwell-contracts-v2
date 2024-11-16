// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin-contracts/contracts/security/Pausable.sol";
import "@openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";

import {IRateLimitedAllowance} from "./IRateLimitedAllowance.sol";

/// @title CypherAutoLoad
/// @notice A contract for managing token transfers with rate-limited allowances
/// @dev Inherits from Pausable and AccessControlEnumerable
contract CypherAutoLoad is Pausable, AccessControlEnumerable {
    /// @notice the executioner role
    bytes32 public constant EXECUTIONER_ROLE = keccak256("EXECUTIONER_ROLE");

    /// @notice the beneficiary who will receive th etokens
    address public beneficiary;

    /// @notice Emitted when tokens are withdrawn
    /// @param token The address of the token being withdrawn
    /// @param user The address of the user from whom tokens are withdrawn
    /// @param beneficiary The address receiving the withdrawn tokens
    /// @param allowedContract The contract which holds the allowance
    /// @param amount The amount of tokens withdrawn
    event Withdraw(
        address indexed token,
        address indexed user,
        address indexed beneficiary,
        address allowedContract,
        uint amount
    );

    /// @notice Emitted when the beneficiary address is changed
    /// @param _beneficiary The new beneficiary address
    event BeneficiaryChanged(address _beneficiary);

    /// @notice Contract constructor
    /// @param _executioner Address to be granted the EXECUTIONER_ROLE
    /// @param _beneficiary Initial beneficiary address
    constructor(address _executioner, address _beneficiary) {
        beneficiary = _beneficiary;
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(EXECUTIONER_ROLE, _executioner);
        _setRoleAdmin(EXECUTIONER_ROLE, DEFAULT_ADMIN_ROLE);
    }

    /// @notice Debit tokens from a user's account and transfer to the beneficiary
    /// @dev Only callable by addresses with EXECUTIONER_ROLE when the contract is not paused
    /// @param rateLimitedAllowance The address of the rate-limited allowance contract
    /// @param tokenAddress The address of the token to be debited
    /// @param userAddress The address of the user from whom tokens will be debited
    /// @param amount The amount of tokens to debit and transfer
    function debit(
        address rateLimitedAllowance,
        address tokenAddress,
        address userAddress,
        uint256 amount
    ) external whenNotPaused onlyRole(EXECUTIONER_ROLE) {
        require(
            rateLimitedAllowance != address(0),
            "Invalid rate limited contract"
        );
        require(tokenAddress != address(0), "Invalid token address");
        require(userAddress != address(0), "Invalid user address");

        IRateLimitedAllowance(rateLimitedAllowance).transferFrom(
            userAddress,
            beneficiary,
            amount,
            tokenAddress
        );

        emit Withdraw(
            tokenAddress,
            userAddress,
            beneficiary,
            rateLimitedAllowance,
            amount
        );
    }

    /// @notice Pause the contract
    /// @dev Can be called by addresses with EXECUTIONER_ROLE or DEFAULT_ADMIN_ROLE
    function pause() external whenNotPaused {
        require(
            hasRole(EXECUTIONER_ROLE, msg.sender) ||
                hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "AccessControl: sender does not have permission"
        );
        _pause();
    }

    /// @notice Unpause the contract
    /// @dev Can only be called by addresses with DEFAULT_ADMIN_ROLE when the contract is paused
    function unpause() external whenPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Set a new beneficiary address
    /// @dev Can only be called by addresses with DEFAULT_ADMIN_ROLE
    /// @param _beneficiary The new beneficiary address to be set
    function setBeneficiary(
        address _beneficiary
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        beneficiary = _beneficiary;

        emit BeneficiaryChanged(_beneficiary);
    }
}
