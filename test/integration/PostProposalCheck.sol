// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";

import {Addresses} from "@test/proposals/Addresses.sol";
import {mip00 as mip} from "@test/proposals/mips/mip00.sol";
import {TestProposals} from "@test/proposals/TestProposals.sol";

contract PostProposalCheck is Test {
    Addresses addresses;
    uint256 preProposalsSnapshot;
    uint256 postProposalsSnapshot;

    function setUp() public virtual {
        preProposalsSnapshot = vm.snapshot();

        // Run all pending proposals before doing e2e tests
        address[] memory mips = new address[](1);
        mips[0] = address(new mip());

        TestProposals proposals = new TestProposals(mips);
        proposals.setUp();
        proposals.setDebug(false);
        proposals.testProposals(
            true,
            true,
            true,
            true,
            true,
            true,
            false,
            true
        );
        addresses = proposals.addresses();

        postProposalsSnapshot = vm.snapshot();
    }
}
