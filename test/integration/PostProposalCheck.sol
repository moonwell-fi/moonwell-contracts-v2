// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {TestProposals} from "@proposals/TestProposals.sol";
import {mipb00 as mip} from "@proposals/mips/mip-b00/mip-b00.sol";
import {mip0x as marketDeployMip} from "@proposals/mips/examples/mip-market-listing/mip-market-listing.sol";

contract PostProposalCheck is Test {
    Addresses addresses;
    uint256 preProposalsSnapshot;
    uint256 postProposalsSnapshot;

    function setUp() public virtual {
        preProposalsSnapshot = vm.snapshot();

        // Run all pending proposals before doing e2e tests
        address[] memory mips = new address[](1);
        mips[0] = address(new mip());

        /// mips[1] = address(new marketDeployMip());

        TestProposals proposals = new TestProposals(mips);
        proposals.setUp();
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
