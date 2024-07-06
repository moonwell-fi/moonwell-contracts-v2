//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MockERC20Params} from "@test/mock/MockERC20Params.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

function etch(Vm vm, Addresses addresses) {
    {
        MockERC20Params mockUSDT = new MockERC20Params("Mock xcUSDT", "xcUSDT");
        address mockUSDTAddress = address(mockUSDT);
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(mockUSDTAddress)
        }

        bytes memory runtimeBytecode = new bytes(codeSize);

        assembly {
            extcodecopy(
                mockUSDTAddress,
                add(runtimeBytecode, 0x20),
                0,
                codeSize
            )
        }

        vm.etch(addresses.getAddress("xcUSDT"), runtimeBytecode);

        MockERC20Params(addresses.getAddress("xcUSDT")).setSymbol("xcUSDT");

        MockERC20Params(addresses.getAddress("xcUSDT")).symbol();
    }

    {
        MockERC20Params mockUSDC = new MockERC20Params("USD Coin", "xcUSDC");
        address mockUSDCAddress = address(mockUSDC);
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(mockUSDCAddress)
        }

        bytes memory runtimeBytecode = new bytes(codeSize);

        assembly {
            extcodecopy(
                mockUSDCAddress,
                add(runtimeBytecode, 0x20),
                0,
                codeSize
            )
        }

        vm.etch(addresses.getAddress("xcUSDC"), runtimeBytecode);

        MockERC20Params(addresses.getAddress("xcUSDC")).setSymbol("xcUSDC");

        MockERC20Params(addresses.getAddress("xcUSDC")).symbol();
    }

    {
        MockERC20Params mockDot = new MockERC20Params("Mock xcDOT", "xcDOT");
        address mockDotAddress = address(mockDot);
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(mockDotAddress)
        }

        bytes memory runtimeBytecode = new bytes(codeSize);

        assembly {
            extcodecopy(mockDotAddress, add(runtimeBytecode, 0x20), 0, codeSize)
        }

        vm.etch(addresses.getAddress("xcDOT"), runtimeBytecode);
        MockERC20Params(addresses.getAddress("xcDOT")).setSymbol("xcDOT");

        MockERC20Params(addresses.getAddress("xcDOT")).symbol();
    }
}
