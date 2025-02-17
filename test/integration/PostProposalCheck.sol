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

        // execute proposals that are in the vote or vote collection period
        executeLiveProposals(addresses, governor);

        // execute proposals that are queued in the temporal governor but not executed yet
        executeTemporalGovernorQueuedProposals(addresses, governor);

        // execute proposals that are not on chain yet
        ProposalMap.ProposalFields[] memory devProposals = proposalMap
            .getAllProposalsInDevelopment();

        if (devProposals.length == 0) {
            return;
        }

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

        if (vm.activeFork() != MOONBEAM_FORK_ID) {
            vm.selectFork(MOONBEAM_FORK_ID);
        }

        addresses.removeAllRestrictions();

        vm.setEnv("PRIMARY_FORK_ID", vm.toString(primaryForkBefore));
    }
}
