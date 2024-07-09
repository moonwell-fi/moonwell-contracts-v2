pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Recovery} from "@protocol/Recovery.sol";

import {FailingReceiver} from "@test/mock/FailingReceiver.sol";
import {RecoveryDeploy} from "@test/utils/RecoveryDeploy.sol";

contract RecoveryUnitTest is Test, RecoveryDeploy {
    Recovery recover;

    function setUp() public {
        recover = deploy(address(this));
    }

    function testOwner() public view {
        assertEq(recover.owner(), address(this));
    }

    function testOwnerCanCallSendAllEth(uint128 ethAmount) public {
        vm.deal(address(recover), ethAmount);
        assertEq(address(recover).balance, ethAmount);
        uint256 startingEthBalance = address(this).balance;

        recover.sendAllEth(payable(address(this)));

        assertEq(
            address(this).balance,
            ethAmount + startingEthBalance,
            "should have received eth"
        );
        assertEq(address(recover).balance, 0, "should have no eth");
    }

    function testNonOwnerCannotCallSendAllEth() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(1000000000));
        recover.sendAllEth(payable(address(this)));
    }

    function testOwnerCanCallEmergencyActionAndRecoverEth(uint128 ethAmount)
        public
    {
        vm.deal(address(recover), ethAmount);
        uint256 startingEthBalance = address(this).balance;

        Recovery.Call[] memory calls = new Recovery.Call[](1);
        calls[0].target = address(this);
        calls[0].value = ethAmount;
        calls[0].callData = "";

        recover.emergencyAction(calls);

        assertEq(
            address(this).balance,
            ethAmount + startingEthBalance,
            "should have received eth"
        );
        assertEq(address(recover).balance, 0);
    }

    function testNonOwnerCannotCallEmergencyAction() public {
        Recovery.Call[] memory calls = new Recovery.Call[](1);
        calls[0].target = address(this);
        calls[0].value = 0;
        calls[0].callData = "";

        vm.prank(address(1000000000));
        vm.expectRevert("Ownable: caller is not the owner");
        recover.emergencyAction(calls);
    }

    function testSendAllEthToFailingReceiverAsOwnerFails() public {
        FailingReceiver fail = new FailingReceiver();

        vm.deal(address(recover), 1 ether);
        vm.expectRevert("Recovery: underlying call reverted");
        recover.sendAllEth(payable(address(fail)));
    }

    function testEmergencyActionEthToFailingReceiverAsOwnerFails() public {
        FailingReceiver fail = new FailingReceiver();
        vm.deal(address(recover), 1 ether);

        Recovery.Call[] memory calls = new Recovery.Call[](1);
        calls[0].target = address(fail);
        calls[0].value = 1 ether;
        calls[0].callData = "";

        vm.expectRevert("Recovery: underlying call reverted");
        recover.emergencyAction(calls);
    }

    /// to receive eth from recovery contract
    receive() external payable {}
}
