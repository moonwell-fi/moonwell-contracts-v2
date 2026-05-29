// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {BaseMoonwellViewsMoonbeam} from "@protocol/views/BaseMoonwellViewsMoonbeam.sol";
import {ComptrollerInterfaceV1} from "@protocol/views/ComptrollerInterfaceV1.sol";
import {MToken} from "@protocol/MToken.sol";
import {ExponentialNoError} from "@protocol/ExponentialNoError.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";

/**
 * @title Moonwell Views Contract — Moonbeam V1 (legacy storage layout)
 * @author Moonwell
 * @notice Same surface as `MoonwellViewsV1`, but inherits from
 *         `BaseMoonwellViewsMoonbeam` so the storage layout matches the
 *         original Moonbeam proxy initialization order. Use this contract
 *         as the implementation for the Moonbeam views proxy. Do NOT use
 *         on Base / Optimism — those proxies follow `BaseMoonwellViews`'s
 *         post-Mar-2024 layout.
 */
contract MoonwellViewsV1Moonbeam is
    BaseMoonwellViewsMoonbeam,
    ExponentialNoError
{
    uint224 constant _INITIAL_INDEX = 1e36;

    /// @notice xWELL token, the canonical "tokens" voting source after
    ///         mip-x58 deployed VotingPowerAggregator on every chain.
    /// @dev    Wired via `initializeV2` since the original `initialize`
    ///         on this proxy ran Sep 2023 — before xWELL existed. Lives
    ///         at storage slot 7 (Initializable at slot 0, plus the six
    ///         legacy `BaseMoonwellViewsMoonbeam` state vars).
    xWELL public xWellToken;

    /// @notice Wire xWELL after upgrading the legacy Moonbeam views
    ///         proxy. Called atomically with the upgrade via
    ///         `ProxyAdmin.upgradeAndCall` so there is no window in
    ///         which an attacker could preempt and point xWellToken at
    ///         a malicious contract.
    /// @param _xWell the xWELL_PROXY address (0xA88594D4… on every
    ///        chain via CREATE2).
    function initializeV2(address _xWell) external reinitializer(2) {
        require(_xWell != address(0), "xWell cant be the 0 address!");
        xWellToken = xWELL(_xWell);
    }

    /// @notice Override: post-mip-x58 only xWELL + stkWELL count toward
    ///         voting power. Native Moonbeam WELL is no longer
    ///         registered as a snapshot source on the
    ///         VotingPowerAggregator, so read xWELL instead of the
    ///         legacy `governanceToken` (WELL) slot.
    function getUserTokensVotingPower(
        address _user
    ) public view override returns (Votes memory _result) {
        if (address(xWellToken) != address(0)) {
            _result = Votes(
                xWellToken.getVotes(_user),
                xWellToken.balanceOf(_user),
                xWellToken.delegates(_user)
            );
        }
    }

    /// @notice Override: post-mip-x58 the TokenSaleDistributor is not a
    ///         snapshot source on the VotingPowerAggregator. Zero out
    ///         the delegated-voting-power component and keep the
    ///         unclaimed balance for display continuity.
    function getUserClaimsVotingPower(
        address _user
    ) public view override returns (Votes memory _result) {
        _result = super.getUserClaimsVotingPower(_user);
        _result.delegatedVotingPower = 0;
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

    function _getRewardSupplyIndex(
        ComptrollerInterfaceV1 comptroller,
        uint8 rewardType,
        address mToken
    )
        internal
        view
        returns (ComptrollerInterfaceV1.RewardMarketState memory _result)
    {
        require(rewardType <= 1, "rewardType is invalid");
        ComptrollerInterfaceV1.RewardMarketState
            memory supplyState = comptroller.rewardSupplyState(
                rewardType,
                mToken
            );
        uint supplySpeed = comptroller.supplyRewardSpeeds(rewardType, mToken);
        uint blockTimestamp = block.timestamp;
        uint deltaTimestamps = sub_(
            blockTimestamp,
            uint(supplyState.timestamp)
        );
        if (deltaTimestamps > 0 && supplySpeed > 0) {
            uint supplyTokens = MToken(mToken).totalSupply();
            uint wellAccrued = mul_(deltaTimestamps, supplySpeed);
            Double memory ratio = supplyTokens > 0
                ? fraction(wellAccrued, supplyTokens)
                : Double({mantissa: 0});
            Double memory index = add_(
                Double({mantissa: supplyState.index}),
                ratio
            );
            _result = ComptrollerInterfaceV1.RewardMarketState({
                index: safe224(index.mantissa, "new index exceeds 224 bits"),
                timestamp: safe32(
                    blockTimestamp,
                    "block timestamp exceeds 32 bits"
                )
            });
        } else if (deltaTimestamps > 0) {
            _result = ComptrollerInterfaceV1.RewardMarketState({
                index: safe224(supplyState.index, "new index exceeds 224 bits"),
                timestamp: safe32(
                    blockTimestamp,
                    "block timestamp exceeds 32 bits"
                )
            });
        }
    }

    function _getRewardBorrowIndex(
        ComptrollerInterfaceV1 comptroller,
        uint8 rewardType,
        address mToken
    )
        internal
        view
        returns (ComptrollerInterfaceV1.RewardMarketState memory _result)
    {
        require(rewardType <= 1, "rewardType is invalid");

        Exp memory marketBorrowIndex = Exp({
            mantissa: MToken(mToken).borrowIndex()
        });

        ComptrollerInterfaceV1.RewardMarketState
            memory borrowState = comptroller.rewardBorrowState(
                rewardType,
                mToken
            );
        uint borrowSpeed = comptroller.borrowRewardSpeeds(rewardType, mToken);
        uint blockTimestamp = block.timestamp;
        uint deltaTimestamps = sub_(
            blockTimestamp,
            uint(borrowState.timestamp)
        );

        if (deltaTimestamps > 0 && borrowSpeed > 0) {
            uint borrowAmount = div_(
                MToken(mToken).totalBorrows(),
                marketBorrowIndex
            );
            uint wellAccrued = mul_(deltaTimestamps, borrowSpeed);
            Double memory ratio = borrowAmount > 0
                ? fraction(wellAccrued, borrowAmount)
                : Double({mantissa: 0});
            Double memory index = add_(
                Double({mantissa: borrowState.index}),
                ratio
            );
            _result = ComptrollerInterfaceV1.RewardMarketState({
                index: safe224(index.mantissa, "new index exceeds 224 bits"),
                timestamp: safe32(
                    blockTimestamp,
                    "block timestamp exceeds 32 bits"
                )
            });
        } else if (deltaTimestamps > 0) {
            _result = ComptrollerInterfaceV1.RewardMarketState({
                index: safe224(borrowState.index, "new index exceeds 224 bits"),
                timestamp: safe32(
                    blockTimestamp,
                    "block timestamp exceeds 32 bits"
                )
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

        ComptrollerInterfaceV1.RewardMarketState
            memory supplyState = _getRewardSupplyIndex(
                comptroller,
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
            supplierIndex.mantissa = _INITIAL_INDEX;
        }

        Double memory deltaIndex = sub_(supplyIndex, supplierIndex);
        uint supplierTokens = mToken.balanceOf(supplier);
        uint supplierDelta = mul_(supplierTokens, deltaIndex);
        return supplierDelta;
    }

    function _getBorrowerReward(
        ComptrollerInterfaceV1 comptroller,
        uint8 rewardType,
        MToken mToken,
        address borrower
    ) internal view returns (uint) {
        require(rewardType <= 1, "rewardType is invalid");

        Exp memory marketBorrowIndex = Exp({mantissa: mToken.borrowIndex()});

        ComptrollerInterfaceV1.RewardMarketState
            memory borrowState = _getRewardBorrowIndex(
                comptroller,
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
            return borrowerDelta;
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
