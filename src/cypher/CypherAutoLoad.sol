// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract CypherAutoLoad is Pausable, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant EXECUTIONER_ROLE = keccak256("EXECUTIONER_ROLE");
    address public beneficiary;

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

    modifier anyPrivilegedUser() {
        bool authorized = false;

        if (hasRole(EXECUTIONER_ROLE, _msgSender())) {
            authorized = true;
        } else if (hasRole(DEFAULT_ADMIN_ROLE, _msgSender())) {
            authorized = true;
        }

        require(authorized, "AccessControl: sender does not have permission");
        _;
    }

    function pause() external whenNotPaused anyPrivilegedUser {
        _pause();
    }

    function unpause() external whenPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Debit tokens from a user's account and transfer to a beneficiary.
     * @dev Only the EXECUTIONER_ROLE can call this function.
     * @param tokenAddress The address of the token to be debited.
     * @param userAddress The address of the user from whom tokens will be debited.
     * @param beneficiaryAddress The address of the beneficiary receiving the tokens.
     * @param amount The amount of tokens to debit and transfer.
     * @return A boolean indicating the success of the transfer.
     */
    function debit(
        address tokenAddress,
        address userAddress,
        uint amount
    )
        external
        whenNotPaused
        nonReentrant
        onlyRole(EXECUTIONER_ROLE)
        returns (bool)
    {
        require(userAddress != address(0), "Invalid user address");

        IERC20 token = IERC20(tokenAddress);

        token.safeTransferFrom(userAddress, beneficiary, amount);
        emit Withdraw(tokenAddress, userAddress, beneficiary, amount);
        return true;
    }
}
