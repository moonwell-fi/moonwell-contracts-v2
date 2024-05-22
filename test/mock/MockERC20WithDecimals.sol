// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockERC20WithDecimals is ERC20 {
    uint8 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 _dec
    ) ERC20(name, symbol) {
        _decimals = _dec;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address account, uint256 amount) public returns (bool) {
        _mint(account, amount);
        return true;
    }
}
