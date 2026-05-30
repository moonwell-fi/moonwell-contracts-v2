// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IDistributionManager {
    function configureAssets(
        uint128[] calldata emissionPerSecond,
        uint256[] calldata totalStaked,
        address[] calldata underlyingAsset
    ) external;
}
