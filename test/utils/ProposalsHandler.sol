// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {String} from "@utils/String.sol";

contract ProposalsHandler is Test {
    using stdJson for string;
    using String for string;

    struct ProposalMap {
        string envPath;
        string path;
        uint256 proposalId;
    }

    ProposalMap[] public proposals;

    mapping(uint256 id => uint256) private proposalIdToIndex;

    mapping(string path => uint256) private proposalPathToIndex;

    constructor() {
        string memory data = vm.readFile(
            string(abi.encodePacked(vm.projectRoot(), "/test/utils/mips.json"))
        );

        bytes memory parsedJson = vm.parseJson(data);

        ProposalMap[] memory jsonProposals = abi.decode(
            parsedJson,
            (ProposalMap[])
        );

        for (uint256 i = 0; i < jsonProposals.length; i++) {
            addProposal(jsonProposals[i]);
        }
    }

    function addProposal(ProposalMap memory proposal) public {
        uint256 index = proposals.length;

        proposals.push();

        proposals[index].envPath = proposal.envPath;
        proposals[index].path = proposal.path;
        proposals[index].proposalId = proposal.proposalId;

        proposalIdToIndex[proposal.proposalId] = index;
        proposalPathToIndex[proposal.path] = index;
    }

    function getProposalById(
        uint256 id
    ) public view returns (string memory path, string memory envPath) {
        ProposalMap memory proposal = proposals[proposalIdToIndex[id]];
        return (proposal.path, proposal.envPath);
    }

    function getProposalByPath(
        string memory path
    ) public view returns (uint256 proposalId, string memory envPath) {
        ProposalMap memory proposal = proposals[proposalPathToIndex[path]];
        return (proposal.proposalId, proposal.envPath);
    }

    // function to execute shell file to set env variables
    function executeShellFile(
        string memory path
    ) public returns (string memory lastEnv) {
        string[] memory inputs = new string[](1);
        inputs[0] = string.concat("./", path);

        string memory output = string(vm.ffi(inputs));
        string[] memory envs = output.split("\n");

        // call setEnv for each env variable
        // so we can later call vm.envString
        for (uint256 k = 0; k < envs.length; k++) {
            string memory key = envs[k].split("=")[0];
            string memory value = envs[k].split("=")[1];
            vm.setEnv(key, value);

            if (k == envs.length - 1) {
                lastEnv = value;
            }
        }
    }
}
