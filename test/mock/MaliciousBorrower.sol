pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {MErc20} from "@protocol/MErc20.sol";

contract MaliciousBorrower {
    /// @notice mWETH contract
    address public immutable mToken;

    /// @notice amount to borrow
    uint256 public borrowAmount;

    /// @notice whether to use cross-contract reentrancy or try regular reentrancy
    bool public crossContractReentrancy;

    constructor(address _mToken, bool _crossContractReentrancy) {
        mToken = _mToken;
        crossContractReentrancy = _crossContractReentrancy;
    }

    function exploit() external {
        address underlying = MErc20(mToken).underlying();
        uint256 amount = ERC20(underlying).balanceOf(address(this));
        borrowAmount = (amount * 6) / 10;

        address[] memory tokens = new address[](1);
        tokens[0] = mToken;

        MErc20(mToken).comptroller().enterMarkets(tokens); /// put up mweth as collateral

        ERC20(underlying).approve(address(mToken), amount);
        MErc20(mToken).mint(amount);
        MErc20(mToken).borrow(borrowAmount);
    }

    receive() external payable {
        if (crossContractReentrancy) {
            /// exit markets
            MErc20(mToken).comptroller().exitMarket(mToken);
        } else {
            MErc20(mToken).borrow(borrowAmount); /// tnis call should revert
        }
    }
}
