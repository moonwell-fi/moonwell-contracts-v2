// SPDX-License-Identifier: GPL-3.0-or-late
pragma solidity 0.8.19;

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {String} from "@utils/String.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {MOONBEAM_FORK_ID, ChainIds} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {etch} from "@proposals/utils/PrecompileEtching.sol";
import {ProposalMap} from "@test/utils/ProposalMap.sol";

contract PostProposalCheck is ProposalMap {
    using String for string;
    using ChainIds for uint256;

    /// @notice addresses contract
    Addresses public addresses;

    /// @notice governor address
    MultichainGovernor governor;

    function setUp() public virtual {
        MOONBEAM_FORK_ID.createForksAndSelect();

        addresses = new Addresses();
        vm.makePersistent(address(addresses));

        governor = MultichainGovernor(
            payable(addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"))
        );

        address well = addresses.getAddress("xWELL_PROXY");

        vm.warp(1000);

        deal(well, address(this), governor.quorum());
        xWELL(well).delegate(address(this));

        uint256[] memory liveProposals = governor.liveProposals();

        for (uint256 i = 0; i < liveProposals.length; i++) {
            (address[] memory targets, , ) = governor.getProposalData(
                liveProposals[i]
            );

            {
                // Simulate proposals execution
                (
                    ,
                    ,
                    uint256 votingStartTime,
                    ,
                    uint256 crossChainVoteCollectionEndTimestamp,
                    ,
                    ,
                    ,

                ) = governor.proposalInformation(liveProposals[i]);

                vm.warp(votingStartTime);

                governor.castVote(liveProposals[i], 0);

                vm.warp(crossChainVoteCollectionEndTimestamp + 1);
            }

            uint256 totalValue = 0;
            (, uint256[] memory values, ) = governor.getProposalData(
                liveProposals[i]
            );

            for (uint256 j = 0; j < values.length; j++) {
                totalValue += values[j];
            }

            governor.execute{value: totalValue}(liveProposals[i]);
        }

        /// only etch out precompile contracts if on the moonbeam chain
        if (
            addresses.isAddressSet("xcUSDT") &&
            addresses.isAddressSet("xcUSDC") &&
            addresses.isAddressSet("xcDOT")
        ) {
            etch(vm, addresses);
        }

        ProposalFields[] memory devProposals = getAllProposalsInDevelopment();

        for (uint256 i = 0; i < devProposals.length; i++) {
            executeShellFile(devProposals[i].envPath);
            runProposal(addresses, devProposals[i].path);
        }

        vm.selectFork(MOONBEAM_FORK_ID);
    }
}
