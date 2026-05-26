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

    function test_descriptionUriAbsentByDefault() public {
        // no entry currently carries descriptionUri => empty string
        assertEq(
            map.getProposalDescriptionUri(
                "artifacts/foundry/mip-e00.sol/mipe00.json"
            ),
            ""
        );
    }
}
