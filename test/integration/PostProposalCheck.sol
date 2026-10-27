// SPDX-License-Identifier: GPL-3.0-or-late
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import "@utils/ChainIds.sol";

import {etch} from "@proposals/utils/PrecompileEtching.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {String} from "@utils/String.sol";
import {Proposal} from "@proposals/Proposal.sol";
import {ProposalMap} from "@test/utils/ProposalMap.sol";
import {MarketPriceGuard} from "@test/utils/MarketPriceGuard.sol";
import {MarketStateGuard} from "@test/utils/MarketStateGuard.sol";
import {IMultichainGovernorV2} from "@protocol/governance/multichain/IMultichainGovernorV2.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract PostProposalCheck is Test {
    using String for string;
    using ChainIds for uint256;

    /// @notice addresses contract
    Addresses public addresses;

    /// @notice proposal to file map contract
    ProposalMap proposalMap;

    /// @notice array of proposals in development
    Proposal[] public proposals;

    /// @notice union of simulated proposals' expectedPriceChanges()
    address[] internal _priceChangeAllowlist;

    /// @notice union of simulated proposals' expectedMarketStateChanges()
    Proposal.MarketStateChange[] internal _marketStateChanges;

    /// @notice store the proposal start time so that tests can go back in time
    /// to this point if needed. Used in ReserveAutomationDeploy Integration Test
    uint256 public proposalStartTime;

    /// @notice snapshots every market's oracle price before the pending
    /// proposals run and fails setUp if any price moved afterwards
    MarketPriceGuard public priceGuard;

    /// @notice resolves expectedMarketStateChanges(); snapshots on demand
    MarketStateGuard public stateGuard;

    function setUp() public virtual {
        uint256 primaryForkBefore = vm.envOr("PRIMARY_FORK_ID", uint256(0));
        proposalMap = new ProposalMap();
        vm.makePersistent(address(proposalMap));

        MOONBEAM_FORK_ID.createForksAndSelect();

        proposalStartTime = block.timestamp;

        addresses = new Addresses();
        vm.makePersistent(address(addresses));

        // do not run proposals on moonbase
        if (block.chainid == MOONBASE_CHAIN_ID) {
            return;
        }

        // baseline before any not-yet-executed proposal, on-chain or in dev
        _snapshotMarketPrices();
        _beforePendingProposals();

        // Simulate MultichainGovernorV2 proposals that already carry an
        // on-chain id but have not been executed yet (e.g. MIP-E00). Runs
        // before the dev loop: a submitted proposal executes before any
        // unsubmitted one.
        simulatePendingGovernorV2Proposals();

        // execute proposals that are not on chain yet
        ProposalMap.ProposalFields[] memory devProposals = proposalMap
            .getAllProposalsInDevelopment();

        // execute in the inverse order so that the lowest id is executed first
        for (uint256 i = devProposals.length; i > 0; i--) {
            proposalMap.setEnv(devProposals[i - 1].envPath);
            Proposal proposal = proposalMap.runProposal(
                addresses,
                devProposals[i - 1].path,
                devProposals[i - 1].envPath
            );
            vm.makePersistent(address(proposal));

            proposals.push(proposal);
            _recordExpectedPriceChanges(proposal);
        }

        // Sync all fork timestamps to the maximum observed across all forks.
        // Proposal execution may warp some forks forward (e.g. Base during
        // executeLiveProposals) and then backward (e.g. Base during
        // executeTemporalGovernorQueuedProposals processing older proposals).
        // This leaves stored contract timestamps (MRD globalTimestamps,
        // MToken accrualBlockTimestamp) ahead of block.timestamp, causing
        // subtraction underflow errors in subsequent test interactions.
        {
            uint256 maxTime = proposalStartTime;
            for (uint256 i = BASE_FORK_ID; i <= ETHEREUM_FORK_ID; i++) {
                vm.selectFork(i);
                if (block.timestamp > maxTime) {
                    maxTime = block.timestamp;
                }
            }
            for (uint256 i = BASE_FORK_ID; i <= ETHEREUM_FORK_ID; i++) {
                vm.selectFork(i);
                if (block.timestamp < maxTime) {
                    vm.warp(maxTime);
                }
            }
            proposalStartTime = maxTime;
        }

        _assertMarketPricesPreserved();

        vm.selectFork(MOONBEAM_FORK_ID);

        addresses.removeAllRestrictions();

        vm.setEnv("PRIMARY_FORK_ID", vm.toString(primaryForkBefore));

        // set proposalStartTime on the active fork
        vm.warp(proposalStartTime);
    }

    /// @notice record every listed market's price on every fork before any
    /// pending proposal is simulated
    function _snapshotMarketPrices() internal {
        uint256 activeFork = vm.activeFork();

        priceGuard = new MarketPriceGuard();
        vm.makePersistent(address(priceGuard));

        stateGuard = new MarketStateGuard();
        vm.makePersistent(address(stateGuard));

        for (uint256 i = BASE_FORK_ID; i <= ETHEREUM_FORK_ID; i++) {
            priceGuard.snapshot(addresses, i);
        }

        vm.selectFork(activeFork);
    }

    /// @notice fail setUp when a simulated proposal moved a market price it
    /// did not declare in expectedPriceChanges()
    function _assertMarketPricesPreserved() internal {
        uint256 activeFork = vm.activeFork();

        address[] memory allowlist = _priceChangeAllowlist;
        uint256 total;
        string memory firstSummary;

        for (uint256 i = BASE_FORK_ID; i <= ETHEREUM_FORK_ID; i++) {
            MarketPriceGuard.Violation[] memory violations = priceGuard.check(
                addresses,
                i,
                allowlist
            );
            if (violations.length > 0) {
                string memory summary = priceGuard.describe(violations);
                if (total == 0) {
                    firstSummary = summary;
                }
                total += violations.length;
            }
        }

        vm.selectFork(activeFork);

        require(total == 0, firstSummary);
    }

    /// @notice runs after the price snapshot, before any pending proposal;
    /// suites that diff pre/post state take their snapshot here
    function _beforePendingProposals() internal virtual {}

    /// @notice resolve the declaration while the proposal's PRIMARY_FORK_ID
    /// env is still set (ProtocolDeployment reads it)
    function _recordExpectedPriceChanges(Proposal proposal) internal {
        address[] memory declared = priceGuard.declaredChanges(
            addresses,
            proposal
        );
        for (uint256 i = 0; i < declared.length; i++) {
            _priceChangeAllowlist.push(declared[i]);
        }

        Proposal.MarketStateChange[] memory changes = stateGuard
            .declaredChanges(addresses, proposal);
        for (uint256 i = 0; i < changes.length; i++) {
            _marketStateChanges.push(changes[i]);
        }
    }

    /// @notice Run the full deploy -> build -> simulate -> validate lifecycle
    /// for every MultichainGovernorV2 proposal in mips.json that carries a
    /// non-zero id but has not yet executed on-chain. These were simulated as
    /// id:0 in-development proposals until an id was assigned, so we re-apply
    /// their effects here (e.g. MIP-E00 lists and initializes the Ethereum
    /// markets). Already-executed proposals are
    /// skipped so we never re-run finalized governance.
    function simulatePendingGovernorV2Proposals() internal {
        ProposalMap.ProposalFields[] memory v2Proposals = proposalMap
            .filterByGovernor("MultichainGovernorV2");

        for (uint256 i = 0; i < v2Proposals.length; i++) {
            // id:0 entries are handled by the in-development loop above.
            if (v2Proposals[i].id == 0) {
                continue;
            }

            vm.selectFork(ETHEREUM_FORK_ID);

            if (!addresses.isAddressSet("MULTICHAIN_GOVERNOR_V2_PROXY")) {
                continue;
            }

            IMultichainGovernorV2 governorV2 = IMultichainGovernorV2(
                addresses.getAddress("MULTICHAIN_GOVERNOR_V2_PROXY")
            );

            // A proposal whose id exists but has not executed yet still needs
            // its effects applied to the fork. Defeated and Canceled proposals
            // never will, so simulating them would apply state that never
            // lands on-chain. If state() reverts the id was never created
            // on-chain — treat as pending.
            bool pending;
            try governorV2.state(v2Proposals[i].id) returns (
                IMultichainGovernorV2.ProposalState state
            ) {
                pending =
                    state != IMultichainGovernorV2.ProposalState.Executed &&
                    state != IMultichainGovernorV2.ProposalState.Defeated &&
                    state != IMultichainGovernorV2.ProposalState.Canceled;
            } catch {
                pending = true;
            }

            if (!pending) {
                continue;
            }

            proposalMap.setEnv(v2Proposals[i].envPath);
            Proposal proposal = proposalMap.runProposal(
                addresses,
                v2Proposals[i].path,
                v2Proposals[i].envPath
            );
            vm.makePersistent(address(proposal));

            proposals.push(proposal);
            _recordExpectedPriceChanges(proposal);
        }
    }
}
