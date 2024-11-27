pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {DeployChainlinkOEVWrapper} from "@script/DeployChainlinkOEVWrapper.sol";
import {ChainlinkFeedOEVWrapper} from "@protocol/oracles/ChainlinkFeedOEVWrapper.sol";

contract ChainlinkOEVWrapperIntegrationTest is PostProposalCheck {
    event PriceUpdated(int256 newPrice);

    ChainlinkFeedOEVWrapper public wrapper;

    uint256 public constant multiplier = 99;

    function setUp() public override {
        uint256 primaryForkId = vm.envUint("PRIMARY_FORK_ID");

        super.setUp();
        vm.selectFork(primaryForkId);

        DeployChainlinkOEVWrapper deployScript = new DeployChainlinkOEVWrapper();
        wrapper = deployScript.deployChainlinkOEVWrapper(
            addresses,
            "CHAINLINK_ETH_USD"
        );
    }

    function testCanUpdatePriceEarly() public {
        vm.warp(vm.getBlockTimestamp() + 1 days);

        int256 mockPrice = 3_000e8; // chainlink oracle uses 8 decimals

        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(
                wrapper.originalFeed().latestRoundData.selector
            ),
            abi.encode(
                uint80(1), // roundId
                mockPrice, // answer
                uint256(0), // startedAt
                uint256(block.timestamp), // updatedAt
                uint80(1) // answeredInRound
            )
        );

        uint256 tax = (50 gwei - 25 gwei) * multiplier; // (gasPrice - baseFee) * multiplier
        vm.deal(address(this), tax);
        vm.txGasPrice(50 gwei); // Set gas price to 50 gwei
        vm.fee(25 gwei); // Set base fee to 25 gwei
        vm.expectEmit(address(wrapper));
        emit PriceUpdated(mockPrice);
        int256 price = wrapper.updatePriceEarly{value: tax}();

        (, int256 answer, , uint256 timestamp, ) = wrapper.latestRoundData();

        vm.warp(vm.getBlockTimestamp() + 1);

        assertEq(mockPrice, answer, "Price should be the same as answer");
        assertEq(mockPrice, price, "Price should be the same as price");
        assertEq(
            timestamp,
            block.timestamp - 1,
            "Timestamp should be the same as block.timestamp - 1"
        );
    }

    function testReturnOriginalFeedPriceIfEarlyUpdateWindowHasPassed() public {
        testCanUpdatePriceEarly();

        vm.warp(vm.getBlockTimestamp() + wrapper.earlyUpdateWindow());

        int256 mockPrice = 3_3333e8; // chainlink oracle uses 8 decimals
        uint256 mockTimestamp = block.timestamp - 1;
        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(
                wrapper.originalFeed().latestRoundData.selector
            ),
            abi.encode(uint80(1), mockPrice, 0, mockTimestamp, uint80(1))
        );
        (, int256 answer, , uint256 timestamp, ) = wrapper.latestRoundData();

        assertEq(mockPrice, answer, "Price should be the same as answer");
        assertEq(
            timestamp,
            mockTimestamp,
            "Timestamp should be the same as block.timestamp"
        );
    }

    function testRevertIfInsufficientTax() public {
        uint256 tax = 25 gwei * multiplier;
        vm.deal(address(this), tax - 1);

        vm.txGasPrice(50 gwei);
        vm.fee(25 gwei);
        vm.expectRevert("ChainlinkOEVWrapper: Insufficient tax");
        wrapper.updatePriceEarly{value: tax - 1}();
    }

    function testLiquidationOpportunity() public {}
}
