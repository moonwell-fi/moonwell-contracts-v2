pragma solidity =0.8.19;

import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

abstract contract ERC20Mover is Ownable {
    using SafeERC20 for IERC20;

    /// @param _owner the owner of the contract
    constructor(address _owner) {
        _transferOwnership(_owner);
    }

    /// @notice emitted when ERC20 tokens are withdrawn from the contract
    /// @param tokenAddress the address of the ERC20 token withdrawn
    /// @param to the address to receive the tokens
    /// @param amount the amount of tokens withdrawn
    event ERC20Withdrawn(
        address indexed tokenAddress,
        address indexed to,
        uint256 amount
    );

    /// @notice withdraws ERC20 tokens from the contract
    /// @param tokenAddress the address of the ERC20 token
    /// @param to the address to receive the tokens
    /// @param amount the amount of tokens to send
    function withdrawERC20Token(
        address tokenAddress,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(
            to != address(0),
            "ERC20HoldingDeposit: to address cannot be 0"
        );
        require(
            amount > 0,
            "ERC20HoldingDeposit: amount must be greater than 0"
        );

        IERC20(tokenAddress).safeTransfer(to, amount);

        emit ERC20Withdrawn(tokenAddress, to, amount);
    }
}
