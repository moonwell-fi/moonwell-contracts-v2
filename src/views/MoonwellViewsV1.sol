// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {BaseMoonwellViews} from "@protocol/views/BaseMoonwellViews.sol";
import {ComptrollerInterfaceV1} from "@protocol/views/ComptrollerInterfaceV1.sol";
import {MToken} from "@protocol/MToken.sol";
import {ExponentialNoError} from "@protocol/ExponentialNoError.sol";

/**
 * @title Moonwell's Views Contract for V1 deployment (pre Basechain deployment)
 * @author Moonwell
 */
contract MoonwellViewsV1 is BaseMoonwellViews, ExponentialNoError {
    function getSupplyCaps(address) public pure override returns (uint) {
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

    function getSupplierReward(
        ComptrollerInterfaceV1 comptroller,
        uint8 rewardType,
        MToken mToken,
        address supplier
    ) public view returns (uint256) {
        require(rewardType <= 1, "rewardType is invalid");

        ComptrollerInterfaceV1.RewardMarketState
            memory supplyState = comptroller.rewardSupplyState(
                rewardType,
                address(mToken)
            );
        Double memory supplyIndex = Double({mantissa: supplyState.index});
        Double memory supplierIndex = Double({
            mantissa: comptroller.rewardSupplierIndex(
                rewardType,
                address(mToken),
                supplier
            )
        });

        if (supplierIndex.mantissa == 0 && supplyIndex.mantissa > 0) {
            supplierIndex.mantissa = 1e36;
        }

        Double memory deltaIndex = sub_(supplyIndex, supplierIndex);
        uint supplierTokens = mToken.balanceOf(supplier);
        uint supplierDelta = mul_(supplierTokens, deltaIndex);
        uint supplierAccrued = add_(
            comptroller.rewardAccrued(rewardType, supplier),
            supplierDelta
        );

        return supplierAccrued;
    }

    function getBorrowerReward(
        ComptrollerInterfaceV1 comptroller,
        uint8 rewardType,
        MToken mToken,
        address borrower
    ) public view returns (uint) {
        require(rewardType <= 1, "rewardType is invalid");

        Exp memory marketBorrowIndex = Exp({mantissa: mToken.borrowIndex()});

        ComptrollerInterfaceV1.RewardMarketState
            memory borrowState = comptroller.rewardBorrowState(
                rewardType,
                address(mToken)
            );

        Double memory borrowIndex = Double({mantissa: borrowState.index});
        Double memory borrowerIndex = Double({
            mantissa: comptroller.rewardBorrowerIndex(
                rewardType,
                address(mToken),
                borrower
            )
        });

        if (borrowerIndex.mantissa > 0) {
            Double memory deltaIndex = sub_(borrowIndex, borrowerIndex);
            uint borrowerAmount = div_(
                mToken.borrowBalanceStored(borrower),
                marketBorrowIndex
            );
            uint borrowerDelta = mul_(borrowerAmount, deltaIndex);
            uint borrowerAccrued = add_(
                comptroller.rewardAccrued(rewardType, borrower),
                borrowerDelta
            );

            return borrowerAccrued;
        }
        return 0;
    }

    /// @notice Function to get the user accrued and pendings rewards
    function getUserRewards(
        address _user
    ) public view override returns (Rewards[] memory) {
        MToken[] memory _mTokens = comptroller.getAllMarkets();

        ComptrollerInterfaceV1 comptrollerV1 = ComptrollerInterfaceV1(
            address(comptroller)
        );

        Rewards[] memory _result = new Rewards[](_mTokens.length * 2);

        for (uint i = 0; i < _mTokens.length * 2; i += 2) {
            MToken mToken = _mTokens[i > 0 ? i - 1 : 0];

            _result[i].market = address(mToken);
            _result[i].rewardToken = address(comptrollerV1.wellAddress());

            _result[i + 1].market = address(mToken);
            _result[i + 1].rewardToken = address(0);

            if (comptrollerV1.markets(address(mToken)).isListed) {
                _result[i].supplyRewardsAmount = getSupplierReward(
                    comptrollerV1,
                    0,
                    mToken,
                    _user
                );
                _result[i].borrowRewardsAmount = getBorrowerReward(
                    comptrollerV1,
                    0,
                    mToken,
                    _user
                );

                _result[i + 1].supplyRewardsAmount = getSupplierReward(
                    comptrollerV1,
                    1,
                    mToken,
                    _user
                );
                _result[i + 1].borrowRewardsAmount = getBorrowerReward(
                    comptrollerV1,
                    1,
                    mToken,
                    _user
                );
            }
        }

        return _result;
    }
}
