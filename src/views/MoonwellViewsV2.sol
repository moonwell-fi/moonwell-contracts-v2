// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {BaseMoonwellViews} from "@protocol/views/BaseMoonwellViews.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {IMultiRewardDistributor} from "@protocol/MultiRewardDistributor/IMultiRewardDistributor.sol";
import {MToken} from "@protocol/MToken.sol";

/**
 * @title Moonwell's Views Contract for V1 deployment (pre Basechain deployment)
 * @author Moonwell
 */
contract MoonwellViewsV2 is BaseMoonwellViews {
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
}
