// SPDX-License-Identifier: GPL-3.0-or-late
pragma solidity 0.8.19;

import "@utils/ChainIds.sol";

import {etch} from "@proposals/utils/PrecompileEtching.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {String} from "@utils/String.sol";
import {Proposal} from "@proposals/Proposal.sol";
import {ProposalMap} from "@test/utils/ProposalMap.sol";
import {LiveProposalCheck} from "@test/utils/LiveProposalCheck.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {IMultichainGovernorV2} from "@protocol/governance/multichain/IMultichainGovernorV2.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract PostProposalCheck is LiveProposalCheck {
    using String for string;
    using ChainIds for uint256;

    /// @notice addresses contract
    Addresses public addresses;

    /// @notice governor address
    MultichainGovernor governor;

    /// @notice array of proposals in development
    Proposal[] public proposals;

    /// @notice store the proposal start time so that tests can go back in time
    /// to this point if needed. Used in ReserveAutomationDeploy Integration Test
    uint256 public proposalStartTime;

    function setUp() public virtual override {
        uint256 primaryForkBefore = vm.envOr("PRIMARY_FORK_ID", uint256(0));
        super.setUp();

        MOONBEAM_FORK_ID.createForksAndSelect();

        proposalStartTime = block.timestamp;

        addresses = new Addresses();
        vm.makePersistent(address(addresses));

        // do not run proposals on moonbase
        if (block.chainid == MOONBASE_CHAIN_ID) {
            return;
        }

        governor = MultichainGovernor(
            payable(addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"))
        );

        // execute proposals that are succeeded but not executed yet
        executeSucceededProposals(addresses, governor);

        // reset the block timestamp in case executeSucceededProposals moved it forward
        vm.warp(proposalStartTime);

        // execute proposals that are in the vote or vote collection period
        executeLiveProposals(addresses, governor);

        // update proposalStartTime to account for time warps during live
        // proposal execution. Contracts like the safety module store
        // lastUpdateTimestamp, so we cannot warp backward past that point.
        proposalStartTime = block.timestamp;

        // execute proposals that are queued in the temporal governor but not executed yet
        executeTemporalGovernorQueuedProposals(addresses, governor);

        // execute proposals that are not on chain yet
        ProposalMap.ProposalFields[] memory devProposals = proposalMap
            .getAllProposalsInDevelopment();

        // execute in the inverse order so that the lowest id is executed first
        for (uint256 i = devProposals.length; i > 0; i--) {
            proposalMap.setEnv(devProposals[i - 1].envPath);
            Proposal proposal = proposalMap.runProposal(
                addresses,
                devProposals[i - 1].path
            );
            vm.makePersistent(address(proposal));

            proposals.push(proposal);
        }

        // Simulate MultichainGovernorV2 proposals that already carry an
        // on-chain id but have not been executed yet (e.g. MIP-E00). The legacy
        // executeSucceededProposals / executeLiveProposals paths only drive the
        // original Moonbeam MultichainGovernor, so a pending V2 proposal would
        // otherwise never apply its effects to the fork.
        simulatePendingGovernorV2Proposals();

        // Sync all fork timestamps to the maximum observed across all forks.
        // Proposal execution may warp some forks forward (e.g. Base during
        // executeLiveProposals) and then backward (e.g. Base during
        // executeTemporalGovernorQueuedProposals processing older proposals).
        // This leaves stored contract timestamps (MRD globalTimestamps,
        // MToken accrualBlockTimestamp) ahead of block.timestamp, causing
        // subtraction underflow errors in subsequent test interactions.
        {
            uint256 maxTime = proposalStartTime;
            for (uint256 i = MOONBEAM_FORK_ID; i <= ETHEREUM_FORK_ID; i++) {
                vm.selectFork(i);
                if (block.timestamp > maxTime) {
                    maxTime = block.timestamp;
                }
            }
            for (uint256 i = MOONBEAM_FORK_ID; i <= ETHEREUM_FORK_ID; i++) {
                vm.selectFork(i);
                if (block.timestamp < maxTime) {
                    vm.warp(maxTime);
                }
            }
            proposalStartTime = maxTime;
        }

        vm.selectFork(MOONBEAM_FORK_ID);

        addresses.removeAllRestrictions();

        vm.setEnv("PRIMARY_FORK_ID", vm.toString(primaryForkBefore));

        // set proposalStartTime on the active (Moonbeam) fork
        vm.warp(proposalStartTime);
    }

    /// @notice Run the full deploy -> build -> simulate -> validate lifecycle
    /// for every MultichainGovernorV2 proposal in mips.json that carries a
    /// non-zero id but has not yet executed on-chain. These were simulated as
    /// id:0 in-development proposals until an id was assigned; once submitted to
    /// MultichainGovernorV2 they fall outside the legacy Moonbeam-governor
    /// execution paths, so we re-apply their effects here (e.g. MIP-E00 lists
    /// and initializes the Ethereum markets). Already-executed proposals are
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

            // A proposal whose id exists but whose state is anything other than
            // Executed still needs its effects applied to the fork. If state()
            // reverts the id was never created on-chain — also treat as pending.
            bool pending;
            try governorV2.state(v2Proposals[i].id) returns (
                IMultichainGovernorV2.ProposalState state
            ) {
                pending = state != IMultichainGovernorV2.ProposalState.Executed;
            } catch {
                pending = true;
            }

            if (!pending) {
                continue;
            }

            proposalMap.setEnv(v2Proposals[i].envPath);
            Proposal proposal = proposalMap.runProposal(
                addresses,
                v2Proposals[i].path
            );
            vm.makePersistent(address(proposal));

            proposals.push(proposal);
        }
    }
}
