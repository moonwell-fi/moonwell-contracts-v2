// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Addresses} from "@proposals/Addresses.sol";

import {Script} from "@forge-std/Script.sol";

import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {MockERC20WithDecimals} from "../test/mock/MockERC20WithDecimals.sol";

import {String} from "../src/utils/String.sol";

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
            decimals.toUint8()
        );
        vm.stopBroadcast();

        addresses.changeAddress(symbol, address(token), true);

        addresses.printJSONChanges();
    }
}
