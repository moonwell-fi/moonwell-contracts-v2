//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ActionType, ProposalAction} from "@proposals/proposalTypes/IProposal.sol";
import {RewardsDistributionV2Template} from "@proposals/templates/RewardsDistributionV2.sol";

/// @notice test-only harness exposing the generic action-batching internals of
/// RewardsDistributionV2Template so the size-driven chunker and propose()
/// packer can be exercised with synthetic actions — no fork, no rewards JSON.
contract RewardsBatchHarness is RewardsDistributionV2Template {
    uint256 private _maxChunk;
    uint256 private _maxCall;

    function name() external pure override returns (string memory) {
        return "RewardsBatchHarness";
    }

    function setBudgets(uint256 chunkBudget, uint256 callBudget) external {
        _maxChunk = chunkBudget;
        _maxCall = callBudget;
    }

    function maxChunkPayloadBytes() public view override returns (uint256) {
        return _maxChunk;
    }

    function maxProposeCallBytes() public view override returns (uint256) {
        return _maxCall;
    }

    function pushAction(
        address target,
        bytes memory data,
        ActionType at
    ) external {
        _pushAction(target, data, at);
    }

    function markGroup(ActionType at, uint256 start, uint256 len) external {
        _markAtomicGroup(at, start, len);
    }

    function chunkPayloadSize(
        ActionType at,
        uint256 index
    ) external view returns (uint256) {
        return _chunkEncodedSize(chunkActions(at, index));
    }
}

