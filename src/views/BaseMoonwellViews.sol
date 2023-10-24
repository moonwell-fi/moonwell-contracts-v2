// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MToken} from "@protocol/MToken.sol";
import {PriceOracle} from "@protocol//Oracles/PriceOracle.sol";
import {TokenSaleDistributorInterfaceV1} from "@protocol/views/TokenSaleDistributorInterfaceV1.sol";
import {SafetyModuleInterfaceV1} from "@protocol/views/SafetyModuleInterfaceV1.sol";
import {Well} from "@protocol/Governance/Well.sol";
import {IERC20} from "@protocol/Governance/IERC20.sol";
import {MErc20Interface} from "@protocol/MTokenInterfaces.sol";

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

    struct Votes {
        uint votingPower;
        address delegates;
    }

    struct Balances {
        uint amount;
        address token;
    }

    struct Rewards {
        address market;
        address rewardToken;
        uint supplyRewardsAmount;
        uint borrowRewardsAmount;
    }

    struct UserVotes {
        Votes claimsVotes;
        Votes stakingVotes;
        Votes tokenVotes;
    }

    struct UserStakingInfo {
        uint cooldown;
        uint pendingRewards;
        uint totalStaked;
    }

    Comptroller public comptroller;
    TokenSaleDistributorInterfaceV1 public tokenSaleDistributor;
    SafetyModuleInterfaceV1 public safetyModule;
    Well public governanceToken;
    address public nativeMarket;

    /// construct the logic contract and initialize so that the initialize function is uncallable
    /// from the implementation and only callable from the proxy
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _comptroller,
        address _tokenSaleDistributor,
        address _safetyModule,
        address _governanceToken,
        address _nativeMarket
    ) external initializer {
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

        tokenSaleDistributor = TokenSaleDistributorInterfaceV1(
            address(_tokenSaleDistributor)
        );

        safetyModule = SafetyModuleInterfaceV1(address(_safetyModule));
        governanceToken = Well(address(_governanceToken));
        nativeMarket = _nativeMarket;
    }

    /// @notice Virtual function to get the user accrued and pendings rewards, must be overriden depending on the version of the deployment
    function getSupplyCaps(
        address _market
    ) public view virtual returns (uint) {}

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
            _result.supplyCap = getSupplyCaps(address(_mToken));
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

    /// @notice Virtual function to get market incentives, must be overrided overriden on the version of the deployment
    function getMarketIncentives(
        MToken market
    ) public view virtual returns (MarketIncentives[] memory) {}

    /// @notice A view to get the user voting power from the tokens staking in the safety module
    function getUserStakingVotingPower(
        address _user
    ) public view virtual returns (Votes memory _result) {
        if (address(safetyModule) != address(0)) {
            uint _priorVotes = safetyModule.getPriorVotes(
                _user,
                block.number - 1
            );
            _result = Votes(_priorVotes, address(0));
        }
    }

    /// @notice A view to get the user voting power from the user vested tokens
    function getUserClaimsVotingPower(
        address _user
    ) public view virtual returns (Votes memory _result) {
        if (address(tokenSaleDistributor) != address(0)) {
            uint _priorVotes = tokenSaleDistributor.getPriorVotes(
                _user,
                block.number - 1
            );
            uint _totalAllocated = tokenSaleDistributor.totalAllocated(_user);
            uint _totalClaimed = tokenSaleDistributor.totalClaimed(_user);
            address _delegates = tokenSaleDistributor.delegates(_user);
            _result = Votes(
                _priorVotes + (_totalAllocated - _totalClaimed),
                _delegates
            );
        }
    }

    /// @notice A view to get the user voting power from the user holdings
    function getUserTokensVotingPower(
        address _user
    ) public view virtual returns (Votes memory _result) {
        if (address(governanceToken) != address(0)) {
            uint _priorVotes = governanceToken.getPriorVotes(
                _user,
                block.number - 1
            );
            address _delegates = governanceToken.delegates(_user);
            _result = Votes(_priorVotes, _delegates);
        }
    }

    /// @notice A view to get the user voting power from all the possible sources
    function getUserVotingPower(
        address _user
    ) public view virtual returns (UserVotes memory _result) {
        _result.claimsVotes = getUserClaimsVotingPower(_user);
        _result.stakingVotes = getUserStakingVotingPower(_user);
        _result.tokenVotes = getUserTokensVotingPower(_user);
    }

    /// @notice Auxiliary function to get user token balances
    function getTokensBalances(
        address[] memory _tokens,
        address _user
    ) public view returns (Balances[] memory) {
        Balances[] memory _result = new Balances[](_tokens.length);

        // Loop through tokens
        for (uint index = 0; index < _tokens.length; index++) {
            if (_tokens[index] == address(0)) {
                _result[index] = Balances(_user.balance, address(0));
            } else {
                IERC20 token = IERC20(_tokens[index]);
                _result[index] = Balances(
                    token.balanceOf(_user),
                    address(token)
                );
            }
        }

        return _result;
    }

    /// @notice View function to get the user balances from mTokens and the underlying tokens, including the native token and governance token
    function getUserBalances(
        address _user
    ) public view returns (Balances[] memory) {
        MToken[] memory _mTokens = comptroller.getAllMarkets();

        //Gov token + Native + Markets + Underlying
        uint _resultSize = (_mTokens.length * 2) + 1;
        uint _currIndex;

        if (address(governanceToken) != address(0)) {
            _resultSize++;
        }

        address[] memory _tokens = new address[](_resultSize);

        // Gov token balance
        if (address(governanceToken) != address(0)) {
            _tokens[_currIndex] = address(governanceToken);
            _currIndex++;
        }

        {
            // Native token balance
            _tokens[_currIndex] = address(0);
            _currIndex++;
        }

        // Loop through markets and underlying tokens
        for (uint index = 0; index < _mTokens.length; index++) {
            MToken mToken = _mTokens[index];
            address underlyingToken = address(0);
            if (address(mToken) != nativeMarket) {
                underlyingToken = address(
                    MErc20Interface(address(mToken)).underlying()
                );
            }
            _tokens[_currIndex] = address(mToken);
            _tokens[_currIndex + 1] = address(underlyingToken);
            _currIndex += 2;
        }

        return getTokensBalances(_tokens, _user);
    }

    /// @notice Virtual function to get the user accrued and pendings rewards, must be overriden depending on the version of the deployment
    function getUserRewards(
        address _user
    ) public view virtual returns (Rewards[] memory) {}

    /// @notice Virtual function to get the user accrued and pendings rewards, must be overriden depending on the version of the deployment
    function getUserStakingInfo(
        address _user
    ) public view returns (UserStakingInfo memory _result) {
        if (address(safetyModule) != address(0)) {
            _result.pendingRewards = safetyModule.getTotalRewardsBalance(_user);
            _result.cooldown = safetyModule.stakersCooldowns(_user);
            _result.totalStaked = safetyModule.balanceOf(_user);
        }
    }
}
