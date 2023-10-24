// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

interface ComptrollerInterfaceV1 {
    struct RewardMarketState {
        /// @notice The market's last updated rewardBorrowIndex or rewardSupplyIndex
        uint224 index;
        /// @notice The block timestamp the index was last updated at
        uint32 timestamp;
    }

    function supplyRewardSpeeds(
        uint8 reward,
        address market
    ) external view returns (uint);

    function borrowRewardSpeeds(
        uint8 reward,
        address market
    ) external view returns (uint);

    function rewardSupplyState(
        uint8 reward,
        address market
    ) external view returns (RewardMarketState memory);

    function rewardBorrowState(
        uint8 reward,
        address market
    ) external view returns (RewardMarketState memory);

    function rewardSupplierIndex(
        uint8 reward,
        address market,
        address user
    ) external view returns (uint);

    function rewardBorrowerIndex(
        uint8 reward,
        address market,
        address user
    ) external view returns (uint);

    function rewardAccrued(
        uint8 reward,
        address user
    ) external view returns (uint);

    function wellAddress() external view returns (address);

    struct Market {
        /// @notice Whether or not this market is listed
        bool isListed;
        /**
         * @notice Multiplier representing the most one can borrow against their collateral in this market.
         *  For instance, 0.9 to allow borrowing 90% of collateral value.
         *  Must be between 0 and 1, and stored as a mantissa.
         */
        uint collateralFactorMantissa;
    }

    function markets(address market) external view returns (Market memory);
}
