// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "@openzeppelin-contracts/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";

contract StandardToken is ERC20 {
    uint8 _decimals;

    constructor(
        uint256 _initialAmount,
        string memory _tokenName,
        uint8 _decimalUnits,
        string memory _tokenSymbol
    ) ERC20(_tokenName, _tokenSymbol) {
        _mint(msg.sender, _initialAmount);
        _decimals = _decimalUnits;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}

contract FaucetToken is StandardToken {
    constructor(
        uint256 _initialAmount,
        string memory _tokenName,
        uint8 _decimalUnits,
        string memory _tokenSymbol
    ) StandardToken(_initialAmount, _tokenName, _decimalUnits, _tokenSymbol) {}

    function allocateTo(address _owner, uint256 value) public {
        _mint(_owner, value);
        emit Transfer(address(this), _owner, value);
    }
}

contract FaucetTokenWithPermit is FaucetToken, ERC20Permit {
    constructor(
        uint256 _initialAmount,
        string memory _tokenName,
        uint8 _decimalUnits,
        string memory _tokenSymbol
    )
        FaucetToken(_initialAmount, _tokenName, _decimalUnits, _tokenSymbol)
        ERC20Permit(_tokenName)
    {}

    // Super dumb that OZ removed dynamic decimals :(
    // See https://github.com/OpenZeppelin/openzeppelin-contracts/issues/2613
    function decimals()
        public
        view
        override(ERC20, StandardToken)
        returns (uint8)
    {
        return _decimals;
    }
}
