// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.19;

import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @notice Mock ERC20 token with configurable decimals
/// @dev Inherits from solmate's ERC20 implementation
contract MockERC20Decimals is ERC20 {
    uint8 private immutable _decimals;

    /// @notice Constructor to create a new mock token
    /// @param name_ The name of the token
    /// @param symbol_ The symbol of the token
    /// @param decimals_ The number of decimals for the token
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    /// @notice Override decimals function to return custom value
    /// @return The number of decimals for the token
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /// @notice Mint tokens to an address
    /// @param to The address to mint tokens to
    /// @param amount The amount of tokens to mint
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Burn tokens from an address
    /// @param from The address to burn tokens from
    /// @param amount The amount of tokens to burn
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
