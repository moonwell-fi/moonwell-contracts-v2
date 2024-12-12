// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {WETH9} from "@protocol/router/IWETH.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {ChainlinkBoundedCompositeOracle} from "@protocol/oracles/ChainlinkBoundedCompositeOracle.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {DeployChainlinkBoundedCompositeOracle} from "@script/DeployChainlinkBoundedCompositeOracle.sol";

/// TODO remove post proposal check as this contract does not fit into the broader system
contract ChainlinkBoundedCompositeOracleIntegrationTest is PostProposalCheck {
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

    function setUp() public override {
        uint256 primaryForkId = vm.envUint("PRIMARY_FORK_ID");
        super.setUp();

        vm.selectFork(primaryForkId);
        vm.warp(block.timestamp - 1 days);
        console.log("block timestamp: ", block.timestamp);
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
            address(oracle.btcChainlinkOracle()),
            addresses.getAddress("CHAINLINK_BTC_USD")
        );
        assertEq(
            address(oracle.fallbackLBTCOracle()),
            addresses.getAddress("CHAINLINK_LBTC_MARKET")
        );

        // Bounds
        assertEq(oracle.lowerBound(), 9.9e17);
        assertEq(oracle.upperBound(), 1.05e18);

        // Early update config
        assertEq(oracle.earlyUpdateWindow(), 30 seconds);
        assertEq(oracle.feeMultiplier(), 99);

        // Protocol addresses
        assertEq(address(oracle.WETH()), addresses.getAddress("WETH"));
        assertEq(
            address(oracle.WETHMarket()),
            addresses.getAddress("MOONWELL_WETH")
        );

        // Other config
        assertEq(oracle.decimals(), 18);
        assertEq(oracle.owner(), addresses.getAddress("TEMPORAL_GOVERNOR"));
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

        // Mock BTC/USD price
        vm.mockCall(
            address(oracle.btcChainlinkOracle()),
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(
                uint80(1),
                50_000e8,
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

        assertEq(answer, 50_250e18, "Price should be 50,250 USD");
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

        // Mock BTC/USD price
        vm.mockCall(
            address(oracle.btcChainlinkOracle()),
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(
                uint80(1),
                50_000e8,
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

        assertEq(roundId, 0, "Round ID should be 0");
        assertEq(answer, 55_000e18, "Should use fallback price");
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

        // Mock fallback oracle response
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

        // Mock BTC/USD price
        vm.mockCall(
            address(oracle.btcChainlinkOracle()),
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(
                uint80(1),
                50_000e8,
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
        assertEq(answer, 37_500e18, "Should use fallback price");
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

    function testSetBTCOracle() public {
        address newOracle = makeAddr("newBTCOracle");
        // Mock contract check
        vm.etch(newOracle, "dummy code");
        address oldBTCOracle = address(oracle.btcChainlinkOracle());

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectEmit(address(oracle));
        emit BTCOracleUpdated(oldBTCOracle, newOracle);
        oracle.setBTCOracle(newOracle);

        assertEq(
            address(oracle.btcChainlinkOracle()),
            newOracle,
            "BTC oracle not updated"
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

    function testSetBTCOracleRevertNonContract() public {
        address nonContract = makeAddr("nonContract");

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectRevert(
            "ChainlinkBoundedCompositeOracle: BTC oracle must be a contract"
        );
        oracle.setBTCOracle(nonContract);
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

    function testSetBTCOracleRevertNonOwner() public {
        address newOracle = makeAddr("newOracle");
        vm.etch(newOracle, "dummy code");

        vm.expectRevert("Ownable: caller is not the owner");
        oracle.setBTCOracle(newOracle);
    }

    function testSetFallbackOracleRevertNonOwner() public {
        address newOracle = makeAddr("newOracle");
        vm.etch(newOracle, "dummy code");

        vm.expectRevert("Ownable: caller is not the owner");
        oracle.setFallbackOracle(newOracle);
    }

    function testSetFeeMultiplierRevertNonOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        oracle.setFeeMultiplier(100);
    }

    function testSetEarlyUpdateWindowRevertNonOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        oracle.setEarlyUpdateWindow(1 hours);
    }

    function testSetFeeMultiplier() public {
        uint16 newMultiplier = 100;
        uint16 oldMultiplier = oracle.feeMultiplier();

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectEmit(address(oracle));
        emit FeeMultiplierUpdated(oldMultiplier, newMultiplier);
        oracle.setFeeMultiplier(newMultiplier);

        assertEq(oracle.feeMultiplier(), newMultiplier);
    }

    function testSetEarlyUpdateWindow() public {
        uint256 newWindow = 1 hours;
        uint256 oldWindow = oracle.earlyUpdateWindow();

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectEmit(address(oracle));
        emit EarlyUpdateWindowUpdated(oldWindow, newWindow);
        oracle.setEarlyUpdateWindow(newWindow);

        assertEq(oracle.earlyUpdateWindow(), newWindow);
    }
}
