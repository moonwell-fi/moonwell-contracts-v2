// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {CreateCode} from "@proposals/utils/CreateCode.sol";
import {String} from "@utils/String.sol";
import {TestProposals} from "@proposals/TestProposals.sol";

contract PostProposalCheck is CreateCode {
    using String for string;

    Addresses addresses;
    TestProposals proposals;

    function setUp() public virtual {
        string memory path = getPath();
        // Run all pending proposals before doing e2e tests
        address[] memory mips = new address[](1);

        if (
            keccak256(bytes(path)) == keccak256('""') || bytes(path).length == 0
        ) {
            /// empty string on both mac and unix, no proposals to run
            mips = new address[](0);

            proposals = new TestProposals(mips);
        } else if (path.hasChar(",")) {
            string[] memory mipPaths = path.split(",");
            if (mipPaths.length < 2) {
                revert(
                    "Invalid path(s) provided. If you want to deploy a single mip, do not use a comma."
                );
            }
            mips = new address[](mipPaths.length); /// expand mips size if multiple mips

            /// guzzle all of the memory, quadratic cost, but we don't care
            for (uint256 i = 0; i < mipPaths.length; i++) {
                /// deploy each mip and add it to the array
                bytes memory code = getCode(mipPaths[i]);

                mips[i] = deployCode(code);
                vm.makePersistent(mips[i]);
            }
            proposals = new TestProposals(mips);
        } else {
            bytes memory code = getCode(path);
            mips[0] = deployCode(code);
            vm.makePersistent(mips[0]);
            proposals = new TestProposals(mips);
        }

        vm.makePersistent(address(proposals));

        proposals.setUp();
        proposals.testProposals(
            false, /// do not log debug output
            true,
            true,
            true,
            true,
            true,
            true,
            true
        );

        addresses = proposals.addresses();

        /// only etch out precompile contracts if on the moonbeam chain
        if (addresses.isAddressSet("xcUSDT")) {
            MockERC20Params mockUSDT = new MockERC20Params(
                "Mock xcUSDT",
                "xcUSDT"
            );
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
        }

        if (addresses.isAddressSet("xcUSDC")) {
            MockERC20Params mockUSDC = new MockERC20Params(
                "USD Coin",
                "xcUSDC"
            );
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
        }

        if (addresses.isAddressSet("xcDOT")) {
            MockERC20Params mockDot = new MockERC20Params(
                "Mock xcDOT",
                "xcDOT"
            );
            address mockDotAddress = address(mockDot);
            uint256 codeSize;
            assembly {
                codeSize := extcodesize(mockDotAddress)
            }

            bytes memory runtimeBytecode = new bytes(codeSize);

            assembly {
                extcodecopy(
                    mockDotAddress,
                    add(runtimeBytecode, 0x20),
                    0,
                    codeSize
                )
            }

            vm.etch(addresses.getAddress("xcDOT"), runtimeBytecode);
            MockERC20Params(addresses.getAddress("xcDOT")).setSymbol("xcDOT");
        }
    }
}
