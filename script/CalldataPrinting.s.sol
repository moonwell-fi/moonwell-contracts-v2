pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import {String} from "@protocol/utils/String.sol";
import {Proposal} from "@proposals/Proposal.sol";
import {ProposalMap} from "@test/utils/ProposalMap.sol";
import {MOONBEAM_FORK_ID, ChainIds} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract CalldataPrinting is Script {
    using String for string;
    using ChainIds for uint256;

    /// @notice addresses contract
    Addresses addresses;

    /// @notice proposal to file map contract
    ProposalMap proposalMap;

    function run() public {
        string memory changedFiles = vm.envString("PR_CHANGED_FILES");
        console.log("changed files", changedFiles);

        string[] memory changedFilesArray = changedFiles.split(" ");
        console.log("changed files length", changedFilesArray.length);

        MOONBEAM_FORK_ID.createForksAndSelect();

        addresses = new Addresses();
        vm.makePersistent(address(addresses));

        proposalMap = new ProposalMap();
        vm.makePersistent(address(proposalMap));

        // proposals that are not on chain yet
        ProposalMap.ProposalFields[] memory devProposals = proposalMap
            .getAllProposalsInDevelopment();

        for (uint256 i = 0; i < changedFilesArray.length; i++) {
            string memory changedFile = changedFilesArray[i];

            for (uint256 j = 0; j < devProposals.length; j++) {
                if (
                    bytes32(bytes(changedFile)) ==
                    bytes32(bytes(devProposals[j].path))
                ) {
                    console.log(
                        "Proposal in development: ",
                        devProposals[j].path
                    );

                    proposalMap.executeShellFile(devProposals[i].envPath);
                    Proposal proposal = proposalMap.runProposal(
                        addresses,
                        devProposals[i].path
                    );
                    proposal.printProposalActionSteps();
                    proposal.printCalldata(addresses);
                }
            }
        }
    }
}
