pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import {String} from "@utils/String.sol";
import {Proposal} from "@proposals/Proposal.sol";
import {ProposalMap} from "@test/utils/ProposalMap.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract CalldataPrinting is Script, Test {
    using String for string;

    /// @notice addresses contract
    Addresses addresses;

    /// @notice proposal to file map contract
    ProposalMap proposalMap;

    constructor() {
        addresses = new Addresses();
        vm.makePersistent(address(addresses));

        proposalMap = new ProposalMap();
        vm.makePersistent(address(proposalMap));
    }

    function run() public {
        string memory changedFiles = vm.envString("PR_CHANGED_FILES");

        string[] memory changedFilesArray = changedFiles.split(" ");

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
