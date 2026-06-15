// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {xWELLBridgeFeePayer} from "@protocol/xWELL/xWELLBridgeFeePayer.sol";
import {MockERC20} from "@test/mock/MockERC20.sol";

/// @notice minimal adapter mock: quotes a fixed cost, requires exact
/// msg.value like the real WormholeBridgeAdapter, and pulls the tokens.
contract MockBridgeAdapter {
    uint256 public cost;
    MockERC20 public token;

    uint256 public lastAmount;
    address public lastTo;
    uint256 public lastValue;

    constructor(MockERC20 _token, uint256 _cost) {
        token = _token;
        cost = _cost;
    }

    function setCost(uint256 _cost) external {
        cost = _cost;
    }

    function bridgeCost(uint16) external view returns (uint256) {
        return cost;
    }

    function bridge(uint256, uint256 amount, address to) external payable {
        require(msg.value == cost, "WormholeBridge: cost not equal to quote");
        token.transferFrom(msg.sender, address(this), amount);
        lastAmount = amount;
        lastTo = to;
        lastValue = msg.value;
    }
}

contract xWELLBridgeFeePayerUnitTest is Test {
    MockERC20 xwell;
    MockBridgeAdapter adapter;
    xWELLBridgeFeePayer feePayer;

    address governor = address(0x1111);
    address sweeper = address(0x2222);
    address baseTG = address(0x3333);

    uint16 constant BASE_WH_ID = 30;
    uint256 constant COST = 0.0001 ether;

    function setUp() public {
        xwell = new MockERC20();
        adapter = new MockBridgeAdapter(xwell, COST);
        feePayer = new xWELLBridgeFeePayer(
            address(xwell),
            address(adapter),
            governor,
            sweeper
        );

        xwell.mint(governor, 1_000_000e18);
        vm.prank(governor);
        xwell.approve(address(feePayer), type(uint256).max);
    }

    function testBridgePaysLiveQuoteFromOwnBalance() public {
        vm.deal(address(feePayer), 1 ether);

        vm.prank(governor);
        feePayer.bridgeToRecipient(baseTG, 100e18, BASE_WH_ID);

        assertEq(adapter.lastAmount(), 100e18, "amount");
        assertEq(adapter.lastTo(), baseTG, "recipient");
        assertEq(adapter.lastValue(), COST, "fee paid from fee payer balance");
        assertEq(address(feePayer).balance, 1 ether - COST, "balance reduced");
        assertEq(xwell.balanceOf(address(feePayer)), 0, "no xWELL left behind");
    }

    function testBridgeSurvivesQuoteDrift() public {
        // the quote moving between "propose" and "execute" must not matter:
        // the fee payer reads it live in the same transaction
        vm.deal(address(feePayer), 1 ether);
        adapter.setCost(COST * 3);

        vm.prank(governor);
        feePayer.bridgeToRecipient(baseTG, 100e18, BASE_WH_ID);

        assertEq(adapter.lastValue(), COST * 3, "drifted quote paid exactly");
    }

    function testBridgeRevertsForNonCaller() public {
        vm.deal(address(feePayer), 1 ether);

        vm.expectRevert("FeePayer: only caller");
        feePayer.bridgeToRecipient(baseTG, 100e18, BASE_WH_ID);
    }

    function testBridgeRevertsOnZeroQuote() public {
        vm.deal(address(feePayer), 1 ether);
        adapter.setCost(0);

        vm.prank(governor);
        vm.expectRevert("FeePayer: quote unavailable");
        feePayer.bridgeToRecipient(baseTG, 100e18, BASE_WH_ID);
    }

    function testBridgeRevertsWhenUnderfunded() public {
        vm.prank(governor);
        vm.expectRevert("FeePayer: insufficient fee balance");
        feePayer.bridgeToRecipient(baseTG, 100e18, BASE_WH_ID);
    }

    function testAnyoneCanTopUp() public {
        vm.deal(address(0x4444), 1 ether);
        vm.prank(address(0x4444));
        (bool ok, ) = address(feePayer).call{value: 0.5 ether}("");
        assertTrue(ok, "top-up accepted");
        assertEq(address(feePayer).balance, 0.5 ether);
    }

    function testSweepOnlySweeper() public {
        vm.deal(address(feePayer), 1 ether);

        vm.expectRevert("FeePayer: only sweeper");
        feePayer.sweep(address(this));

        vm.prank(sweeper);
        feePayer.sweep(sweeper);
        assertEq(address(feePayer).balance, 0, "swept");
        assertEq(sweeper.balance, 1 ether, "received");
    }

    function testSweepTokenOnlySweeper() public {
        xwell.mint(address(feePayer), 123e18); // accidentally-sent tokens

        vm.expectRevert("FeePayer: only sweeper");
        feePayer.sweepToken(address(xwell), address(this));

        vm.prank(sweeper);
        feePayer.sweepToken(address(xwell), sweeper);
        assertEq(xwell.balanceOf(address(feePayer)), 0, "token swept");
        assertEq(xwell.balanceOf(sweeper), 123e18, "token received");
    }
}
