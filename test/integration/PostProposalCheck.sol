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
        vm.makePersistent(address(addresses));
    }
}
