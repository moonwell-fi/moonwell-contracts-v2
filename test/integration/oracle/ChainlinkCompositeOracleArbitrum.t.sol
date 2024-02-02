pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ChainlinkCompositeOracle} from "@protocol/Oracles/ChainlinkCompositeOracle.sol";

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
    uint256 public constant expectedwstEthUsdPrice = 1961081787640101877788;

    /// @notice expected steth/usd price
    uint256 public constant expectedStethUsdPrice = 1737398897450621932100;

    /// @notice expected cbeth/usd price
    uint256 public constant expectedcbEthUsdPrice = 1806705256062053314476;

    function setUp() public {
        oracle = new ChainlinkCompositeOracle(
            usdEthOracle,
            stethEthOracle,
            wstethstEthOracle
        );

        vm.rollFork(102516073);
    }

    function testSetup() public {
        assertEq(oracle.base(), usdEthOracle);
        assertEq(oracle.multiplier(), stethEthOracle);
        assertEq(oracle.secondMultiplier(), wstethstEthOracle);
        assertEq(oracle.decimals(), 18);
    }

    function test_stETH_USD_CompositeOracle() public {
        uint256 price = oracle.getDerivedPrice(
            usdEthOracle,
            stethEthOracle,
            18
        );
        assertTrue(price > 0, "Price should be greater than 0");

        console.log("price: %s", price);
        assertEq(expectedStethUsdPrice, price);
    }

    function testTestLatestRoundData() public {
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

        assertEq(price, uint256(answer));
        assertEq(updatedAt, block.timestamp);
        assertEq(roundId, 0);
        assertEq(startedAt, 0);
        assertEq(answeredInRound, 0);

        console.log("price: %s", price);

        assertEq(expectedwstEthUsdPrice, price);
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

        console.log("price: %s", price);

        assertEq(expectedcbEthUsdPrice, price);
    }

    function testScalePrice(
        int256 price,
        uint8 priceDecimals,
        uint8 expectedDecimals
    ) public {
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
    ) public {
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
