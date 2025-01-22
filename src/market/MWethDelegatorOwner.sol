// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {WETH9} from "@protocol/router/IWETH.sol";
import {MToken} from "@protocol/MToken.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {InterestRateModel} from "@protocol/irm/InterestRateModel.sol";

/// @title MWethDelegatorOwner
/// @notice A contract that owns and manages an mToken, with special handling for WETH
/// @author Moonwell
contract MWethDelegatorOwner is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice The mToken this contract manages
    MToken public mToken;

    /// @notice The WETH contract
    WETH9 public weth;

    /// @notice Emitted when ETH is wrapped to WETH
    event EthWrapped(uint256 amount);

    /// @notice Emitted when admin functions are called on the mToken
    event AdminFunctionCalled(string functionName, bytes data);

    /// @notice Emitted when an arbitrary call is made
    event ArbitraryCallMade(address target, uint256 value, bytes data);

    /// @notice emitted when ERC20 tokens are withdrawn from the contract
    /// @param tokenAddress the address of the ERC20 token withdrawn
    /// @param to the address to receive the tokens
    /// @param amount the amount of tokens withdrawn
    event ERC20Withdrawn(
        address indexed tokenAddress,
        address indexed to,
        uint256 amount
    );

    /// @notice Constructor that disables initializers
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract with the mToken it will manage
    /// @param _mToken The mToken address
    /// @param _weth The WETH contract address
    /// @param _owner The owner of this contract
    function initialize(
        address _mToken,
        address _weth,
        address _owner
    ) external initializer {
        require(
            _mToken != address(0),
            "MWethDelegatorOwner: mToken cannot be 0"
        );
        require(_weth != address(0), "MWethDelegatorOwner: weth cannot be 0");
        require(_owner != address(0), "MWethDelegatorOwner: owner cannot be 0");

        __Ownable_init();
        _transferOwnership(_owner);

        mToken = MToken(_mToken);
        weth = WETH9(_weth);
    }

    /// @notice Fallback function to receive ETH and wrap it to WETH
    receive() external payable {
        if (msg.value > 0) {
            weth.deposit{value: msg.value}();
            emit EthWrapped(msg.value);
        }
    }

    /// @notice Make an arbitrary call to any address with specified calldata and value
    /// @param target The address to call
    /// @param data The calldata to send
    /// @param value The ETH value to send
    /// @return success Whether the call succeeded
    /// @return result The result of the call
    function makeArbitraryCall(
        address target,
        bytes calldata data,
        uint256 value
    ) external payable onlyOwner returns (bool success, bytes memory result) {
        require(
            target != address(0),
            "MWethDelegatorOwner: target cannot be 0"
        );

        (success, result) = target.call{value: value}(data);
        require(success, "MWethDelegatorOwner: call failed");

        emit ArbitraryCallMade(target, value, data);
    }

    /// @notice withdraws ERC20 tokens from the contract. Used to withdraw WETH
    /// from the contract
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

    /// @notice Set the pending admin of the mToken
    /// @param newPendingAdmin The new pending admin address
    function setPendingAdmin(
        address payable newPendingAdmin
    ) external onlyOwner {
        require(
            mToken._setPendingAdmin(newPendingAdmin) == 0,
            "MWethDelegatorOwner: setPendingAdmin failed"
        );
        emit AdminFunctionCalled(
            "setPendingAdmin",
            abi.encode(newPendingAdmin)
        );
    }

    /// @notice Set the reserve factor of the mToken
    /// @param newReserveFactorMantissa The new reserve factor, scaled by 1e18
    function setReserveFactor(
        uint256 newReserveFactorMantissa
    ) external onlyOwner {
        require(
            mToken._setReserveFactor(newReserveFactorMantissa) == 0,
            "MWethDelegatorOwner: setReserveFactor failed"
        );
        emit AdminFunctionCalled(
            "setReserveFactor",
            abi.encode(newReserveFactorMantissa)
        );
    }

    /// @notice Reduce the reserves of the mToken
    /// @param reduceAmount The amount to reduce reserves by
    function reduceReserves(uint256 reduceAmount) external onlyOwner {
        require(
            mToken._reduceReserves(reduceAmount) == 0,
            "MWethDelegatorOwner: reduceReserves failed"
        );
        emit AdminFunctionCalled("reduceReserves", abi.encode(reduceAmount));
    }

    /// @notice Set the interest rate model of the mToken
    /// @param newInterestRateModel The new interest rate model contract
    function setInterestRateModel(
        InterestRateModel newInterestRateModel
    ) external onlyOwner {
        require(
            mToken._setInterestRateModel(newInterestRateModel) == 0,
            "MWethDelegatorOwner: setInterestRateModel failed"
        );
        emit AdminFunctionCalled(
            "setInterestRateModel",
            abi.encode(newInterestRateModel)
        );
    }

    /// @notice Set the protocol seize share of the mToken
    /// @param newProtocolSeizeShareMantissa The new protocol seize share, scaled by 1e18
    function setProtocolSeizeShare(
        uint256 newProtocolSeizeShareMantissa
    ) external onlyOwner {
        require(
            mToken._setProtocolSeizeShare(newProtocolSeizeShareMantissa) == 0,
            "MWethDelegatorOwner: setProtocolSeizeShare failed"
        );
        emit AdminFunctionCalled(
            "setProtocolSeizeShare",
            abi.encode(newProtocolSeizeShareMantissa)
        );
    }
}
