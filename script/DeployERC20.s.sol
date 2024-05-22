// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Addresses} from "@proposals/Addresses.sol";

import {Script} from "@forge-std/Script.sol";

import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {MockERC20WithDecimals} from "../test/mock/MockERC20WithDecimals.sol";

// forge script script/DeployERC20.s.sol --rpc-url baseSepolia --broadcast
// --verify --sender ${SENDER_WALLET} --account ${WALLET}
contract DeployERC20 is Script {
    function run() public {
        Addresses addresses = new Addresses();

        string memory name = vm.prompt("Enter the token name");
        string memory symbol = vm.prompt("Enter the token symbol");
        string memory decimals = vm.prompt("Enter the token decimals");

        vm.startBroadcast();
        MockERC20WithDecimals token = new MockERC20WithDecimals(
            name,
            symbol,
            stringToUint8(decimals)
        );
        vm.stopBroadcast();

        addresses.changeAddress(symbol, address(token), true);

        addresses.printJSONChanges();
    }

    function stringToUint8(string memory str) public pure returns (uint8) {
        bytes memory b = bytes(str);
        uint result = 0;
        for (uint i = 0; i < b.length; i++) {
            if (b[i] >= 0x30 && b[i] <= 0x39) {
                // ensure it's a numeric character (0-9)
                result = result * 10 + (uint8(b[i]) - 48); // ASCII value for '0' is 48
            } else {
                revert("Non-numeric character.");
            }
        }
        require(result <= 255, "Value does not fit in uint8.");
        return uint8(result);
    }
}
