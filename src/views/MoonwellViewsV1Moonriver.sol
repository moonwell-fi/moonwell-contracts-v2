// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {MoonwellViewsV1Simple} from "@protocol/views/MoonwellViewsV1Simple.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {Well} from "@protocol/governance/Well.sol";
import {MToken} from "@protocol/MToken.sol";
import {MErc20Interface} from "@protocol/MTokenInterfaces.sol";
import {SafetyModuleInterfaceV1} from "@protocol/views/SafetyModuleInterfaceV1.sol";
import {UniswapV2PairInterface} from "@protocol/views/UniswapV2PairInterface.sol";

/**
 * @title Moonwell Views Contract for Moonriver
 * @author Moonwell
 * @notice Extends MoonwellViewsV1Simple with DEX-based pricing for Moonriver.
 *         Chainlink deprecated all Moonriver feeds, so prices come directly
 *         from Solarbeam DEX pairs.
 */
contract MoonwellViewsV1Moonriver is MoonwellViewsV1Simple {
    struct InitParams {
        address comptroller;
        address safetyModule;
        address governanceToken;
        address nativeMarket;
        address governanceTokenLP;
        address nativeWrapped;
        address stableToken;
        uint8 stableDecimals;
        address[] tokens;
        address[] pairs;
    }

    /// @notice Token address to Solarbeam DEX pair mapping
    mapping(address => address) public dexPairs;

    /// @notice Wrapped native token address (WMOVR)
    address public nativeWrapped;

    /// @notice USD stablecoin reference token (USDC)
    address public stableToken;

    /// @notice Decimals of the stable token
    uint8 public stableTokenDecimals;

    /// @notice Initialize all state: protocol config + DEX pricing
    function initialize(InitParams calldata params) external initializer {
        // Base protocol config
        require(params.comptroller != address(0));
        comptroller = Comptroller(payable(params.comptroller));
        require(comptroller.isComptroller());

        safetyModule = SafetyModuleInterfaceV1(params.safetyModule);
        governanceToken = Well(params.governanceToken);
        _nativeMarket = params.nativeMarket;
        _governanceTokenLP = UniswapV2PairInterface(params.governanceTokenLP);

        // DEX pricing config
        require(params.tokens.length == params.pairs.length);

        nativeWrapped = params.nativeWrapped;
        stableToken = params.stableToken;
        stableTokenDecimals = params.stableDecimals;

        for (uint i = 0; i < params.tokens.length; i++) {
            dexPairs[params.tokens[i]] = params.pairs[i];
        }
    }

    /// @notice Get native token price from DEX (WMOVR/USDC pair)
    /// @return price in oracle format (1e18 mantissa for 18-decimal token)
    function _getNativeTokenPriceFromDex() internal view returns (uint) {
        address pair = dexPairs[nativeWrapped];
        if (pair == address(0) || stableToken == address(0)) return 0;

        (uint112 r0, uint112 r1, ) = UniswapV2PairInterface(pair).getReserves();
        address token0 = UniswapV2PairInterface(pair).token0();

        uint stableReserve = token0 == nativeWrapped ? uint(r1) : uint(r0);
        uint nativeReserve = token0 == nativeWrapped ? uint(r0) : uint(r1);

        if (nativeReserve == 0) return 0;

        // nativePrice = stableReserve * 10^(36 - stableDecimals) / nativeReserve
        return
            (stableReserve * (10 ** (36 - stableTokenDecimals))) /
            nativeReserve;
    }

    /// @notice Get token price from DEX via token/WMOVR pair + MOVR/USD
    /// @return price in oracle format (10^(36 - tokenDecimals) mantissa)
    function _getTokenPriceFromDex(address token) internal view returns (uint) {
        if (token == nativeWrapped) return _getNativeTokenPriceFromDex();

        address pair = dexPairs[token];
        if (pair == address(0)) return 0;

        (uint112 r0, uint112 r1, ) = UniswapV2PairInterface(pair).getReserves();
        address token0 = UniswapV2PairInterface(pair).token0();

        uint nativeReserve = token0 == token ? uint(r1) : uint(r0);
        uint tokenReserve = token0 == token ? uint(r0) : uint(r1);

        if (tokenReserve == 0) return 0;

        uint nativePrice = getNativeTokenPrice();
        // tokenPrice = nativeReserve * nativePrice / tokenReserve
        // This formula is decimal-independent (works for any token decimals)
        return (nativeReserve * nativePrice) / tokenReserve;
    }

    /// @notice Get underlying price purely from DEX (Chainlink deprecated on Moonriver)
    function _getUnderlyingPrice(
        MToken _mToken
    ) internal view override returns (uint) {
        if (address(_mToken) == _nativeMarket) {
            return _getNativeTokenPriceFromDex();
        }
        return
            _getTokenPriceFromDex(
                MErc20Interface(address(_mToken)).underlying()
            );
    }

    /// @notice Native token price purely from DEX (Chainlink deprecated on Moonriver)
    function getNativeTokenPrice()
        public
        view
        virtual
        override
        returns (uint _result)
    {
        _result = _getNativeTokenPriceFromDex();
    }
}
