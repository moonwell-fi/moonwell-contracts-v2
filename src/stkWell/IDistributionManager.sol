// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {IERC20} from "./IERC20.sol";
import {DistributionTypes} from "./DistributionTypes.sol";

interface IDistributionManager {
    function configureAsset(
        uint128 emissionPerSecond,
        IERC20 underlyingAsset
    ) external;
    function configureAssets(
        DistributionTypes.AssetConfigInput[] calldata assetsConfigInput
    ) external;
}
