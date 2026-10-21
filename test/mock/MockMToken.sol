// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ComptrollerInterface} from "@protocol/ComptrollerInterface.sol";
import {InterestRateModel} from "@protocol/irm/InterestRateModel.sol";

/// @notice Mock MToken for testing MWethOwnerWrapper
contract MockMToken {
    address payable public admin;
    address payable public pendingAdmin;
    ComptrollerInterface public comptroller;
    InterestRateModel public interestRateModel;
    uint256 public reserveFactorMantissa;
    uint256 public protocolSeizeShareMantissa;
    uint256 public totalReserves;

    // Track function calls for testing
    uint256 public reduceReservesCallCount;
    uint256 public lastReduceReservesAmount;
    uint256 public addReservesCallCount;
    uint256 public lastAddReservesAmount;
    address public implementation;
    bool public lastAllowResign;
    bytes public lastBecomeImplementationData;
    uint256 public sweepExcessCashCallCount;
    uint256 public syncCashDownCallCount;

    event ReservesReduced(uint256 amount);
    event ReservesAdded(uint256 amount);

    constructor() {
        admin = payable(msg.sender);
        totalReserves = 1000 ether;
    }

    function _setPendingAdmin(
        address payable newPendingAdmin
    ) external returns (uint) {
        require(msg.sender == admin, "only admin");
        pendingAdmin = newPendingAdmin;
        return 0; // success
    }

    function _acceptAdmin() external returns (uint) {
        require(msg.sender == pendingAdmin, "only pending admin");
        admin = pendingAdmin;
        pendingAdmin = payable(address(0));
        return 0; // success
    }

    function _setComptroller(
        ComptrollerInterface newComptroller
    ) external returns (uint) {
        require(msg.sender == admin, "only admin");
        comptroller = newComptroller;
        return 0; // success
    }

    function _setReserveFactor(
        uint256 newReserveFactorMantissa
    ) external returns (uint) {
        require(msg.sender == admin, "only admin");
        reserveFactorMantissa = newReserveFactorMantissa;
        return 0; // success
    }

    function _reduceReserves(uint256 reduceAmount) external returns (uint) {
        require(msg.sender == admin, "only admin");
        require(reduceAmount <= totalReserves, "not enough reserves");

        reduceReservesCallCount++;
        lastReduceReservesAmount = reduceAmount;
        totalReserves -= reduceAmount;

        // Send ETH to the admin (simulating the unwrapping process)
        (bool success, ) = admin.call{value: reduceAmount}("");
        require(success, "ETH transfer failed");

        emit ReservesReduced(reduceAmount);
        return 0; // success
    }

    function _setInterestRateModel(
        InterestRateModel newInterestRateModel
    ) external returns (uint) {
        require(msg.sender == admin, "only admin");
        interestRateModel = newInterestRateModel;
        return 0; // success
    }

    function _setProtocolSeizeShare(
        uint256 newProtocolSeizeShareMantissa
    ) external returns (uint) {
        require(msg.sender == admin, "only admin");
        protocolSeizeShareMantissa = newProtocolSeizeShareMantissa;
        return 0; // success
    }

    function _addReserves(uint256 addAmount) external returns (uint) {
        require(msg.sender == admin, "only admin");

        addReservesCallCount++;
        lastAddReservesAmount = addAmount;
        totalReserves += addAmount;

        emit ReservesAdded(addAmount);
        return 0; // success
    }

    function _setImplementation(
        address implementation_,
        bool allowResign,
        bytes memory becomeImplementationData
    ) external {
        require(msg.sender == admin, "only admin");

        implementation = implementation_;
        lastAllowResign = allowResign;
        lastBecomeImplementationData = becomeImplementationData;
    }

    function _sweepExcessCash() external {
        require(msg.sender == admin, "only admin");

        sweepExcessCashCallCount++;
    }

    function _syncCashDown() external {
        require(msg.sender == admin, "only admin");

        syncCashDownCallCount++;
    }

    // Helper function to fund the mock with ETH for testing
    receive() external payable {}
}
