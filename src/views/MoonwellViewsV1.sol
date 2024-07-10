// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {ExponentialNoError} from "@protocol/ExponentialNoError.sol";
import {MToken} from "@protocol/MToken.sol";
import {BaseMoonwellViews} from "@protocol/views/BaseMoonwellViews.sol";
import {ComptrollerInterfaceV1} from "@protocol/views/ComptrollerInterfaceV1.sol";

/**
 * @title Moonwell Views Contract for V1 deployment (pre Basechain deployment)
 * @author Moonwell
 */
contract MoonwellViewsV1 is BaseMoonwellViews, ExponentialNoError {
    uint224 constant _INITIAL_INDEX = 1e36;

    function _getSupplyCaps(address) internal pure override returns (uint256) {
        return 0;
    }

    function getMarketIncentives(MToken market) public view override returns (MarketIncentives[] memory) {
        ComptrollerInterfaceV1 comptrollerV1 = ComptrollerInterfaceV1(address(comptroller));

        address govToken = comptrollerV1.wellAddress();
        address[2] memory _incentives;
        _incentives[0] = govToken;
        _incentives[1] = address(0);

        MarketIncentives[] memory _result = new MarketIncentives[](_incentives.length);

        for (uint8 index = 0; index < _incentives.length; index++) {
            _result[index] = MarketIncentives(
                _incentives[index],
                comptrollerV1.supplyRewardSpeeds(index, address(market)),
                comptrollerV1.borrowRewardSpeeds(index, address(market))
            );
        }

        return _result;
    }

    function _getRewardSupplyIndex(
        ComptrollerInterfaceV1 comptroller,
        uint8 rewardType,
        address mToken
    ) internal view returns (ComptrollerInterfaceV1.RewardMarketState memory _result) {
        require(rewardType <= 1, "rewardType is invalid");
        ComptrollerInterfaceV1.RewardMarketState memory supplyState = comptroller.rewardSupplyState(rewardType, mToken);
        uint256 supplySpeed = comptroller.supplyRewardSpeeds(rewardType, mToken);
        uint256 blockTimestamp = block.timestamp;
        uint256 deltaTimestamps = sub_(blockTimestamp, uint256(supplyState.timestamp));
        if (deltaTimestamps > 0 && supplySpeed > 0) {
            uint256 supplyTokens = MToken(mToken).totalSupply();
            uint256 wellAccrued = mul_(deltaTimestamps, supplySpeed);
            Double memory ratio = supplyTokens > 0 ? fraction(wellAccrued, supplyTokens) : Double({mantissa: 0});
            Double memory index = add_(Double({mantissa: supplyState.index}), ratio);
            _result = ComptrollerInterfaceV1.RewardMarketState({
                index: safe224(index.mantissa, "new index exceeds 224 bits"),
                timestamp: safe32(blockTimestamp, "block timestamp exceeds 32 bits")
            });
        } else if (deltaTimestamps > 0) {
            _result = ComptrollerInterfaceV1.RewardMarketState({
                index: safe224(supplyState.index, "new index exceeds 224 bits"),
                timestamp: safe32(blockTimestamp, "block timestamp exceeds 32 bits")
            });
        }
    }

    function _getRewardBorrowIndex(
        ComptrollerInterfaceV1 comptroller,
        uint8 rewardType,
        address mToken
    ) internal view returns (ComptrollerInterfaceV1.RewardMarketState memory _result) {
        require(rewardType <= 1, "rewardType is invalid");

        Exp memory marketBorrowIndex = Exp({mantissa: MToken(mToken).borrowIndex()});

        ComptrollerInterfaceV1.RewardMarketState memory borrowState = comptroller.rewardBorrowState(rewardType, mToken);
        uint256 borrowSpeed = comptroller.borrowRewardSpeeds(rewardType, mToken);
        uint256 blockTimestamp = block.timestamp;
        uint256 deltaTimestamps = sub_(blockTimestamp, uint256(borrowState.timestamp));

        if (deltaTimestamps > 0 && borrowSpeed > 0) {
            uint256 borrowAmount = div_(MToken(mToken).totalBorrows(), marketBorrowIndex);
            uint256 wellAccrued = mul_(deltaTimestamps, borrowSpeed);
            Double memory ratio = borrowAmount > 0 ? fraction(wellAccrued, borrowAmount) : Double({mantissa: 0});
            Double memory index = add_(Double({mantissa: borrowState.index}), ratio);
            _result = ComptrollerInterfaceV1.RewardMarketState({
                index: safe224(index.mantissa, "new index exceeds 224 bits"),
                timestamp: safe32(blockTimestamp, "block timestamp exceeds 32 bits")
            });
        } else if (deltaTimestamps > 0) {
            _result = ComptrollerInterfaceV1.RewardMarketState({
                index: safe224(borrowState.index, "new index exceeds 224 bits"),
                timestamp: safe32(blockTimestamp, "block timestamp exceeds 32 bits")
            });
        }
    }

    function _getSupplierReward(
        ComptrollerInterfaceV1 comptroller,
        uint8 rewardType,
        MToken mToken,
        address supplier
    ) internal view returns (uint256) {
        require(rewardType <= 1, "rewardType is invalid");

        ComptrollerInterfaceV1.RewardMarketState memory supplyState =
            _getRewardSupplyIndex(comptroller, rewardType, address(mToken));

        Double memory supplyIndex = Double({mantissa: supplyState.index});
        Double memory supplierIndex =
            Double({mantissa: comptroller.rewardSupplierIndex(rewardType, address(mToken), supplier)});

        if (supplierIndex.mantissa == 0 && supplyIndex.mantissa > 0) {
            supplierIndex.mantissa = _INITIAL_INDEX;
        }

        Double memory deltaIndex = sub_(supplyIndex, supplierIndex);
        uint256 supplierTokens = mToken.balanceOf(supplier);
        uint256 supplierDelta = mul_(supplierTokens, deltaIndex);
        return supplierDelta;
    }

    function _getBorrowerReward(
        ComptrollerInterfaceV1 comptroller,
        uint8 rewardType,
        MToken mToken,
        address borrower
    ) internal view returns (uint256) {
        require(rewardType <= 1, "rewardType is invalid");

        Exp memory marketBorrowIndex = Exp({mantissa: mToken.borrowIndex()});

        ComptrollerInterfaceV1.RewardMarketState memory borrowState =
            _getRewardBorrowIndex(comptroller, rewardType, address(mToken));

        Double memory borrowIndex = Double({mantissa: borrowState.index});
        Double memory borrowerIndex =
            Double({mantissa: comptroller.rewardBorrowerIndex(rewardType, address(mToken), borrower)});

        if (borrowerIndex.mantissa > 0) {
            Double memory deltaIndex = sub_(borrowIndex, borrowerIndex);
            uint256 borrowerAmount = div_(mToken.borrowBalanceStored(borrower), marketBorrowIndex);
            uint256 borrowerDelta = mul_(borrowerAmount, deltaIndex);
            return borrowerDelta;
        }
        return 0;
    }

    /// @notice Function to get the user accrued and pendings rewards
    function getUserRewards(address _user) public view override returns (Rewards[] memory) {
        MToken[] memory _mTokens = comptroller.getAllMarkets();

        ComptrollerInterfaceV1 comptrollerV1 = ComptrollerInterfaceV1(address(comptroller));

        Rewards[] memory _result = new Rewards[](_mTokens.length * 2);
        uint256 _currIndex;
        bool _distributedAccrued = false;

        for (uint256 i = 0; i < _mTokens.length; i++) {
            MToken mToken = _mTokens[i];

            _result[_currIndex].market = address(mToken);
            _result[_currIndex].rewardToken = address(comptrollerV1.wellAddress());

            _result[_currIndex + 1].market = address(mToken);
            _result[_currIndex + 1].rewardToken = address(0);

            if (comptrollerV1.markets(address(mToken)).isListed) {
                _result[_currIndex].supplyRewardsAmount = _getSupplierReward(comptrollerV1, 0, mToken, _user);
                _result[_currIndex].borrowRewardsAmount = _getBorrowerReward(comptrollerV1, 0, mToken, _user);

                _result[_currIndex + 1].supplyRewardsAmount = _getSupplierReward(comptrollerV1, 1, mToken, _user);
                _result[_currIndex + 1].borrowRewardsAmount = _getBorrowerReward(comptrollerV1, 1, mToken, _user);

                if (_distributedAccrued == false) {
                    _result[_currIndex].supplyRewardsAmount += comptrollerV1.rewardAccrued(0, _user);
                    _result[_currIndex + 1].supplyRewardsAmount += comptrollerV1.rewardAccrued(1, _user);
                    _distributedAccrued = true;
                }
            }

            _currIndex += 2;
        }

        return _result;
    }
}
