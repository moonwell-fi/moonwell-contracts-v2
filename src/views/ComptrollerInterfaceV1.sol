// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

abstract contract ComptrollerInterfaceV1 {

    struct RewardMarketState {
        /// @notice The market's last updated rewardBorrowIndex or rewardSupplyIndex
        uint224 index;

        /// @notice The block timestamp the index was last updated at
        uint32 timestamp;
    }

    /// @notice The portion of supply reward rate that each market currently receives
    mapping(uint8 => mapping(address => uint)) public supplyRewardSpeeds;

    /// @notice The portion of borrow reward rate that each market currently receives
    mapping(uint8 => mapping(address => uint)) public borrowRewardSpeeds;

    /// @notice The WELL/GLMR market supply state for each market
    mapping(uint8 => mapping(address => RewardMarketState)) public rewardSupplyState;

    /// @notice The WELL/GLMR market borrow state for each market
    mapping(uint8 =>mapping(address => RewardMarketState)) public rewardBorrowState;

    /// @notice The WELL/GLMR borrow index for each market for each supplier as of the last time they accrued reward
    mapping(uint8 => mapping(address => mapping(address => uint))) public rewardSupplierIndex;

    /// @notice The WELL/GLMR borrow index for each market for each borrower as of the last time they accrued reward
    mapping(uint8 => mapping(address => mapping(address => uint))) public rewardBorrowerIndex;

    /// @notice The WELL/GLMR accrued but not yet transferred to each user
    mapping(uint8 => mapping(address => uint)) public rewardAccrued;

    /// @notice WELL token contract address
    address public wellAddress;


}