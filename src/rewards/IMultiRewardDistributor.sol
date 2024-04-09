// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "../MToken.sol";
import "../ExponentialNoError.sol";
import "./MultiRewardDistributor.sol";

interface IMultiRewardDistributor is MultiRewardDistributorCommon {
    // Public views
    function getAllMarketConfigs(
        MToken _mToken
    ) external view returns (MarketConfig[] memory);
    function getConfigForMarket(
        MToken _mToken,
        address _emissionToken
    ) external view returns (MarketConfig memory);
    function getOutstandingRewardsForUser(
        address _user
    ) external view returns (RewardWithMToken[] memory);
    function getOutstandingRewardsForUser(
        MToken _mToken,
        address _user
    ) external view returns (RewardInfo[] memory);
    function getCurrentEmissionCap() external view returns (uint);

    // Administrative functions
    function _addEmissionConfig(
        MToken _mToken,
        address _owner,
        address _emissionToken,
        uint _supplyEmissionPerSec,
        uint _borrowEmissionsPerSec,
        uint _endTime
    ) external;
    function _rescueFunds(address _tokenAddress, uint _amount) external;
    function _setPauseGuardian(address _newPauseGuardian) external;
    function _setEmissionCap(uint _newEmissionCap) external;

    // Comptroller API
    function updateMarketSupplyIndex(MToken _mToken) external;
    function disburseSupplierRewards(
        MToken _mToken,
        address _supplier,
        bool _sendTokens
    ) external;
    function updateMarketSupplyIndexAndDisburseSupplierRewards(
        MToken _mToken,
        address _supplier,
        bool _sendTokens
    ) external;
    function updateMarketBorrowIndex(MToken _mToken) external;
    function disburseBorrowerRewards(
        MToken _mToken,
        address _borrower,
        bool _sendTokens
    ) external;
    function updateMarketBorrowIndexAndDisburseBorrowerRewards(
        MToken _mToken,
        address _borrower,
        bool _sendTokens
    ) external;

    // Pause guardian functions
    function _pauseRewards() external;
    function _unpauseRewards() external;

    // Emission schedule admin functions
    function _updateSupplySpeed(
        MToken _mToken,
        address _emissionToken,
        uint _newSupplySpeed
    ) external;
    function _updateBorrowSpeed(
        MToken _mToken,
        address _emissionToken,
        uint _newBorrowSpeed
    ) external;
    function _updateOwner(
        MToken _mToken,
        address _emissionToken,
        address _newOwner
    ) external;
    function _updateEndTime(
        MToken _mToken,
        address _emissionToken,
        uint _newEndTime
    ) external;
}
