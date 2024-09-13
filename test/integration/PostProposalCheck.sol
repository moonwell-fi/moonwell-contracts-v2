// SPDX-License-Identifier: GPL-3.0-or-late
pragma solidity 0.8.19;
import {console} from "forge-std/console.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {String} from "@utils/String.sol";
import {Proposal} from "@proposals/Proposal.sol";
import {MOONBEAM_FORK_ID, ChainIds} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {etch} from "@proposals/utils/PrecompileEtching.sol";
import {ProposalMap} from "@test/utils/ProposalMap.sol";
import {LiveProposalCheck} from "@test/utils/LiveProposalCheck.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";

contract PostProposalCheck is LiveProposalCheck {
    using String for string;
    using ChainIds for uint256;

    /// @notice addresses contract
    Addresses public addresses;

    /// @notice governor address
    MultichainGovernor governor;

    /// @notice array of proposals in development
    Proposal[] public proposals;

    function setUp() public virtual {
        MOONBEAM_FORK_ID.createForksAndSelect();

        addresses = new Addresses();
        vm.makePersistent(address(addresses));

        governor = MultichainGovernor(
            payable(addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"))
        );

        // execute proposals that are succeeded but not executed yet
        executeSucceededProposals(addresses, governor);

        // execute proposals that are in the vote or vote collection period
        executeLiveProposals(addresses, governor);

        // execute proposals that are not on chain yet
        ProposalMap.ProposalFields[] memory devProposals = proposalMap
            .getAllProposalsInDevelopment();

        if (devProposals.length == 0) {
            return;
        }

        // execute in the inverse order so that the lowest id is executed first
        for (uint256 i = devProposals.length - 1; i >= 0; i--) {
            proposalMap.executeShellFile(devProposals[i].envPath);
            Proposal proposal = proposalMap.runProposal(
                addresses,
                devProposals[i].path
            );
            proposals.push(proposal);
        }

        if (vm.activeFork() != MOONBEAM_FORK_ID) {
            vm.selectFork(MOONBEAM_FORK_ID);
        }
    }
}
