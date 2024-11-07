// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin-contracts/contracts/security/Pausable.sol";
import "@openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";

import {IRateLimitedAllowance} from "./IRateLimitedAllowance.sol";

contract CypherAutoLoad is Pausable, AccessControlEnumerable {
    bytes32 public constant EXECUTIONER_ROLE = keccak256("EXECUTIONER_ROLE");

    address public beneficiary;
    IRateLimitedAllowance public rateLimitedAllowance;

    event Withdraw(
        address indexed token,
        address indexed user,
        address indexed beneficiary,
        uint amount
    );

    event BeneficiaryChanged(address _beneficiary);

    constructor(address _executioner, address _beneficiary) {
        beneficiary = _beneficiary;
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(EXECUTIONER_ROLE, _executioner);
        _setRoleAdmin(EXECUTIONER_ROLE, DEFAULT_ADMIN_ROLE);
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
        uint256 amount
    ) external whenNotPaused onlyRole(EXECUTIONER_ROLE) {
        require(tokenAddress != address(0), "Invalid token address");
        require(userAddress != address(0), "Invalid user address");

        (rateLimitedAllowance).transferFrom(
            userAddress,
            beneficiary,
            amount,
            tokenAddress
        );

        emit Withdraw(tokenAddress, userAddress, beneficiary, amount);
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

        emit BeneficiaryChanged(_beneficiary);
    }

    function setRateLimitedAllowance(
        IRateLimitedAllowance _rateLimitedAllowance
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        rateLimitedAllowance = _rateLimitedAllowance;
    }
}
