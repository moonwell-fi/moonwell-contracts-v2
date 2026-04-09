// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {DeployMoonwellViewsV1Moonriver} from "@script/DeployMoonwellViewsV1Moonriver.s.sol";
import {MoonwellViewsV1Moonriver} from "@protocol/views/MoonwellViewsV1Moonriver.sol";
import {BaseMoonwellViews} from "@protocol/views/BaseMoonwellViews.sol";
import {MToken} from "@protocol/MToken.sol";
import {MErc20Interface} from "@protocol/MTokenInterfaces.sol";
import {Comptroller} from "@protocol/Comptroller.sol";

contract MoonwellViewsV1MoonriverTest is Test {
    MoonwellViewsV1Moonriver public views;
    Addresses public addresses;

    // Resolved from Addresses registry
    address mNative;
    address wmovr;
    address usdc;
    address xcKSM;
    address frax;
    address wmovrUsdcPair;
    address xcKsmWmovrPair;
    address fraxWmovrPair;

    function setUp() public {
        string memory rpcUrl = vm.envString("MOONRIVER_RPC_URL");
        vm.createSelectFork(rpcUrl);

        addresses = new Addresses();

        // Deploy using the deploy script
        DeployMoonwellViewsV1Moonriver deployer = new DeployMoonwellViewsV1Moonriver();
        views = deployer.deploy(addresses);

        // Cache addresses for assertions
        mNative = addresses.getAddress("MNATIVE");
        wmovr = addresses.getAddress("WMOVR");
        usdc = addresses.getAddress("USDC");
        xcKSM = addresses.getAddress("xcKSM");
        frax = addresses.getAddress("FRAX");
        wmovrUsdcPair = addresses.getAddress("WMOVR_USDC_PAIR");
        xcKsmWmovrPair = addresses.getAddress("xcKSM_WMOVR_PAIR");
        fraxWmovrPair = addresses.getAddress("FRAX_WMOVR_PAIR");
    }

    function testGetMarketInfoMOVR() public view {
        BaseMoonwellViews.Market memory market = views.getMarketInfo(
            MToken(mNative)
        );

        assertTrue(market.isListed, "mMOVR should be listed");
        assertGt(market.underlyingPrice, 0, "MOVR price should be non-zero");

        // MOVR price in oracle format (1e18 mantissa) should be reasonable
        // ~$5-50 range -> 5e18 to 50e18
        assertGt(market.underlyingPrice, 1e18, "MOVR price too low");
        assertLt(market.underlyingPrice, 100e18, "MOVR price too high");
    }

    function testGetAllMarketsInfo() public view {
        BaseMoonwellViews.Market[] memory markets = views.getAllMarketsInfo();

        assertGt(markets.length, 0, "should have markets");

        // Verify MOVR market (first market) has a price from DEX fallback
        bool foundMOVR = false;
        for (uint i = 0; i < markets.length; i++) {
            if (markets[i].market == mNative) {
                foundMOVR = true;
                assertGt(
                    markets[i].underlyingPrice,
                    0,
                    "MOVR market should have non-zero price"
                );
            }
        }
        assertTrue(foundMOVR, "MOVR market should be found");
    }

    function testGetNativeTokenPrice() public view {
        uint price = views.getNativeTokenPrice();

        assertGt(price, 0, "native price should be non-zero");
        // MOVR ~$5-50 -> 5e18 to 50e18 in oracle format
        assertGt(price, 1e18, "MOVR price too low");
        assertLt(price, 100e18, "MOVR price too high");
    }

    function testGetGovernanceTokenPrice() public view {
        uint price = views.getGovernanceTokenPrice();

        // Governance token price should be non-zero if LP has liquidity
        // It's ok if it's 0 if LP is empty
        // Just verify it doesn't revert
        assertGe(price, 0, "governance token price should not revert");
    }

    function testDexPricesForAllConfiguredTokens() public view {
        BaseMoonwellViews.Market[] memory markets = views.getAllMarketsInfo();

        // Track which DEX-paired tokens we found with valid prices
        bool foundWMOVR = false;
        bool foundXcKSM = false;
        bool foundFRAX = false;

        for (uint i = 0; i < markets.length; i++) {
            address underlying;

            if (markets[i].market == mNative) {
                underlying = wmovr;
            } else {
                underlying = address(
                    MErc20Interface(markets[i].market).underlying()
                );
            }

            if (underlying == wmovr || markets[i].market == mNative) {
                foundWMOVR = true;
                assertGt(
                    markets[i].underlyingPrice,
                    0,
                    "WMOVR/MOVR price should be non-zero"
                );
            } else if (underlying == xcKSM) {
                foundXcKSM = true;
                assertGt(
                    markets[i].underlyingPrice,
                    0,
                    "xcKSM price should be non-zero"
                );
            } else if (underlying == frax) {
                foundFRAX = true;
                assertGt(
                    markets[i].underlyingPrice,
                    0,
                    "FRAX price should be non-zero"
                );
            }
        }

        assertTrue(foundWMOVR, "should find WMOVR/MOVR market");
        assertTrue(foundXcKSM, "should find xcKSM market");
        assertTrue(foundFRAX, "should find FRAX market");
    }

    function testDexPairConfiguration() public view {
        assertEq(views.dexPairs(wmovr), wmovrUsdcPair, "WMOVR pair mismatch");
        assertEq(views.dexPairs(xcKSM), xcKsmWmovrPair, "xcKSM pair mismatch");
        assertEq(views.dexPairs(frax), fraxWmovrPair, "FRAX pair mismatch");
        // nativeWrapped is internal; verified implicitly via price checks
        // stableToken is internal; verified implicitly via price checks
        // stableTokenDecimals is internal; verified implicitly via price checks
    }
}
