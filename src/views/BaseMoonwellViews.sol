// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MToken} from "@protocol/MToken.sol";
import {PriceOracle} from "@protocol//Oracles/PriceOracle.sol";

/**
 * @title Moonwell's Views Contract
 * @author Moonwell
 */
contract BaseMoonwellViews is Initializable {
    struct MarketIncentives {
        address token;
        uint supplyIncentivesPerSec;
        uint borrowIncentivesPerSec;
    }

    struct Market {
        bool isListed;
        uint borrowCap;
        uint supplyCap;
        bool mintPaused;
        bool borrowPaused;
        uint collateralFactor;
        uint underlyingPrice;
        uint totalSupply;
        uint totalBorrows;
        uint totalReserves;
        uint cash;
        uint exchangeRate;
        uint borrowIndex;
        uint reserveFactor;
        uint borrowRate;
        uint supplyRate;
        MarketIncentives[] incentives;
    }

    /// @notice Comptroller this distributor is bound to
    Comptroller public comptroller; /// we can't make this immutable because we are using proxies

    /// construct the logic contract and initialize so that the initialize function is uncallable
    /// from the implementation and only callable from the proxy
    constructor() {
        _disableInitializers();
    }

    function initialize(address _comptroller) external initializer {
        // Sanity check the params
        require(
            _comptroller != address(0),
            "Comptroller can't be the 0 address!"
        );

        comptroller = Comptroller(payable(_comptroller));

        require(
            comptroller.isComptroller(),
            "Can't bind to something that's not a comptroller!"
        );
    }

    /// @notice A view to get a specific market info
    function getMarketInfo(
        MToken _mToken
    ) external view returns (Market memory) {
        Market memory _result;

        (bool _isListed, uint _collateralFactor) = comptroller.markets(
            address(_mToken)
        );

        if (_isListed) {
            _result.borrowCap = comptroller.borrowCaps(address(_mToken));
            _result.supplyCap = comptroller.supplyCaps(address(_mToken));
            _result.collateralFactor = _collateralFactor;
            _result.isListed = _isListed;
            _result.mintPaused = comptroller.mintGuardianPaused(
                address(_mToken)
            );
            _result.borrowPaused = comptroller.borrowGuardianPaused(
                address(_mToken)
            );
            _result.underlyingPrice = comptroller.oracle().getUnderlyingPrice(
                _mToken
            );

            _result.totalSupply = _mToken.totalSupply();
            _result.totalBorrows = _mToken.totalBorrows();
            _result.totalReserves = _mToken.totalReserves();
            _result.cash = _mToken.getCash();
            _result.exchangeRate = _mToken.exchangeRateStored();
            _result.borrowIndex = _mToken.borrowIndex();
            _result.reserveFactor = _mToken.reserveFactorMantissa();
            _result.borrowRate = _mToken.borrowRatePerTimestamp();
            _result.supplyRate = _mToken.supplyRatePerTimestamp();
            _result.incentives = getMarketIncentives(_mToken);
        }

        return _result;
    }

    /// @notice A view to enumerate specfic markets configs
    function getMarketsInfo(
        MToken[] calldata _mTokens
    ) external view returns (Market[] memory) {
        Market[] memory _result = new Market[](_mTokens.length);

        for (uint256 index = 0; index < _mTokens.length; index++) {
            _result[index] = this.getMarketInfo(_mTokens[index]);
        }

        return _result;
    }

    /// @notice A view to enumerate all market configs
    function getAllMarketsInfo() external view returns (Market[] memory) {
        MToken[] memory _mTokens = comptroller.getAllMarkets();

        Market[] memory _result = new Market[](_mTokens.length);

        for (uint256 index = 0; index < _mTokens.length; index++) {
            _result[index] = this.getMarketInfo(_mTokens[index]);
        }

        return _result;
    }

    function getMarketIncentives(
        MToken market
    ) public view virtual returns (MarketIncentives[] memory) {}
}
