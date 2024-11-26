pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {DeployChainlinkOEVWrapper} from "@script/DeployChainlinkOEVWrapper.sol";
import {ChainlinkFeedOEVWrapper} from "@protocol/oracles/ChainlinkFeedOEVWrapper.sol";

contract ChainlinkOEVWrapperIntegrationTest is PostProposalCheck {
    event PriceUpdated(int256 newPrice);

    ChainlinkFeedOEVWrapper public wrapper;

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
        vm.deal(address(this), 1 ether);

        vm.warp(vm.getBlockTimestamp() + 1 days);

        int256 mockPrice = 3_000e8; // chainlink oracle uses 8 decimals

        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(
                wrapper.originalFeed().latestRoundData.selector
            ),
            abi.encode(mockPrice)
        );
        vm.txGasPrice(50 gwei); // Set gas price to 50 gwei
        vm.fee(25 gwei);
        // that means that priorityFee is 25 gwei
        int256 price = wrapper.updatePriceEarly{value: 25 gwei}();

        vm.expectEmit(address(wrapper));
        emit PriceUpdated(mockPrice);
        (, int256 answer, , , ) = wrapper.latestRoundData();

        assertEq(mockPrice, answer, "Price should be the same as answer");
        assertEq(mockPrice, price, "Price should be the same as price");
    }
}
