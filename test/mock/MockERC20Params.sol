pragma solidity 0.8.19;

import "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract MockERC20Params is ERC20, ERC20Burnable {
    string private _newSymbol;

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function mint(address account, uint256 amount) public returns (bool) {
        _mint(account, amount);
        return true;
    }

    function mockBurn(address account, uint256 amount) public returns (bool) {
        _burn(account, amount);
        return true;
    }

    function setSymbol(string memory _symbol) public {
        _newSymbol = _symbol;
    }

    function symbol() public view virtual override returns (string memory) {
        return _newSymbol;
    }
}
