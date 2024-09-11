// SPDX-License-Identifier: GPL-3.0-or-late
pragma solidity 0.8.19;
import {console} from "forge-std/console.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {String} from "@utils/String.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {MOONBEAM_FORK_ID, ChainIds} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {etch} from "@proposals/utils/PrecompileEtching.sol";
import {ProposalMap} from "@test/utils/ProposalMap.sol";
import {LiveProposalCheck} from "@test/utils/LiveProposalCheck.sol";

contract PostProposalCheck is LiveProposalCheck {
    using String for string;
    using ChainIds for uint256;

    /// @notice addresses contract
    Addresses public addresses;

    /// @notice governor address
    MultichainGovernor governor;

    /// @notice proposal to file map contract
    ProposalMap proposalMap;

    function setUp() public virtual {
        MOONBEAM_FORK_ID.createForksAndSelect();

        proposalMap = new ProposalMap();

        addresses = new Addresses();
        vm.makePersistent(address(addresses));

        governor = MultichainGovernor(
            payable(addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"))
        );

        executeLiveProposals(addresses, governor);

        ProposalMap.ProposalFields[] memory devProposals = proposalMap
            .getAllProposalsInDevelopment();
        console.log("dev proposals length", devProposals.length);

        for (uint256 i = 0; i < devProposals.length; i++) {
            console.log("proposal envpath", devProposals[i].envPath);
            proposalMap.executeShellFile(devProposals[i].envPath);
            proposalMap.runProposal(addresses, devProposals[i].path);
        }

        vm.selectFork(MOONBEAM_FORK_ID);
    }
}
