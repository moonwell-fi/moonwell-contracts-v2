// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// @notice Minimal concrete HybridProposal used only to exercise how the
/// proposal resolves the description argument for propose(). Both getCalldata()
/// (printed calldata) and the in-simulation propose() use _proposeDescription().
contract DescUriHarness is HybridProposal {
    function name() external pure override returns (string memory) {
        return "TEST-DESC-URI-V1";
    }

    function primaryForkId() public pure override returns (uint256) {
        return 0;
    }

    function validate(Addresses, address) public override {}

    function setMarkdown(string memory md) external {
        _setProposalDescription(bytes(md));
    }

    function proposeDescription() external view returns (string memory) {
        return _proposeDescription();
    }
}

contract HybridProposalDescriptionUriTest is Test {
    DescUriHarness internal harness;

    function setUp() public {
        harness = new DescUriHarness();
        harness.setMarkdown("# Full markdown body");
    }

    function test_defaultsToMarkdownWhenNoUri() public {
        assertEq(harness.proposeDescription(), "# Full markdown body");
    }

    function test_usesIpfsUriWhenSet() public {
        harness.setProposalDescriptionUri("ipfs://bafytest");
        assertEq(harness.proposeDescription(), "ipfs://bafytest");
    }

    function test_emptyUriFallsBackToMarkdown() public {
        harness.setProposalDescriptionUri("");
        assertEq(harness.proposeDescription(), "# Full markdown body");
    }
}
