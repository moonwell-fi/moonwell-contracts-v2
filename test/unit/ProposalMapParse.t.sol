// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ProposalMap} from "@test/utils/ProposalMap.sol";

/// @notice Characterization test for ProposalMap's per-element mips.json parse.
/// It must read the real registry identically to the prior bulk abi.decode and
/// expose the optional `descriptionUri` without disturbing entries that lack it.
contract ProposalMapParseTest is Test {
    ProposalMap internal map;

    function setUp() public {
        map = new ProposalMap();
    }

    function test_parsesKnownMultichainProposalById() public {
        (string memory path, string memory envPath) = map.getProposalById(167);
        assertEq(
            path,
            "artifacts/foundry/mip-x57.sol/mipx57.json",
            "mip-x57 path"
        );
        assertEq(envPath, "proposals/mips/mip-x57/x57.sh", "mip-x57 envPath");
    }

    function test_inDevelopmentIncludesMipE00() public {
        ProposalMap.ProposalFields[] memory dev = map
            .getAllProposalsInDevelopment();

        bool sawE00;
        for (uint256 i = 0; i < dev.length; i++) {
            if (
                keccak256(bytes(dev[i].path)) ==
                keccak256(bytes("artifacts/foundry/mip-e00.sol/mipe00.json"))
            ) {
                sawE00 = true;
                assertEq(dev[i].id, 0, "mip-e00 id");
                assertEq(dev[i].governor, "MultichainGovernorV2", "governor");
                assertEq(dev[i].proposalType, "HybridProposalV2", "ptype");
                assertEq(bytes(dev[i].envPath).length, 0, "mip-e00 envPath");
            }
        }
        assertTrue(sawE00, "mip-e00 should be in development");
    }

    function test_descriptionUriPresentForMipE00() public {
        // MIP-E00 is pinned to IPFS by the pin-proposal-description workflow,
        // so its mips.json entry must carry a non-empty ipfs:// descriptionUri.
        // Assert the durable invariant (prefix + non-empty), not the literal
        // CID, which changes each time the description is re-pinned.
        string memory uri = map.getProposalDescriptionUri(
            "artifacts/foundry/mip-e00.sol/mipe00.json"
        );
        bytes memory uriBytes = bytes(uri);
        assertGt(uriBytes.length, 7, "mip-e00 descriptionUri is empty");
        assertEq(uriBytes[0], bytes1("i"), "mip-e00 descriptionUri prefix [0]");
        assertEq(uriBytes[1], bytes1("p"), "mip-e00 descriptionUri prefix [1]");
        assertEq(uriBytes[2], bytes1("f"), "mip-e00 descriptionUri prefix [2]");
        assertEq(uriBytes[3], bytes1("s"), "mip-e00 descriptionUri prefix [3]");
        assertEq(uriBytes[4], bytes1(":"), "mip-e00 descriptionUri prefix [4]");
        assertEq(uriBytes[5], bytes1("/"), "mip-e00 descriptionUri prefix [5]");
        assertEq(uriBytes[6], bytes1("/"), "mip-e00 descriptionUri prefix [6]");
    }
}
