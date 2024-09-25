pragma solidity 0.8.19;

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

        string[] memory changedFilesArray = changedFiles.split(" ");

        MOONBEAM_FORK_ID.createForksAndSelect();

        addresses = new Addresses();
        vm.makePersistent(address(addresses));

        proposalMap = new ProposalMap();
        vm.makePersistent(address(proposalMap));

        // proposals that are not on chain yet
        ProposalMap.ProposalFields[] memory devProposals = proposalMap
            .getAllProposalsInDevelopment();

        for (uint256 i = 0; i < devProposals.length; i++) {
            string memory devProposal = devProposals[i].path;
            string memory shellScript = devProposals[i].envPath;

            for (uint256 j = 0; j < changedFilesArray.length; j++) {
                if (
                    keccak256(abi.encodePacked(changedFilesArray[j])) ==
                    keccak256(abi.encodePacked(devProposal)) ||
                    keccak256(abi.encodePacked(changedFilesArray[j])) ==
                    keccak256(abi.encodePacked(shellScript))
                ) {
                    console.log(
                        "\n\n=================== PROPOSAL START ==================\n",
                        devProposal
                    );
                    proposalMap.setEnv(shellScript);
                    Proposal proposal = proposalMap.runProposal(
                        addresses,
                        devProposal
                    );
                    proposal.printProposalActionSteps();
                    proposal.printCalldata(addresses);

                    console.log(
                        "\n===================== PROPOSAL END ===================\n\n"
                    );

                    break;
                }
            }
        }
    }
}
