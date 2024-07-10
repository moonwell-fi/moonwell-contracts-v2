pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ChainlinkCompositeOracle} from "@protocol/oracles/ChainlinkCompositeOracle.sol";
import {MockChainlinkOracle} from "@test/mock/MockChainlinkOracle.sol";

contract OracleUnitTest is Test {
    MockChainlinkOracle public chainlinkOracleA;
    MockChainlinkOracle public chainlinkOracleB;
    MockChainlinkOracle public chainlinkOracleC;
    ChainlinkCompositeOracle public oracle;

    function setUp() public {
        chainlinkOracleA = new MockChainlinkOracle(1.1e18, 18);
        chainlinkOracleB = new MockChainlinkOracle(1.2e18, 18);
        chainlinkOracleC = new MockChainlinkOracle(1.3e18, 18);
        oracle = new ChainlinkCompositeOracle(
            address(chainlinkOracleA), address(chainlinkOracleB), address(chainlinkOracleC)
        );
    }

    function testSetup() public view {
        assertEq(oracle.decimals(), 18);

        assertEq(oracle.base(), address(chainlinkOracleA));
        assertEq(oracle.multiplier(), address(chainlinkOracleB));
        assertEq(oracle.secondMultiplier(), address(chainlinkOracleC));
    }

    function testOracleReadFailsInvalidDecimalsOver18() public {
        vm.expectRevert("CLCOracle: Invalid expected decimals");
        oracle.getDerivedPrice(address(chainlinkOracleA), address(chainlinkOracleB), 19);
    }

    function testOracleReadFailsInvalidDecimalsEq0() public {
        vm.expectRevert("CLCOracle: Invalid expected decimals");
        oracle.getDerivedPrice(address(chainlinkOracleA), address(chainlinkOracleB), 0);
    }

    function test3OracleReadFailsInvalidDecimalsOver18() public {
        vm.expectRevert("CLCOracle: Invalid expected decimals");
        oracle.getDerivedPriceThreeOracles(
            address(chainlinkOracleA), address(chainlinkOracleB), address(chainlinkOracleC), 19
        );
    }

    function test3OracleReadFailsInvalidDecimalsEq0() public {
        vm.expectRevert("CLCOracle: Invalid expected decimals");
        oracle.getDerivedPriceThreeOracles(
            address(chainlinkOracleA), address(chainlinkOracleB), address(chainlinkOracleC), 0
        );
    }

    function testCompositeOracleTwoAddresses() public view {
        uint256 price = oracle.getDerivedPrice(address(chainlinkOracleA), address(chainlinkOracleB), 18);
        assertTrue(price > 0, "Price should be greater than 0");
        assertEq(price, (((1e18 * 1.1e18) / 1e18) * 1.2e18) / 1e18);
    }

    function testCompositeOracleThreeAddresses() public view {
        uint256 price = oracle.getDerivedPriceThreeOracles(
            address(chainlinkOracleA), address(chainlinkOracleB), address(chainlinkOracleC), 18
        );
        assertTrue(price > 0, "Price should be greater than 0");
        assertEq(price, (((((1e18 * 1.1e18) / 1e18) * 1.2e18) / 1e18) * 1.3e18) / 1e18);
    }

    function testLatestRoundData() public view {
        (
            uint80 roundId,
            /// always 0, value unused in ChainlinkOracle.sol
            int256 answer,
            /// the composite price
            uint256 startedAt,
            /// always 0, value unused in ChainlinkOracle.sol
            uint256 updatedAt,
            /// always block.timestamp
            uint80 answeredInRound
        ) =
        /// always 0, value unused in ChainlinkOracle.sol
         oracle.latestRoundData();

        uint256 price = oracle.getDerivedPriceThreeOracles(
            address(chainlinkOracleA), address(chainlinkOracleB), address(chainlinkOracleC), 18
        );

        assertTrue(answer > 0, "Price should be greater than 0");

        assertEq(price, uint256(answer));
        assertEq(updatedAt, block.timestamp);
        assertEq(roundId, 0);
        assertEq(startedAt, 0);
        assertEq(answeredInRound, 0);
    }

    function testTestLatestRoundDataTwoOracles() public {
        oracle = new ChainlinkCompositeOracle(address(chainlinkOracleA), address(chainlinkOracleB), address(0));
        (
            uint80 roundId,
            /// always 0, value unused in ChainlinkOracle.sol
            int256 answer,
            /// the composite price
            uint256 startedAt,
            /// always 0, value unused in ChainlinkOracle.sol
            uint256 updatedAt,
            /// always block.timestamp
            uint80 answeredInRound
        ) =
        /// always 0, value unused in ChainlinkOracle.sol
         oracle.latestRoundData();

        uint256 price = oracle.getDerivedPrice(address(chainlinkOracleA), address(chainlinkOracleB), 18);

        assertTrue(answer > 0, "Price should be greater than 0");

        assertEq(price, uint256(answer));
        assertEq(updatedAt, block.timestamp);
        assertEq(roundId, 0);
        assertEq(startedAt, 0);
        assertEq(answeredInRound, 0);

        assertEq(price, (((1e18 * 1.1e18) / 1e18) * 1.2e18) / 1e18);
    }

    function testGetPriceAndDecimalsFailsInvalidChainlinkDataPriceZero() public {
        chainlinkOracleA.set(10, 0, 0, 0, 10);
        /// invalid because price is 0
        vm.expectRevert("CLCOracle: Oracle data is invalid");
        oracle.getDerivedPrice(address(chainlinkOracleA), address(chainlinkOracleB), 18);
    }

    function testGetPriceAndDecimalsFailsInvalidChainlinkDataRoundsIncorrect() public {
        chainlinkOracleA.set(11, 1, 0, 0, 10);
        /// invalid because rounds are desynced
        vm.expectRevert("CLCOracle: Oracle data is invalid");
        oracle.getDerivedPrice(address(chainlinkOracleA), address(chainlinkOracleB), 18);
    }

    function testScalePrice(int256 price, uint8 priceDecimals, uint8 expectedDecimals) public view {
        price = int256(_bound(uint256(price), 100, 10_000e18));
        /// bound price between 100 and 10_000e18
        priceDecimals = uint8(_bound(priceDecimals, 0, 18));
        /// bound priceDecimals between 0 and 18
        expectedDecimals = uint8(_bound(expectedDecimals, 0, 18));
        /// bound expectedDecimals between 0 and 18

        int256 scaledPrice = oracle.scalePrice(price, priceDecimals, expectedDecimals);

        if (priceDecimals > expectedDecimals) {
            assertEq(uint256(scaledPrice), uint256(price) / (10 ** (_getAbsDelta(expectedDecimals, priceDecimals))));
        } else {
            assertEq(uint256(scaledPrice), uint256(price) * (10 ** (_getAbsDelta(expectedDecimals, priceDecimals))));
        }

        if (expectedDecimals > priceDecimals) {
            /// if expected decimals is greater than price decimals, then return value must be greater than or equal to 100
            assertTrue(scaledPrice >= 100);
            /// price must be above minimum decimals
        }
    }

    function testCalculatePrice(int256 basePrice, int256 priceMultiplier, uint8 decimals) public view {
        basePrice = int256(_bound(uint256(basePrice), 100, 10_000e18));
        /// bound price between 100 and 10_000e18
        priceMultiplier = int256(_bound(uint256(priceMultiplier), 1e18, 10_000e18));
        /// bound price multiplier between 1e18 and 10_000e18
        /// scaling factor is between 1 and 1e18
        uint256 scalingFactor = 10 ** uint256(_bound(decimals, 0, 18));
        /// bound decimals between 0 and 18

        assertEq(
            oracle.calculatePrice(basePrice, priceMultiplier, int256(scalingFactor)),
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
