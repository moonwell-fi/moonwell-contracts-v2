pragma solidity 0.8.19;

import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {WETH9} from "@protocol/router/IWETH.sol";
import {MErc20} from "@protocol/MErc20.sol";

/// @notice WETH router for depositing raw ETH into Moonwell by wrapping into WETH then calling mint
/// allows for a single transaction to remove ETH from Moonwell
contract WETHRouter {
    using SafeERC20 for IERC20;

    /// @notice The WETH9 contract
    WETH9 public immutable weth;

    /// @notice The mToken contract
    MErc20 public immutable mToken;

    /// @notice construct the WETH router
    /// @param _weth The WETH9 contract
    /// @param _mToken The mToken contract
    constructor(WETH9 _weth, MErc20 _mToken) {
        weth = _weth;
        mToken = _mToken;
        _weth.approve(address(_mToken), type(uint256).max);
    }

    /// @notice Deposit ETH into the Moonwell protocol
    /// @param recipient The address to receive the mToken
    function mint(address recipient) external payable {
        weth.deposit{value: msg.value}();

        require(mToken.mint(msg.value) == 0, "WETHRouter: mint failed");

        IERC20(address(mToken)).safeTransfer(
            recipient,
            mToken.balanceOf(address(this))
        );
    }

    /// @notice repay borrow using raw ETH with the most up to date borrow balance
    /// @dev all excess ETH will be returned to the sender
    /// @param borrower to repay on behalf of
    function repayBorrowBehalf(address borrower) public payable {
        uint256 received = msg.value;
        uint256 borrows = mToken.borrowBalanceCurrent(borrower);

        if (received > borrows) {
            weth.deposit{value: borrows}();

            require(
                mToken.repayBorrowBehalf(borrower, borrows) == 0,
                "WETHRouter: repay borrow behalf failed"
            );
            
            (bool success, ) = msg.sender.call{value: address(this).balance}(
                ""
            );
            require(success, "WETHRouter: ETH transfer failed");
        } else {
            weth.deposit{value: received}();
            
            require(
                mToken.repayBorrowBehalf(borrower, received) == 0,
                "WETHRouter: repay borrow behalf failed"
            );
        }
    }

    receive() external payable {
        require(msg.sender == address(weth), "WETHRouter: not weth"); // only accept ETH via fallback from the WETH contract
    }
}
