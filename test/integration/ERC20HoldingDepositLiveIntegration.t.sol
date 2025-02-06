// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

import "@forge-std/Test.sol";

import {AutomationDeploy} from "@protocol/market/AutomationDeploy.sol";
import {ERC20HoldingDeposit} from "@protocol/market/ERC20HoldingDeposit.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract ERC20HoldingDepositLiveIntegrationTest is Test {
    event ERC20Withdrawn(
        address indexed tokenAddress,
        address indexed to,
        uint256 amount
    );

    ERC20 public well;
    ERC20HoldingDeposit public holder;
    Addresses private _addresses;

    function setUp() public {
        _addresses = new Addresses();
        well = ERC20(_addresses.getAddress("xWELL_PROXY"));

        AutomationDeploy deployer = new AutomationDeploy();
        holder = ERC20HoldingDeposit(
            deployer.deployERC20HoldingDeposit(
                address(well),
                _addresses.getAddress("TEMPORAL_GOVERNOR")
            )
        );
    }

    function testSetup() public view {
        assertEq(holder.token(), address(well), "incorrect token address");
        assertEq(
            holder.owner(),
            _addresses.getAddress("TEMPORAL_GOVERNOR"),
            "incorrect owner"
        );
    }

    function testBalance() public {
        assertEq(holder.balance(), 0, "initial balance should be 0");

        uint256 amount = 1000e18;
        deal(address(well), address(holder), amount);

        assertEq(
            holder.balance(),
            amount,
            "balance should match transferred amount"
        );
    }

    function testWithdrawERC20TokenRevertNonOwner() public {
        uint256 amount = 1000e18;
        deal(address(well), address(holder), amount);

        vm.expectRevert("Ownable: caller is not the owner");
        holder.withdrawERC20Token(address(well), address(this), amount);
    }

    function testWithdrawERC20TokenRevertZeroAddress() public {
        uint256 amount = 1000e18;
        deal(address(well), address(holder), amount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectRevert("ERC20HoldingDeposit: to address cannot be 0");
        holder.withdrawERC20Token(address(well), address(0), amount);
    }

    function testWithdrawERC20TokenRevertZeroAmount() public {
        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectRevert("ERC20HoldingDeposit: amount must be greater than 0");
        holder.withdrawERC20Token(address(well), address(this), 0);
    }

    function testWithdrawERC20TokenRevertInsufficientBalance() public {
        uint256 amount = 1000e18;
        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        holder.withdrawERC20Token(address(well), address(this), amount);
    }

    function testWithdrawERC20TokenSucceeds() public {
        uint256 amount = 1000e18;
        deal(address(well), address(holder), amount);

        uint256 initialBalance = well.balanceOf(address(this));

        vm.expectEmit(true, true, false, true);
        emit ERC20Withdrawn(address(well), address(this), amount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        holder.withdrawERC20Token(address(well), address(this), amount);

        assertEq(
            well.balanceOf(address(this)) - initialBalance,
            amount,
            "recipient balance did not increase correctly"
        );
        assertEq(
            well.balanceOf(address(holder)),
            0,
            "holder balance not zero after withdrawal"
        );
    }

    function testWithdrawERC20TokenPartialAmount() public {
        uint256 amount = 1000e18;
        deal(address(well), address(holder), amount);

        uint256 withdrawAmount = amount / 2;
        uint256 initialBalance = well.balanceOf(address(this));

        vm.expectEmit(true, true, false, true);
        emit ERC20Withdrawn(address(well), address(this), withdrawAmount);

        vm.prank(_addresses.getAddress("TEMPORAL_GOVERNOR"));
        holder.withdrawERC20Token(address(well), address(this), withdrawAmount);

        assertEq(
            well.balanceOf(address(this)) - initialBalance,
            withdrawAmount,
            "recipient balance did not increase correctly"
        );
        assertEq(
            well.balanceOf(address(holder)),
            withdrawAmount,
            "holder balance incorrect after partial withdrawal"
        );
    }
}
