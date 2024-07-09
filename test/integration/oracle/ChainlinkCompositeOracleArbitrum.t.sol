pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MockChainlinkOracle} from "@test/mock/MockChainlinkOracle.sol";
import {ChainlinkCompositeOracle} from "@protocol/oracles/ChainlinkCompositeOracle.sol";

contract ChainlinkCompositeOracleArbitrumTest is Test {
    ChainlinkCompositeOracle public oracle;

    /// @notice usd-eth exchange rate
    address public constant usdEthOracle =
        0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;

    /// @notice steth-eth exchange rate
    address public constant stethEthOracle =
        0xded2c52b75B24732e9107377B7Ba93eC1fFa4BAf;

    /// @notice wsteth-steth exchange rate
    address public constant wstethstEthOracle =
        0xB1552C5e96B312d0Bf8b554186F846C40614a540;

    /// @notice cbeth-eth exchange rate
    address public constant cbethEthOracle =
        0xa668682974E3f121185a3cD94f00322beC674275;

    /// @notice expected wsteth/usd price
    uint256 public constant expectedwstEthUsdPrice = 3614882813449691700118;

    /// @notice expected steth/usd price
    uint256 public constant expectedStethUsdPrice = 3105417811919294597070;

    /// @notice expected cbeth/usd price
    uint256 public constant expectedcbEthUsdPrice = 3308361417282418265307;

    function setUp() public {
        oracle = new ChainlinkCompositeOracle(
            usdEthOracle,
            stethEthOracle,
            wstethstEthOracle
        );

        /// this needs to be updated every 6 months for tests to pass as rolling
        /// to blocks too far in the past will cause the test to fail due to the rpc provider
        /// updating this value to the current block number means tests will fail if the eth
        /// price changes, so those will need to be updated too.
        vm.rollFork(202629125);
    }

    function testSetup() public view {
        assertEq(oracle.base(), usdEthOracle);
        assertEq(oracle.multiplier(), stethEthOracle);
        assertEq(oracle.secondMultiplier(), wstethstEthOracle);
        assertEq(oracle.decimals(), 18);
    }

    function test_stETH_USD_CompositeOracle() public view {
        uint256 price = oracle.getDerivedPrice(
            usdEthOracle,
            stethEthOracle,
            18
        );
        assertTrue(price > 0, "Price should be greater than 0");

        assertEq(expectedStethUsdPrice, price);
    }

    function testTestLatestRoundData() public view {
        (
            uint80 roundId, /// always 0, value unused in ChainlinkOracle.sol
            int256 answer, /// the composite price
            uint256 startedAt, /// always 0, value unused in ChainlinkOracle.sol
            uint256 updatedAt, /// always block.timestamp
            uint80 answeredInRound /// always 0, value unused in ChainlinkOracle.sol
        ) = oracle.latestRoundData();
        uint256 price = oracle.getDerivedPriceThreeOracles(
            usdEthOracle,
            stethEthOracle,
            wstethstEthOracle,
            18
        );

        assertTrue(answer > 0, "Price should be greater than 0");

        assertEq(price, uint256(answer), "Price should be equal to answer");
        assertEq(
            updatedAt,
            block.timestamp,
            "updatedAt should be equal to block.timestamp"
        );
        assertEq(roundId, 0, "roundId should be equal to 0");
        assertEq(startedAt, 0, "startedAt should be equal to 0");
        assertEq(answeredInRound, 0, "answeredInRound should be equal to 0");

        assertEq(
            expectedwstEthUsdPrice,
            price,
            "Price should be equal to expectedwstEthUsdPrice"
        );
    }

    function testTestLatestRoundDataCbEth() public {
        oracle = new ChainlinkCompositeOracle(
            usdEthOracle,
            cbethEthOracle,
            address(0)
        );
        (
            uint80 roundId, /// always 0, value unused in ChainlinkOracle.sol
            int256 answer, /// the composite price
            uint256 startedAt, /// always 0, value unused in ChainlinkOracle.sol
            uint256 updatedAt, /// always block.timestamp
            uint80 answeredInRound /// always 0, value unused in ChainlinkOracle.sol
        ) = oracle.latestRoundData();
        uint256 price = oracle.getDerivedPrice(
            usdEthOracle,
            cbethEthOracle,
            18
        );

        assertTrue(answer > 0, "Price should be greater than 0");

        assertEq(price, uint256(answer));
        assertEq(updatedAt, block.timestamp);
        assertEq(roundId, 0);
        assertEq(startedAt, 0);
        assertEq(answeredInRound, 0);

        assertEq(expectedcbEthUsdPrice, price);
    }

    function testScalePrice(
        int256 price,
        uint8 priceDecimals,
        uint8 expectedDecimals
    ) public view {
        price = int256(_bound(uint256(price), 100, 10_000e18)); /// bound price between 100 and 10_000e18
        priceDecimals = uint8(_bound(priceDecimals, 0, 18)); /// bound priceDecimals between 0 and 18
        expectedDecimals = uint8(_bound(expectedDecimals, 0, 18)); /// bound expectedDecimals between 0 and 18

        int256 scaledPrice = oracle.scalePrice(
            price,
            priceDecimals,
            expectedDecimals
        );

        if (priceDecimals > expectedDecimals) {
            assertEq(
                uint256(scaledPrice),
                uint256(price) /
                    (10 ** (_getAbsDelta(expectedDecimals, priceDecimals)))
            );
        } else {
            assertEq(
                uint256(scaledPrice),
                uint256(price) *
                    (10 ** (_getAbsDelta(expectedDecimals, priceDecimals)))
            );
        }

        if (expectedDecimals > priceDecimals) {
            /// if expected decimals is greater than price decimals, then return value must be greater than or equal to 100
            assertTrue(scaledPrice >= 100); /// price must be above minimum decimals
        }
    }

    function testCalculatePrice(
        int256 basePrice,
        int256 priceMultiplier,
        uint8 decimals
    ) public view {
        basePrice = int256(_bound(uint256(basePrice), 100, 10_000e18)); /// bound price between 100 and 10_000e18
        priceMultiplier = int256(
            _bound(uint256(priceMultiplier), 1e18, 10_000e18)
        ); /// bound price multiplier between 1e18 and 10_000e18
        /// scaling factor is between 1 and 1e18
        uint256 scalingFactor = 10 ** uint256(_bound(decimals, 0, 18)); /// bound decimals between 0 and 18

        assertEq(
            oracle.calculatePrice(
                basePrice,
                priceMultiplier,
                int256(scalingFactor)
            ),
            uint256((basePrice * priceMultiplier) / int256(scalingFactor))
        );
    }

    function _getAbsDelta(uint8 a, uint8 b) internal pure returns (uint8) {
        if (a > b) {
            return a - b;
        } else {
            return b - a;
        }
    }
}
