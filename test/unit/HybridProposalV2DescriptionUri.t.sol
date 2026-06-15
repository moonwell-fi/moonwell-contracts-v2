// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {HybridProposalV2} from "@proposals/proposalTypes/HybridProposalV2.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// @notice Minimal concrete HybridProposalV2 used only to exercise how the
/// proposal resolves the `descriptionUri` argument for propose().
contract DescUriHarness is HybridProposalV2 {
    function name() external pure override returns (string memory) {
        return "TEST-DESC-URI";
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

contract HybridProposalV2DescriptionUriTest is Test {
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

    /// @notice a pinned URI is a valid description even with empty raw markdown
    /// (getCalldata()'s guard checks _proposeDescription(), not PROPOSAL_DESCRIPTION)
    function test_uriOnlyWithoutMarkdown() public {
        harness.setMarkdown("");
        harness.setProposalDescriptionUri("ipfs://bafytest");
        assertEq(harness.proposeDescription(), "ipfs://bafytest");
    }
}

/// @notice Minimal concrete HybridProposal (V1) used to exercise how the V1
/// proposal resolves the description argument for propose(). Both getCalldata()
/// (printed calldata) and the in-simulation propose() use _proposeDescription().
contract DescUriHarnessV1 is HybridProposal {
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
    DescUriHarnessV1 internal harness;

    function setUp() public {
        harness = new DescUriHarnessV1();
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
