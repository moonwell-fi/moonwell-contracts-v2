// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

library DistributionTypes {
    struct UserStakeInput {
        address underlyingAsset;
        uint256 stakedByUser;
        uint256 totalStaked;
    }
}
