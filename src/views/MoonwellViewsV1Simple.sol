// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {BaseMoonwellViews} from "@protocol/views/BaseMoonwellViews.sol";
import {ComptrollerInterfaceV1} from "@protocol/views/ComptrollerInterfaceV1.sol";
import {MToken} from "@protocol/MToken.sol";

/**
 * @title Moonwell Views Contract for V1 deployment — size-optimized
 * @author Moonwell
 * @notice Functionally equivalent to MoonwellViewsV1 but drops
 *         ExponentialNoError in favour of plain Solidity 0.8.x arithmetic,
 *         saving ~3-4 kB of deployed bytecode.
 */
contract MoonwellViewsV1Simple is BaseMoonwellViews {
    uint224 constant _INITIAL_INDEX = 1e36;

    /// @dev Override the base 6-param initialize as a no-op; Moonriver uses
    ///      its own initialize(InitParams) instead.
    function initialize(
        address,
        address,
        address,
        address,
        address,
        address
    ) external pure override {
        revert();
    }

    /// @dev No token sale distributor on V1 chains using this contract
    function getUserClaimsVotingPower(
        address
    ) public pure override returns (Votes memory) {}

    /// @dev Skip claimsVotes (always empty) to save bytecode
    function getUserVotingPower(
        address _user
    ) public view override returns (UserVotes memory _result) {
        _result.stakingVotes = getUserStakingVotingPower(_user);
        _result.tokenVotes = getUserTokensVotingPower(_user);
    }

    function _getSupplyCaps(address) internal pure override returns (uint) {
        return 0;
    }

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

    // ──────── safe narrowing casts (still needed: 0.8.x truncates silently) ────

    function _safe224(uint n) internal pure returns (uint224) {
        require(n < 2 ** 224);
        return uint224(n);
    }

    function _safe32(uint n) internal pure returns (uint32) {
        require(n < 2 ** 32);
        return uint32(n);
    }

    // ──────── reward-index helpers (plain math, no Exp/Double structs) ──────────

    function _getRewardSupplyIndex(
        ComptrollerInterfaceV1 _comptroller,
        uint8 rewardType,
        address mToken
    )
        internal
        view
        returns (ComptrollerInterfaceV1.RewardMarketState memory _result)
    {
        ComptrollerInterfaceV1.RewardMarketState
            memory supplyState = _comptroller.rewardSupplyState(
                rewardType,
                mToken
            );
        uint supplySpeed = _comptroller.supplyRewardSpeeds(rewardType, mToken);
        uint blockTimestamp = block.timestamp;
        uint deltaTimestamps = blockTimestamp - uint(supplyState.timestamp);

        if (deltaTimestamps > 0 && supplySpeed > 0) {
            uint supplyTokens = MToken(mToken).totalSupply();
            uint wellAccrued = deltaTimestamps * supplySpeed;
            uint ratio = supplyTokens > 0
                ? (wellAccrued * 1e36) / supplyTokens
                : 0;
            uint index = uint(supplyState.index) + ratio;
            _result = ComptrollerInterfaceV1.RewardMarketState({
                index: _safe224(index),
                timestamp: _safe32(blockTimestamp)
            });
        } else if (deltaTimestamps > 0) {
            _result = ComptrollerInterfaceV1.RewardMarketState({
                index: _safe224(supplyState.index),
                timestamp: _safe32(blockTimestamp)
            });
        }
    }

    function _getRewardBorrowIndex(
        ComptrollerInterfaceV1 _comptroller,
        uint8 rewardType,
        address mToken
    )
        internal
        view
        returns (ComptrollerInterfaceV1.RewardMarketState memory _result)
    {
        uint marketBorrowIndex = MToken(mToken).borrowIndex();

        ComptrollerInterfaceV1.RewardMarketState
            memory borrowState = _comptroller.rewardBorrowState(
                rewardType,
                mToken
            );
        uint borrowSpeed = _comptroller.borrowRewardSpeeds(rewardType, mToken);
        uint blockTimestamp = block.timestamp;
        uint deltaTimestamps = blockTimestamp - uint(borrowState.timestamp);

        if (deltaTimestamps > 0 && borrowSpeed > 0) {
            uint borrowAmount = (MToken(mToken).totalBorrows() * 1e18) /
                marketBorrowIndex;
            uint wellAccrued = deltaTimestamps * borrowSpeed;
            uint ratio = borrowAmount > 0
                ? (wellAccrued * 1e36) / borrowAmount
                : 0;
            uint index = uint(borrowState.index) + ratio;
            _result = ComptrollerInterfaceV1.RewardMarketState({
                index: _safe224(index),
                timestamp: _safe32(blockTimestamp)
            });
        } else if (deltaTimestamps > 0) {
            _result = ComptrollerInterfaceV1.RewardMarketState({
                index: _safe224(borrowState.index),
                timestamp: _safe32(blockTimestamp)
            });
        }
    }

    function _getSupplierReward(
        ComptrollerInterfaceV1 _comptroller,
        uint8 rewardType,
        MToken mToken,
        address supplier
    ) internal view returns (uint256) {
        ComptrollerInterfaceV1.RewardMarketState
            memory supplyState = _getRewardSupplyIndex(
                _comptroller,
                rewardType,
                address(mToken)
            );

        uint supplyIndex = supplyState.index;
        uint supplierIndex = _comptroller.rewardSupplierIndex(
            rewardType,
            address(mToken),
            supplier
        );

        if (supplierIndex == 0 && supplyIndex > 0) {
            supplierIndex = _INITIAL_INDEX;
        }

        uint deltaIndex = supplyIndex - supplierIndex;
        uint supplierTokens = mToken.balanceOf(supplier);
        return (supplierTokens * deltaIndex) / 1e36;
    }

    function _getBorrowerReward(
        ComptrollerInterfaceV1 _comptroller,
        uint8 rewardType,
        MToken mToken,
        address borrower
    ) internal view returns (uint) {
        uint marketBorrowIndex = mToken.borrowIndex();

        ComptrollerInterfaceV1.RewardMarketState
            memory borrowState = _getRewardBorrowIndex(
                _comptroller,
                rewardType,
                address(mToken)
            );

        uint borrowIndex = borrowState.index;
        uint borrowerIndex = _comptroller.rewardBorrowerIndex(
            rewardType,
            address(mToken),
            borrower
        );

        if (borrowerIndex > 0) {
            uint deltaIndex = borrowIndex - borrowerIndex;
            uint borrowerAmount = (mToken.borrowBalanceStored(borrower) *
                1e18) / marketBorrowIndex;
            return (borrowerAmount * deltaIndex) / 1e36;
        }
        return 0;
    }

    /// @notice Function to get the user accrued and pending rewards
    function getUserRewards(
        address _user
    ) public view override returns (Rewards[] memory) {
        MToken[] memory _mTokens = comptroller.getAllMarkets();

        ComptrollerInterfaceV1 comptrollerV1 = ComptrollerInterfaceV1(
            address(comptroller)
        );

        Rewards[] memory _result = new Rewards[](_mTokens.length * 2);
        uint _currIndex;
        bool _distributedAccrued = false;

        for (uint i = 0; i < _mTokens.length; i++) {
            MToken mToken = _mTokens[i];

            _result[_currIndex].market = address(mToken);
            _result[_currIndex].rewardToken = address(
                comptrollerV1.wellAddress()
            );

            _result[_currIndex + 1].market = address(mToken);
            _result[_currIndex + 1].rewardToken = address(0);

            if (comptrollerV1.markets(address(mToken)).isListed) {
                _result[_currIndex].supplyRewardsAmount = _getSupplierReward(
                    comptrollerV1,
                    0,
                    mToken,
                    _user
                );
                _result[_currIndex].borrowRewardsAmount = _getBorrowerReward(
                    comptrollerV1,
                    0,
                    mToken,
                    _user
                );

                _result[_currIndex + 1]
                    .supplyRewardsAmount = _getSupplierReward(
                    comptrollerV1,
                    1,
                    mToken,
                    _user
                );
                _result[_currIndex + 1]
                    .borrowRewardsAmount = _getBorrowerReward(
                    comptrollerV1,
                    1,
                    mToken,
                    _user
                );

                if (_distributedAccrued == false) {
                    _result[_currIndex].supplyRewardsAmount += comptrollerV1
                        .rewardAccrued(0, _user);
                    _result[_currIndex + 1].supplyRewardsAmount += comptrollerV1
                        .rewardAccrued(1, _user);
                    _distributedAccrued = true;
                }
            }

            _currIndex += 2;
        }

        return _result;
    }
}
