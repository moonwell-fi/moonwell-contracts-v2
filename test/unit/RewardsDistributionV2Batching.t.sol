//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ActionType, ProposalAction} from "@proposals/proposalTypes/IProposal.sol";
import {RewardsDistributionV2Template} from "@proposals/templates/RewardsDistributionV2.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// @notice minimal Addresses stand-in for fork-less tests: the real registry
/// validates isContract on load, which cannot hold without a fork. Only the
/// two entrypoints _buildWithdrawWellActions consumes are implemented.
contract FakeAddresses {
    mapping(bytes32 => address) private addrs;

    function set(string memory name, address a) external {
        addrs[keccak256(bytes(name))] = a;
    }

    function getAddress(string memory name) external view returns (address) {
        address a = addrs[keccak256(bytes(name))];
        require(a != address(0), "FakeAddresses: not set");
        return a;
    }

    function isAddressSet(string memory name) external view returns (bool) {
        return addrs[keccak256(bytes(name))] != address(0);
    }
}

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

    /// @notice real-path entrypoints for the TG-WELL span protection: the
    /// same _buildWithdrawWellActions / _markTgWellSpan flow a rewards build
    /// runs, so tests exercise the production span marking rather than a
    /// synthetic markGroup
    function buildWithdrawWell(
        Addresses addresses,
        uint256 chainId,
        WithdrawWell[] memory ws,
        string memory tokenName
    ) external {
        _buildWithdrawWellActions(addresses, chainId, ws, tokenName);
    }

    function markTgSpan(uint256 chainId) external {
        _markTgWellSpan(chainId);
    }

    /// @notice encoded VAA-payload size of a synthetic bundle of `count`
    /// actions carrying `size` data bytes each — lets tests derive exact
    /// budgets instead of hardcoding byte counts
    function measureEncodedSize(
        uint256 count,
        uint256 size
    ) external view returns (uint256) {
        ProposalAction[] memory a = new ProposalAction[](count);
        for (uint256 i = 0; i < count; i++) {
            a[i] = ProposalAction({
                target: address(1),
                value: 0,
                data: new bytes(size),
                description: "",
                actionType: ActionType.Base
            });
        }
        return _chunkEncodedSize(a);
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
        // the template constructor reads DESCRIPTION_PATH; point it at a
        // tiny test-owned fixture (its contents are irrelevant here)
        vm.setEnv(
            "DESCRIPTION_PATH",
            "test/unit/fixtures/rewards-description.md"
        );
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
            // every chunk fits the budget (over-budget indivisible units
            // revert inside the chunker instead of being emitted)
            assertLe(
                harness.chunkPayloadSize(ActionType.Base, c),
                chunkBudget,
                "chunk exceeds budget"
            );
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
        // budget of exactly three actions: the unprotected greedy chunker
        // would partition [0,1,2][3,4,5], cutting straight through the group
        harness.setBudgets(harness.measureEncodedSize(3, 200), 12_000);
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

    /// an atomic region that cannot fit any chunk fails loudly instead of
    /// being silently emitted as an over-budget chunk
    function testOversizedAtomicRegionReverts() public {
        // budget fits one action but not two
        uint256 single = harness.measureEncodedSize(1, 200);
        uint256 pair = harness.measureEncodedSize(2, 200);
        harness.setBudgets((single + pair) / 2, 12_000);
        _pushBase(4, 200);

        // actions [1,2] are one atomic group larger than the chunk budget
        harness.markGroup(ActionType.Base, 1, 2);

        vm.expectRevert(
            "RewardsDistribution: atomic action region exceeds maxChunkPayloadBytes"
        );
        harness.chunkCount(ActionType.Base);
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

    /// @notice run the REAL TG-WELL span flow (_buildWithdrawWellActions +
    /// _markTgWellSpan): pre-span actions, a withdrawWell(to = TG), then
    /// post-span actions
    function _buildTgSpanBundle() internal {
        FakeAddresses fake = new FakeAddresses();
        fake.set("TEMPORAL_GOVERNOR", address(0xAA01));
        fake.set("RESERVE_WELL_HOLDING_DEPOSIT", address(0xAA02));
        fake.set("xWELL_PROXY", address(0xAA03));

        // pre-span region (models transferFrom / reward-speed actions)
        _pushBase(2, 300);

        RewardsDistributionV2Template.WithdrawWell[]
            memory ws = new RewardsDistributionV2Template.WithdrawWell[](1);
        ws[0] = RewardsDistributionV2Template.WithdrawWell({
            amount: 1e18,
            to: "TEMPORAL_GOVERNOR"
        });
        harness.buildWithdrawWell(
            Addresses(address(fake)),
            8453,
            ws,
            "xWELL_PROXY"
        );

        // post-span region (models multiRewarder / merkle actions)
        _pushBase(3, 300);

        harness.markTgSpan(8453);
    }

    /// the production span marking keeps everything from the TG-bound
    /// withdrawal to the end of the bundle inside one chunk
    function testTgWellSpanMarkedOnRealBuildPath() public {
        // budget fits the 4-action span but not the whole 6-action bundle,
        // so the chunker must cut — and may only cut before the span
        harness.setBudgets(harness.measureEncodedSize(5, 300), 12_000);
        _buildTgSpanBundle();

        uint256[] memory starts = _chunkStarts(ActionType.Base);
        assertGt(starts.length, 1, "bundle should split");
        for (uint256 i = 0; i < starts.length; i++) {
            assertTrue(starts[i] <= 2, "chunker cut inside the TG-WELL span");
        }
    }

    /// a TG-WELL span larger than any chunk fails loudly through the real
    /// build path instead of shipping an unordered cross-chunk WELL flow
    function testTgWellSpanOversizedReverts() public {
        // budget fits two actions; the 4-action span can never fit
        harness.setBudgets(harness.measureEncodedSize(2, 300), 12_000);
        _buildTgSpanBundle();

        vm.expectRevert(
            "RewardsDistribution: atomic action region exceeds maxChunkPayloadBytes"
        );
        harness.chunkCount(ActionType.Base);
    }
}
