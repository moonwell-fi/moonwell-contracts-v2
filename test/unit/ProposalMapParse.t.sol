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

    /// @notice `id: 0` is the in-development sentinel. Which MIP currently
    ///         holds it changes every release — mip-e00 held it until it
    ///         executed as proposal 169 — so this pins the filter's contract
    ///         instead of any one proposal: the returned set is exactly the
    ///         `id == 0` entries of mips.json, fully populated.
    function test_inDevelopmentReturnsExactlyTheSentinelEntries() public {
        ProposalMap.ProposalFields[] memory dev = map
            .getAllProposalsInDevelopment();

        for (uint256 i = 0; i < dev.length; i++) {
            assertEq(dev[i].id, 0, "non-sentinel entry in development set");
            assertGt(bytes(dev[i].path).length, 0, "development entry path");
            assertGt(
                bytes(dev[i].governor).length,
                0,
                "development entry governor"
            );
            assertGt(
                bytes(dev[i].proposalType).length,
                0,
                "development entry proposalType"
            );
        }

        assertEq(
            dev.length,
            _countSentinelEntries(),
            "development set size != count of id:0 entries in mips.json"
        );
    }

    /// @notice count `id: 0` entries by walking the registry through the
    ///         public by-index getter, independent of the filter under test.
    function _countSentinelEntries() internal view returns (uint256 count) {
        for (uint256 i = 0; ; i++) {
            try map.proposals(i) returns (
                string memory,
                string memory,
                uint256 id,
                string memory,
                string memory
            ) {
                if (id == 0) {
                    count++;
                }
            } catch {
                return count;
            }
        }
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