contract RewardsDistributionV2BatchingUnitTest is Test {
    RewardsBatchHarness harness;

    /// @notice short deterministic description used by propose(); mirrors a
    /// production run where the markdown is pinned to an IPFS URI. The packer
    /// charges the init call with the ACTUAL description size, so tests pin a
    /// known-small one.
    string constant DESCRIPTION_URI = "ipfs://QmTestDescriptionUri";

    function setUp() public {
        // the template constructor reads DESCRIPTION_PATH; point it at a real
        // file (its contents are irrelevant to the batching logic)
        vm.setEnv("DESCRIPTION_PATH", "proposals/mips/mip-x59/x59.md");
        harness = new RewardsBatchHarness();
        harness.setProposalDescriptionUri(DESCRIPTION_URI);
    }

    /// @notice mirrors the template's init-call overhead: the fixed
    /// PROPOSE_CALL_OVERHEAD plus the 32-byte-padded description size
    function _initCallOverhead() internal pure returns (uint256) {
        return 512 + ((bytes(DESCRIPTION_URI).length + 31) / 32) * 32;
    }

    /// @notice push `count` Base actions each carrying `size` bytes of data
    function _pushBase(uint256 count, uint256 size) internal {
        for (uint256 i = 0; i < count; i++) {
            harness.pushAction(
                address(uint160(0x1000 + i)),
                new bytes(size),
                ActionType.Base
            );
        }
    }

    /// @notice cumulative chunk start indices reconstructed from chunkActions,
    /// so tests can reason about where the chunker cut the bundle
    function _chunkStarts(
        ActionType at
    ) internal view returns (uint256[] memory starts) {
        uint256 chunks = harness.chunkCount(at);
        starts = new uint256[](chunks);
        uint256 running = 0;
        for (uint256 c = 0; c < chunks; c++) {
            starts[c] = running;
            running += harness.chunkActions(at, c).length;
        }
    }

    /// a small bundle rides a single VAA and needs no batched submission
    function testSmallBundleSingleChunkNoSplit() public {
        harness.setBudgets(11_000, 12_000);
        _pushBase(3, 100);

        assertEq(harness.chunkCount(ActionType.Base), 1, "should be 1 chunk");
        assertEq(
            harness.batchProposeSplits().length,
            0,
            "should be a single propose call"
        );

        // the one chunk is the whole bundle, in order
        ProposalAction[] memory chunk = harness.chunkActions(
            ActionType.Base,
            0
        );
        assertEq(chunk.length, 3, "chunk should hold all actions");
    }

    /// an oversized bundle is split into multiple chunks, each within budget,
    /// and the chunks together reproduce the full bundle in order
    function testOversizedBundleSplitsWithinBudget() public {
        uint256 chunkBudget = 3_000;
        harness.setBudgets(chunkBudget, 12_000);
        _pushBase(9, 800);

        uint256 chunks = harness.chunkCount(ActionType.Base);
        assertGt(chunks, 1, "bundle should split into multiple chunks");

        ProposalAction[] memory all = harness.getActionsByType(ActionType.Base);
        uint256 seen = 0;
        for (uint256 c = 0; c < chunks; c++) {
            ProposalAction[] memory chunk = harness.chunkActions(
                ActionType.Base,
                c
            );
            // every chunk fits the budget unless it is a single indivisible unit
            if (chunk.length > 1) {
                assertLe(
                    harness.chunkPayloadSize(ActionType.Base, c),
                    chunkBudget,
                    "multi-action chunk exceeds budget"
                );
            }
            // chunks are contiguous and ordered
            for (uint256 i = 0; i < chunk.length; i++) {
                assertEq(
                    chunk[i].target,
                    all[seen].target,
                    "chunk action out of order"
                );
                seen++;
            }
        }
        assertEq(
            seen,
            all.length,
            "chunks must cover every action exactly once"
        );
    }

    /// a dependent action group is never split across two chunks even when the
    /// size budget would otherwise cut inside it
    function testAtomicGroupNeverSplit() public {
        // one action per chunk by budget, so without protection the chunker
        // would cut at every boundary (including inside the group)
        harness.setBudgets(1, 12_000);
        _pushBase(6, 200);

        // mark actions [2,3] as one atomic group (interior boundary = 3)
        harness.markGroup(ActionType.Base, 2, 2);

        uint256[] memory starts = _chunkStarts(ActionType.Base);
        for (uint256 i = 0; i < starts.length; i++) {
            assertTrue(starts[i] != 3, "chunker cut inside an atomic group");
        }

        // actions 2 and 3 must land in the same chunk
        uint256 chunks = harness.chunkCount(ActionType.Base);
        bool foundPair = false;
        uint256 running = 0;
        for (uint256 c = 0; c < chunks; c++) {
            uint256 len = harness.chunkActions(ActionType.Base, c).length;
            if (running <= 2 && 3 < running + len) {
                foundPair = true;
            }
            running += len;
        }
        assertTrue(foundPair, "atomic pair split across chunks");
    }

    /// the proposal is packed into successive propose() calls, each within the
    /// call budget, with strictly increasing in-range split points
    function testBatchProposeSplitsPacksWithinCallBudget() public {
        uint256 callBudget = 6_000;
        // keep each chunk small enough to fit a call, then force several calls
        harness.setBudgets(2_000, callBudget);
        _pushBase(12, 700);

        uint256[] memory splits = harness.batchProposeSplits();
        assertGt(
            splits.length,
            0,
            "large proposal should batch its submission"
        );

        uint256 total = harness.allActionTypesCount();
        for (uint256 i = 0; i < splits.length; i++) {
            assertGt(splits[i], 0, "split index must be > 0");
            assertLt(splits[i], total, "split index must be < action count");
            if (i > 0) {
                assertGt(
                    splits[i],
                    splits[i - 1],
                    "splits must be strictly increasing"
                );
            }
        }

        // reconstruct the per-call byte size and assert each call fits the
        // budget (mirrors getTargetsPayloadsValues ordering: no Ethereum
        // actions here, so it is just the Base chunks)
        uint256 chunks = harness.chunkCount(ActionType.Base);
        uint256[] memory lens = new uint256[](chunks);
        for (uint256 c = 0; c < chunks; c++) {
            lens[c] = harness.chunkPayloadSize(ActionType.Base, c);
        }

        uint256 splitCursor = 0;
        // init call carries the description; append calls do not
        uint256 acc = _initCallOverhead();
        for (uint256 i = 0; i < chunks; i++) {
            if (splitCursor < splits.length && i == splits[splitCursor]) {
                acc = 512; // PROPOSE_CALL_OVERHEAD
                splitCursor++;
            }
            acc += 128 + ((lens[i] + 31) / 32) * 32;
            assertLe(acc, callBudget, "a propose() call exceeds the budget");
        }
    }

    /// the init call is charged with the ACTUAL description size: a large
    /// unpinned markdown description forces the first split earlier than the
    /// same actions with a short pinned URI
    function testInitCallAccountsForDescription() public {
        uint256 callBudget = 6_000;
        harness.setBudgets(2_000, callBudget);
        _pushBase(6, 700);

        // short URI (set in setUp): several chunks fit in the init call
        uint256[] memory shortSplits = harness.batchProposeSplits();

        // simulate an unpinned raw markdown description close to the budget:
        // the init call can now fit fewer (here: one) governor actions
        harness.setProposalDescriptionUri(string(new bytes(4_500)));
        uint256[] memory longSplits = harness.batchProposeSplits();

        assertGt(
            longSplits.length,
            shortSplits.length,
            "large description must force more propose() calls"
        );
        assertEq(
            longSplits[0],
            1,
            "init call with near-budget description fits only one action"
        );
    }
}
