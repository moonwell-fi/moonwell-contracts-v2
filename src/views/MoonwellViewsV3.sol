// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {BaseMoonwellViews} from "@protocol/views/BaseMoonwellViews.sol";
import {IMultiRewardDistributor} from "@protocol/rewards/IMultiRewardDistributor.sol";
import {MToken} from "@protocol/MToken.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {SafetyModuleInterfaceV1} from "@protocol/views/SafetyModuleInterfaceV1.sol";

/**
 * @title Moonwells Views Contract for V3 deployment (Post xWELL deployment)
 * @author Moonwell
 */
contract MoonwellViewsV3 is BaseMoonwellViews {
    function _getSupplyCaps(
        address _market
    ) internal view override returns (uint) {
        return comptroller.supplyCaps(_market);
    }

    function getMarketIncentives(
        MToken market
    ) public view override returns (MarketIncentives[] memory) {
        IMultiRewardDistributor distributor = IMultiRewardDistributor(
            address(comptroller.rewardDistributor())
        );

        IMultiRewardDistributor.MarketConfig[]
            memory _emissionConfigs = distributor.getAllMarketConfigs(market);

        uint _indexHelper = 0;
        for (uint index = 0; index < _emissionConfigs.length; index++) {
            IMultiRewardDistributor.MarketConfig
                memory _config = _emissionConfigs[index];
            if (_config.endTime > block.timestamp) {
                _indexHelper++;
            }
        }

        MarketIncentives[] memory _result = new MarketIncentives[](
            _indexHelper
        );

        _indexHelper = 0;
        for (uint index = 0; index < _emissionConfigs.length; index++) {
            IMultiRewardDistributor.MarketConfig
                memory _config = _emissionConfigs[index];
            if (_config.endTime > block.timestamp) {
                _result[_indexHelper] = MarketIncentives(
                    _config.emissionToken,
                    _config.supplyEmissionsPerSec,
                    _config.borrowEmissionsPerSec
                );
                _indexHelper++;
            }
        }

        return _result;
    }

    /// @notice Function to get the user accrued and pendings rewards
    function getUserRewards(
        address _user
    ) public view override returns (Rewards[] memory) {
        IMultiRewardDistributor distributor = IMultiRewardDistributor(
            address(comptroller.rewardDistributor())
        );

        IMultiRewardDistributor.RewardWithMToken[]
            memory outstandingRewards = distributor
                .getOutstandingRewardsForUser(_user);

        uint _indexHelper = 0;

        for (uint index = 0; index < outstandingRewards.length; index++) {
            IMultiRewardDistributor.RewardWithMToken
                memory _rewardInfo = outstandingRewards[index];
            for (
                uint rewardsIndex = 0;
                rewardsIndex < _rewardInfo.rewards.length;
                rewardsIndex++
            ) {
                IMultiRewardDistributor.RewardInfo memory _amounts = _rewardInfo
                    .rewards[rewardsIndex];
                if (_amounts.totalAmount > 0) {
                    _indexHelper++;
                }
            }
        }

        Rewards[] memory _result = new Rewards[](_indexHelper);

        _indexHelper = 0;
        for (uint index = 0; index < outstandingRewards.length; index++) {
            IMultiRewardDistributor.RewardWithMToken
                memory _rewardInfo = outstandingRewards[index];
            for (
                uint rewardsIndex = 0;
                rewardsIndex < _rewardInfo.rewards.length;
                rewardsIndex++
            ) {
                IMultiRewardDistributor.RewardInfo memory _amounts = _rewardInfo
                    .rewards[rewardsIndex];
                if (_amounts.totalAmount > 0) {
                    _result[_indexHelper] = Rewards(
                        _rewardInfo.mToken,
                        _amounts.emissionToken,
                        _amounts.supplySide,
                        _amounts.borrowSide
                    );
                    _indexHelper++;
                }
            }
        }

        return _result;
    }

    /// @notice A view to get the user voting power from the user holdings
    function getUserTokensVotingPower(
        address _user
    ) public view override returns (Votes memory _result) {
        if (address(governanceToken) != address(0)) {
            uint _priorVotes = xWELL(address(governanceToken)).getVotes(_user);
            address _delegates = governanceToken.delegates(_user);
            _result = Votes(
                _priorVotes,
                governanceToken.balanceOf(_user),
                _delegates
            );
        }
    }

    /// @notice A view to get the user voting power from the tokens staking in the safety module
    function getUserStakingVotingPower(
        address _user
    ) public view override returns (Votes memory _result) {
        if (address(safetyModule) != address(0)) {
            uint _priorVotes = SafetyModuleInterfaceV1(address(safetyModule))
                .getPriorVotes(_user, block.timestamp - 1);
            _result = Votes(
                _priorVotes,
                safetyModule.balanceOf(_user),
                address(0)
            );
        }
    }
}
