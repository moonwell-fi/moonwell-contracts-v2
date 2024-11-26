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
            address(this),
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

        int256 price = wrapper.updatePriceEarly{value: tax}();

        vm.expectEmit(address(wrapper));
        emit PriceUpdated(mockPrice);
        (, int256 answer, , , ) = wrapper.latestRoundData();

        assertEq(mockPrice, answer, "Price should be the same as answer");
        assertEq(mockPrice, price, "Price should be the same as price");
    }

    function testRevertIfInsufficientTax() public {
        uint256 tax = 25 gwei * multiplier;
        vm.deal(address(this), tax - 1);

        vm.txGasPrice(50 gwei); // Set gas price to 50 gwei
        vm.fee(25 gwei);
        vm.expectRevert("ChainlinkOEVWrapper: Insufficient tax");
        wrapper.updatePriceEarly{value: tax - 1}();
    }
}
