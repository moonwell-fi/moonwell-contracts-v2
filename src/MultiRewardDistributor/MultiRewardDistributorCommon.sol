// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "../MToken.sol";

// The commonly structures and events for the MultiRewardDistributor
interface MultiRewardDistributorCommon {
    struct MarketConfig {
        // The owner/admin of the emission config
        address owner;
        // The emission token
        address emissionToken;
        // Scheduled to end at this time
        uint endTime;
        // Supplier global state
        uint224 supplyGlobalIndex;
        uint32 supplyGlobalTimestamp;
        // Borrower global state
        uint224 borrowGlobalIndex;
        uint32 borrowGlobalTimestamp;
        uint supplyEmissionsPerSec;
        uint borrowEmissionsPerSec;
    }

    struct MarketEmissionConfig {
        MarketConfig config;
        mapping(address => uint) supplierIndices;
        mapping(address => uint) supplierRewardsAccrued;
        mapping(address => uint) borrowerIndices;
        mapping(address => uint) borrowerRewardsAccrued;
    }

    struct RewardInfo {
        address emissionToken;
        uint totalAmount;
        uint supplySide;
        uint borrowSide;
    }

    struct IndexUpdate {
        uint224 newIndex;
        uint32 newTimestamp;
    }

    struct MTokenData {
        uint mTokenBalance;
        uint borrowBalanceStored;
    }

    struct RewardWithMToken {
        address mToken;
        RewardInfo[] rewards;
    }

    // Global index updates
    event GlobalSupplyIndexUpdated(
        MToken mToken,
        address emissionToken,
        uint newSupplyIndex,
        uint32 newSupplyGlobalTimestamp
    );
    event GlobalBorrowIndexUpdated(
        MToken mToken,
        address emissionToken,
        uint newIndex,
        uint32 newTimestamp
    );

    // Reward Disbursal
    event DisbursedSupplierRewards(
        MToken indexed mToken,
        address indexed supplier,
        address indexed emissionToken,
        uint totalAccrued
    );
    event DisbursedBorrowerRewards(
        MToken indexed mToken,
        address indexed borrower,
        address indexed emissionToken,
        uint totalAccrued
    );

    // Admin update events
    event NewConfigCreated(
        MToken indexed mToken,
        address indexed owner,
        address indexed emissionToken,
        uint supplySpeed,
        uint borrowSpeed,
        uint endTime
    );
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);
    event NewEmissionCap(uint oldEmissionCap, uint newEmissionCap);
    event NewEmissionConfigOwner(
        MToken indexed mToken,
        address indexed emissionToken,
        address currentOwner,
        address newOwner
    );
    event NewRewardEndTime(
        MToken indexed mToken,
        address indexed emissionToken,
        uint currentEndTime,
        uint newEndTime
    );
    event NewSupplyRewardSpeed(
        MToken indexed mToken,
        address indexed emissionToken,
        uint oldRewardSpeed,
        uint newRewardSpeed
    );
    event NewBorrowRewardSpeed(
        MToken indexed mToken,
        address indexed emissionToken,
        uint oldRewardSpeed,
        uint newRewardSpeed
    );
    event FundsRescued(address token, uint amount);

    // Pause guardian stuff
    event RewardsPaused();
    event RewardsUnpaused();

    // Errors
    event InsufficientTokensToEmit(
        address payable user,
        address rewardToken,
        uint amount
    );
}
