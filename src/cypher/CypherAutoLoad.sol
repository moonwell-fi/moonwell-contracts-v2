// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin-contracts/contracts/security/Pausable.sol";
import "@openzeppelin-contracts/contracts/access/AccessControl.sol";

import {IAllowanceTransfer} from "./interfaces/IAllowanceTransfer.sol";

contract CypherAutoLoad is Pausable, AccessControl {
    bytes32 public constant EXECUTIONER_ROLE = keccak256("EXECUTIONER_ROLE");
    address public beneficiary;
    IAllowanceTransfer public moonwellAllowanceTransfer;

    event Withdraw(
        address indexed token,
        address indexed user,
        address indexed beneficiary,
        uint amount
    );

    constructor(address _executioner, address _beneficiary) {
        beneficiary = _beneficiary;
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(EXECUTIONER_ROLE, _executioner);
        _setRoleAdmin(EXECUTIONER_ROLE, DEFAULT_ADMIN_ROLE);
    }

    function pause() external whenNotPaused {
        require(
            hasRole(EXECUTIONER_ROLE, msg.sender) ||
                hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "AccessControl: sender does not have permission"
        );
        _pause();
    }

    function unpause() external whenPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function setBeneficiary(
        address _beneficiary
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        beneficiary = _beneficiary;
    }

    /**
     * @notice Debit tokens from a user's account and transfer to a beneficiary.
     * @dev Only the EXECUTIONER_ROLE can call this function.
     * @param tokenAddress The address of the token to be debited.
     * @param userAddress The address of the user from whom tokens will be debited.
     * @param amount The amount of tokens to debit and transfer.
     */
    function debit(
        address tokenAddress,
        address userAddress,
        uint160 amount
    ) external whenNotPaused onlyRole(EXECUTIONER_ROLE) {
        require(userAddress != address(0), "Invalid user address");
        require(tokenAddress != address(0), "Invalid token address");

        moonwellAllowanceTransfer.transferFrom(
            userAddress,
            beneficiary,
            amount,
            tokenAddress
        );

        emit Withdraw(tokenAddress, userAddress, beneficiary, amount);
    }

    function debitFromVault(
        address vaultAddress,
        address userAddress,
        uint160 amount
    ) external whenNotPaused onlyRole(EXECUTIONER_ROLE) {
        require(userAddress != address(0), "Invalid user address");
        require(vaultAddress != address(0), "Invalid vault address");

        moonwellAllowanceTransfer.withdraw(
            amount,
            beneficiary,
            userAddress,
            vaultAddress
        );

        emit Withdraw(vaultAddress, userAddress, beneficiary, amount);
    }
}
