// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "./MockERC20.sol";
import "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

interface CToken {
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);
}

contract MockCToken is MockERC20 {
    IERC20 public token;
    bool public error;
    bool public isCEther;

    uint256 private constant EXCHANGE_RATE_SCALE = 1e18;
    uint256 public effectiveExchangeRate = 2;

    mapping(address => uint256) public borrowBalanceRepaid;

    constructor(IERC20 _token, bool _isCEther) {
        token = _token;
        isCEther = _isCEther;
    }

    function setError(bool _error) external {
        error = _error;
    }

    function isCToken() external pure returns (bool) {
        return true;
    }

    function underlying() external view returns (address) {
        return address(token);
    }

    function mint() external payable {
        _mint(msg.sender, msg.value / effectiveExchangeRate);
    }

    function mint(uint256 amount) external returns (uint256) {
        token.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount / effectiveExchangeRate);
        return error ? 1 : 0;
    }

    function redeem(uint256 redeemAmount) external returns (uint256) {
        _burn(msg.sender, redeemAmount);
        token.transfer(msg.sender, redeemAmount * effectiveExchangeRate);

        return error ? 1 : 0;
    }

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256) {
        _burn(msg.sender, redeemAmount / effectiveExchangeRate);
        if (address(this).balance >= redeemAmount) {
            payable(msg.sender).transfer(redeemAmount);
        } else {
            token.transfer(msg.sender, redeemAmount);
        }
        return error ? 1 : 0;
    }

    function repayBorrowBehalf(
        address borrower,
        uint256 amt
    ) external returns (uint256) {
        token.transferFrom(msg.sender, address(this), amt);
        borrowBalanceRepaid[borrower] += amt;

        return error ? 1 : 0;
    }

    function _addReserves(uint256 amount) external returns (uint256) {
        token.transferFrom(msg.sender, address(this), amount);

        return 0;
    }

    function borrowBalanceCurrent(address) external pure returns (uint256) {
        return 1000000000000000000;
    }

    function exchangeRateStored() external view returns (uint256) {
        return EXCHANGE_RATE_SCALE * effectiveExchangeRate; // 2:1
    }
}
