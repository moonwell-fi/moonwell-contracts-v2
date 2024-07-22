//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MockERC20Params} from "@test/mock/MockERC20Params.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

function etchPrecompile(
    Vm vm,
    Addresses addresses,
    string memory mockName,
    string memory symbol
) {
    MockERC20Params mock = new MockERC20Params(mockName, symbol);
    address mockAddress = address(mock);
    uint256 codeSize;
    assembly {
        codeSize := extcodesize(mockAddress)
    }

    bytes memory runtimeBytecode = new bytes(codeSize);

    assembly {
        extcodecopy(mockAddress, add(runtimeBytecode, 0x20), 0, codeSize)
    }

    vm.etch(addresses.getAddress(symbol), runtimeBytecode);

    MockERC20Params(addresses.getAddress(symbol)).setSymbol(symbol);

    MockERC20Params(addresses.getAddress(symbol)).symbol();
}

function etch(Vm vm, Addresses addresses) {
    etchPrecompile(vm, addresses, "Mock xcUSDT", "xcUSDT");
    etchPrecompile(vm, addresses, "USD Coin", "xcUSDC");
    etchPrecompile(vm, addresses, "Mock xcDOT", "xcDOT");
}
