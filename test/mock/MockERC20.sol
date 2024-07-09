pragma solidity 0.8.19;

import "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import
    "@openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract MockERC20 is ERC20, ERC20Burnable {
    constructor() ERC20("MockToken", "MCT") {}

    function mint(address account, uint256 amount) public returns (bool) {
        _mint(account, amount);
        return true;
    }

    function mockBurn(address account, uint256 amount) public returns (bool) {
        _burn(account, amount);
        return true;
    }
}
