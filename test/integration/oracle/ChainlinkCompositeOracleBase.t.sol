pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MockChainlinkOracle} from "@test/mock/MockChainlinkOracle.sol";
import {ChainlinkCompositeOracle} from "@protocol/oracles/ChainlinkCompositeOracle.sol";

contract ChainlinkCompositeOracleIntegrationBaseTest is Test {
    ChainlinkCompositeOracle public oracle;

    /// @notice multiplier value
    address public constant cbEthEthOracle =
        0x806b4Ac04501c29769051e42783cF04dCE41440b;

    /// @notice eth usd value
    address public constant ethUsdOracle =
        0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;

    function setUp() public {
        oracle = new ChainlinkCompositeOracle(
            ethUsdOracle,
            cbEthEthOracle,
            address(0)
        );
    }

    function testSetup() public {
        assertEq(oracle.base(), ethUsdOracle);
        assertEq(oracle.multiplier(), cbEthEthOracle);
        assertEq(oracle.decimals(), 18);
    }

    function testcbETH_USD_CompositeOracle() public {
        uint256 price = oracle.getDerivedPrice(
            cbEthEthOracle,
            ethUsdOracle,
            18
        );
        assertTrue(price > 0, "Price should be greater than 0");
    }

    function testTestLatestRoundData() public {
        (
            uint80 roundId, /// always 0, value unused in ChainlinkOracle.sol
            int256 answer, /// the composite price
            uint256 startedAt, /// always 0, value unused in ChainlinkOracle.sol
            uint256 updatedAt, /// always block.timestamp
            uint80 answeredInRound /// always 0, value unused in ChainlinkOracle.sol
        ) = oracle.latestRoundData();
        uint256 price = oracle.getDerivedPrice(
            cbEthEthOracle,
            ethUsdOracle,
            18
        );

        assertTrue(answer > 0, "Price should be greater than 0");

        assertEq(price, uint256(answer));
        assertEq(updatedAt, block.timestamp);
        assertEq(roundId, 0);
        assertEq(startedAt, 0);
        assertEq(answeredInRound, 0);
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
