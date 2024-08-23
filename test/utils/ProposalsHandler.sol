// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

contract ProposalsHandler is Test {
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
}
