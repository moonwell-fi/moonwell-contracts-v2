// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {Test} from "@forge-std/Test.sol";
import {console} from "@forge-std/console.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title AddReserves
/// @notice Generic script to donate tokens to any Moonwell market
/// @dev Usage: forge script script/AddReserves.s.sol:AddReserves \
///             --sig "run(string,uint256,uint256)" "MOONWELL_cbXRP" 464276470778 8453
contract AddReserves is Script, Test {
    /// @notice Addresses contract
    Addresses public addresses;

    /// @notice Underlying token
    IERC20Metadata public underlyingToken;

    /// @notice Moonwell market (mToken)
    MErc20 public mToken;

    constructor() {
        addresses = new Addresses();
    }

    /// @notice Run the script to add reserves to a Moonwell market
    /// @param mTokenName The mToken name in addresses registry (e.g., "MOONWELL_cbXRP")
    /// @param amount The amount of underlying tokens to donate (in smallest unit)
    /// @param chainId The chain ID (e.g., 8453 for Base, 10 for Optimism)
    function run(
        string calldata mTokenName,
        uint256 amount,
        uint256 chainId
    ) public {
        // Load addresses
        mToken = MErc20(addresses.getAddress(mTokenName, chainId));
        underlyingToken = IERC20Metadata(mToken.underlying());

        string memory tokenSymbol = underlyingToken.symbol();
        uint8 decimals = underlyingToken.decimals();

        console.log("\n=== Add Reserves Configuration ===");
        console.log("Chain ID:", chainId);
        console.log("mToken:", mTokenName);
        console.log("mToken address:", address(mToken));
        console.log("Underlying token:", tokenSymbol);
        console.log("Underlying address:", address(underlyingToken));
        console.log("Decimals:", decimals);
        console.log("Amount (wei):", amount);
        console.log(
            "Amount (human):",
            amount / (10 ** decimals),
            ".",
            amount % (10 ** decimals)
        );

        // Capture state before
        uint256 reservesBefore = mToken.totalReserves();
        uint256 senderBalanceBefore = underlyingToken.balanceOf(msg.sender);

        console.log("\n--- Before ---");
        console.log("Total reserves:", reservesBefore);
        console.log("Sender balance:", senderBalanceBefore);

        require(senderBalanceBefore >= amount, "Insufficient token balance");

        vm.startBroadcast();

        // Approve mToken to spend underlying
        underlyingToken.approve(address(mToken), amount);

        // Add reserves (donation)
        uint256 result = mToken._addReserves(amount);
        require(result == 0, "Failed to add reserves");

        vm.stopBroadcast();

        // Validate
        validate(reservesBefore, senderBalanceBefore, amount);
    }

    /// @notice Validates that reserves were correctly added
    /// @param reservesBefore Total reserves before the operation
    /// @param senderBalanceBefore Sender's token balance before the operation
    /// @param amount The amount that was donated
    function validate(
        uint256 reservesBefore,
        uint256 senderBalanceBefore,
        uint256 amount
    ) public view {
        uint256 reservesAfter = mToken.totalReserves();
        uint256 senderBalanceAfter = underlyingToken.balanceOf(msg.sender);

        console.log("\n--- After ---");
        console.log("Total reserves:", reservesAfter);
        console.log("Sender balance:", senderBalanceAfter);

        // Verify reserves increased by at least amount
        // (may be slightly more due to interest accrual between before/after snapshots)
        assertGe(
            reservesAfter,
            reservesBefore + amount,
            "Reserves did not increase by at least the expected amount"
        );

        // Verify sender's balance decreased by amount
        assertEq(
            senderBalanceAfter,
            senderBalanceBefore - amount,
            "Sender balance did not decrease by expected amount"
        );

        uint256 reservesIncrease = reservesAfter - reservesBefore;

        console.log("\n=== Validation Passed ===");
        console.log("Reserves increased by:", reservesIncrease);
        console.log("Amount donated:", amount);
    }
}
