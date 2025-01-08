pragma solidity =0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ERC20Mover} from "@protocol/market/ERC20Mover.sol";

contract ERC20HoldingDeposit is ERC20Mover {
    /// @notice the ERC20 token to hold
    address public immutable token;

    /// @notice construct a new ERC20HoldingDeposit
    /// @param _token the ERC20 token to hold
    constructor(address _token, address _owner) ERC20Mover(_owner) {
        token = _token;
    }

    /// @notice current balance of the ERC20 token held by this contract
    function balance() external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
