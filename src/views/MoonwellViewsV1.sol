// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {BaseMoonwellViews} from "@protocol/views/BaseMoonwellViews.sol";
import {ComptrollerInterfaceV1} from "@protocol/views/ComptrollerInterfaceV1.sol";
import {MToken} from "@protocol/MToken.sol";

/**
 * @title Moonwell's Views Contract for V1 deployment (pre Basechain deployment)
 * @author Moonwell
 */
contract MoonwellViewsV1 is BaseMoonwellViews {
    
    function getMarketIncentives(
        MToken market
    ) public view override returns (MarketIncentives[] memory) {
        ComptrollerInterfaceV1 comptrollerV1 = ComptrollerInterfaceV1(
            address(comptroller)
        );

        address govToken = comptrollerV1.wellAddress();
        address[2] memory _incentives;
        _incentives[0] = govToken;
        _incentives[1] = address(0);

        MarketIncentives[] memory _result = new MarketIncentives[](
            _incentives.length
        );

        for (uint8 index = 0; index < _incentives.length; index++) {
            _result[index] = MarketIncentives(
                _incentives[index],
                comptrollerV1.supplyRewardSpeeds(index, address(market)),
                comptrollerV1.borrowRewardSpeeds(index, address(market))
            );
        }

        return _result;
    }
}
