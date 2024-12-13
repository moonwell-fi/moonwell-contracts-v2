// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

import "@forge-std/Test.sol";

import "@utils/ChainIds.sol";

import {WETH9} from "@protocol/router/IWETH.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ChainlinkBoundedCompositeOracle} from "@protocol/oracles/ChainlinkBoundedCompositeOracle.sol";
import {DeployChainlinkBoundedCompositeOracle} from "@script/DeployChainlinkBoundedCompositeOracle.sol";

contract ChainlinkBoundedCompositeOracleIntegrationTest is Test {
    using ChainIds for uint256;

    /// @notice addresses contract
    Addresses public addresses;

    event BoundsUpdated(
        int256 oldLower,
        int256 newLower,
        int256 oldUpper,
        int256 newUpper
    );
    event ProtocolOEVRevenueUpdated(
        address indexed receiver,
        uint256 revenueAdded
    );
    event PrimaryOracleUpdated(
        address oldPrimaryOracle,
        address newPrimaryOracle
    );
    event BTCOracleUpdated(address oldBTCOracle, address newBTCOracle);
    event FallbackOracleUpdated(
        address oldFallbackOracle,
        address newFallbackOracle
    );
    event FeeMultiplierUpdated(
        uint16 oldFeeMultiplier,
        uint16 newFeeMultiplier
    );
    event EarlyUpdateWindowUpdated(uint256 oldWindow, uint256 newWindow);

    ChainlinkBoundedCompositeOracle public oracle;
    DeployChainlinkBoundedCompositeOracle public deployer;

    function setUp() public {
        MOONBEAM_FORK_ID.createForksAndSelect();

        vm.selectFork(BASE_FORK_ID);

        addresses = new Addresses();

        deployer = new DeployChainlinkBoundedCompositeOracle();
        oracle = deployer.deployChainlinkBoundedCompositeOracle(addresses);
    }

    function testSetup() public view {
        // Oracle addresses
        assertEq(
            address(oracle.primaryLBTCOracle()),
            addresses.getAddress("REDSTONE_LBTC_BTC")
        );
        assertEq(
            address(oracle.fallbackLBTCOracle()),
            addresses.getAddress("CHAINLINK_LBTC_MARKET")
        );

        // Bounds
        assertEq(oracle.lowerBound(), 9.9e17);
        assertEq(oracle.upperBound(), 1.05e18);

        // Other config
        assertEq(oracle.decimals(), 18);
        assertEq(oracle.owner(), addresses.getAddress("TEMPORAL_GOVERNOR"));
    }

    function testInvalidBounds() public {
        // Store addresses in variables for better readability
        address redStoneLbtcBtc = addresses.getAddress("REDSTONE_LBTC_BTC");
        address chainlinkLbtcMarket = addresses.getAddress(
            "CHAINLINK_LBTC_MARKET"
        );
        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        address moonwellWeth = addresses.getAddress("MOONWELL_WETH");
        address weth = addresses.getAddress("WETH");

        // Test equal bounds
        vm.expectRevert("ChainlinkBoundedCompositeOracle: Invalid bounds");
        new ChainlinkBoundedCompositeOracle(
            redStoneLbtcBtc,
            chainlinkLbtcMarket,
            1e18, // lower bound equal to upper bound
            1e18, // upper bound
            30 seconds, // early update window
            99, // fee multiplier
            temporalGovernor
        );

        // Test lower bound greater than upper bound
        vm.expectRevert("ChainlinkBoundedCompositeOracle: Invalid bounds");
        new ChainlinkBoundedCompositeOracle(
            redStoneLbtcBtc,
            chainlinkLbtcMarket,
            1.1e18, // lower bound greater than upper bound
            1e18, // upper bound
            30 seconds, // early update window
            99, // fee multiplier
            temporalGovernor
        );
    }

    function testLatestRoundDataWithinBounds() public {
        // Mock primary oracle response within bounds
        vm.mockCall(
            address(oracle.primaryLBTCOracle()),
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(
                uint80(1),
                1.005e8,
                uint256(0),
                block.timestamp,
                uint80(1)
            )
        );

        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = oracle.latestRoundData();

        assertEq(answer, 1.005e18, "Price should be 1.005 LBTC/BTC");
        assertEq(roundId, 0, "Round ID should be 0");
        assertEq(startedAt, 0, "Started at should be 0");
        assertEq(
            updatedAt,
            block.timestamp,
            "Updated at should be block timestamp"
        );
        assertEq(answeredInRound, 0, "Answered in round should be 0");
    }

    function testLatestRoundDataOutsideBounds() public {
        // Mock primary oracle response outside bounds (1.2)
        vm.mockCall(
            address(oracle.primaryLBTCOracle()),
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(uint80(1), 1.2e8, uint256(0), block.timestamp, uint80(1))
        );

        // Mock fallback oracle response
        vm.mockCall(
            address(oracle.fallbackLBTCOracle()),
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(uint80(1), 1.1e8, uint256(0), block.timestamp, uint80(1))
        );

        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = oracle.latestRoundData();

        assertEq(roundId, 0, "Round ID should be 0");
        assertEq(answer, 1.1e18, "Should use fallback price");
        assertEq(startedAt, 0, "Started at should be 0");
        assertEq(
            updatedAt,
            block.timestamp,
            "Updated at should be block timestamp"
        );
        assertEq(answeredInRound, 0, "Answered in round should be 0");
    }

    function testSetBoundsRevertNonOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        oracle.setBounds(8e17, 12e17);
    }

    function testSetBounds() public {
        int256 oldLower = oracle.lowerBound();
        int256 oldUpper = oracle.upperBound();
        int256 newLower = 8e17;
        int256 newUpper = 12e17;

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectEmit(address(oracle));
        emit BoundsUpdated(oldLower, newLower, oldUpper, newUpper);
        oracle.setBounds(newLower, newUpper);

        assertEq(oracle.lowerBound(), newLower);
        assertEq(oracle.upperBound(), newUpper);
    }

    function testSetBoundsRevertInvalidBounds() public {
        vm.startPrank(addresses.getAddress("TEMPORAL_GOVERNOR"));

        // Test lower bound greater than upper bound
        vm.expectRevert("ChainlinkBoundedCompositeOracle: Invalid bounds");
        oracle.setBounds(12e17, 11e17);

        vm.stopPrank();
    }

    function testScalePriceAllBranches() public view {
        // Test when priceDecimals < expectedDecimals
        assertEq(oracle.scalePrice(1000, 6, 8), 100000, "Scale up failed");

        // Test when priceDecimals > expectedDecimals
        assertEq(oracle.scalePrice(100000, 8, 6), 1000, "Scale down failed");

        // Test when priceDecimals == expectedDecimals
        assertEq(oracle.scalePrice(1000, 8, 8), 1000, "Equal decimals failed");
    }

    function testRevertOnStaleData() public {
        // Mock stale primary oracle data
        vm.mockCall(
            address(oracle.primaryLBTCOracle()),
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(
                uint80(2),
                1e18,
                uint256(0),
                block.timestamp,
                uint80(1) // answeredInRound < roundId
            )
        );

        vm.expectRevert("ChainlinkBoundedCompositeOracle: Stale price");
        oracle.latestRoundData();
    }

    function testRevertOnIncompleteRound() public {
        // Mock incomplete round
        vm.mockCall(
            address(oracle.primaryLBTCOracle()),
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(
                uint80(1),
                1e18,
                uint256(0),
                uint256(0), // updatedAt = 0
                uint80(1)
            )
        );

        vm.expectRevert(
            "ChainlinkBoundedCompositeOracle: Round is in incomplete state"
        );
        oracle.latestRoundData();
    }

    function testRevertOnNegativePrice() public {
        // Mock negative price
        vm.mockCall(
            address(oracle.primaryLBTCOracle()),
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(uint80(1), -1, uint256(0), block.timestamp, uint80(1))
        );

        vm.expectRevert("ChainlinkBoundedCompositeOracle: Invalid price");
        oracle.latestRoundData();
    }

    function testLatestRoundDataWithFallbackOracle() public {
        // Mock primary oracle response outside bounds (0.8)
        vm.mockCall(
            address(oracle.primaryLBTCOracle()),
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(uint80(1), 8e7, uint256(0), block.timestamp, uint80(1))
        );

        // Mock fallback oracle response to 0.75
        vm.mockCall(
            address(oracle.fallbackLBTCOracle()),
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(
                uint80(1),
                0.75e8,
                uint256(0),
                block.timestamp,
                uint80(1)
            )
        );

        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = oracle.latestRoundData();

        // Assert all returned values
        assertEq(roundId, 0, "Round ID should be 0");
        assertEq(answer, 0.75e18, "Should use fallback price");
        assertEq(startedAt, 0, "Started at should be 0");
        assertEq(
            updatedAt,
            block.timestamp,
            "Updated at should be block timestamp"
        );
        assertEq(answeredInRound, 0, "Answered in round should be 0");
    }

    function testSetPrimaryOracle() public {
        address newOracle = makeAddr("newPrimaryOracle");
        // Mock contract check
        vm.etch(newOracle, "dummy code");

        address oldPrimaryOracle = address(oracle.primaryLBTCOracle());
        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectEmit(address(oracle));
        emit PrimaryOracleUpdated(oldPrimaryOracle, newOracle);
        oracle.setPrimaryOracle(newOracle);

        assertEq(
            address(oracle.primaryLBTCOracle()),
            newOracle,
            "Primary oracle not updated"
        );
    }

    function testSetFallbackOracle() public {
        address newOracle = makeAddr("newFallbackOracle");
        // Mock contract check
        vm.etch(newOracle, "dummy code");
        address oldFallbackOracle = address(oracle.fallbackLBTCOracle());

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectEmit(address(oracle));
        emit FallbackOracleUpdated(oldFallbackOracle, newOracle);
        oracle.setFallbackOracle(newOracle);

        assertEq(
            address(oracle.fallbackLBTCOracle()),
            newOracle,
            "Fallback oracle not updated"
        );
    }

    function testSetPrimaryOracleRevertNonContract() public {
        address nonContract = makeAddr("nonContract");

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectRevert(
            "ChainlinkBoundedCompositeOracle: Primary oracle must be a contract"
        );
        oracle.setPrimaryOracle(nonContract);
    }

    function testSetFallbackOracleRevertNonContract() public {
        address nonContract = makeAddr("nonContract");

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectRevert(
            "ChainlinkBoundedCompositeOracle: Fallback oracle must be a contract"
        );
        oracle.setFallbackOracle(nonContract);
    }

    function testSetPrimaryOracleRevertNonOwner() public {
        address newOracle = makeAddr("newOracle");
        vm.etch(newOracle, "dummy code");

        vm.expectRevert("Ownable: caller is not the owner");
        oracle.setPrimaryOracle(newOracle);
    }

    function testSetFallbackOracleRevertNonOwner() public {
        address newOracle = makeAddr("newOracle");
        vm.etch(newOracle, "dummy code");

        vm.expectRevert("Ownable: caller is not the owner");
        oracle.setFallbackOracle(newOracle);
    }
}
