// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {IERC20} from "./IERC20.sol";
import {DistributionTypes} from "../libraries/DistributionTypes.sol";

interface IDistributionManager {
    function configureAsset(
        uint128 emissionPerSecond,
        IERC20 underlyingAsset
    ) external;

    function configureAssets(
        uint128[] memory emissionPerSecond,
        uint256[] memory totalStaked,
        address[] memory underlyingAsset
    ) external;
}
