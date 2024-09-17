// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {String} from "@utils/String.sol";
import {Proposal} from "@proposals/Proposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract ProposalMap is Test {
    using stdJson for string;
    using String for string;

    struct ProposalFields {
        string envPath;
        string governor;
        uint256 id;
        string path;
        string proposalType;
    }

    ProposalFields[] public proposals;

    mapping(uint256 id => uint256) private proposalIdToIndex;

    mapping(string path => uint256) private proposalPathToIndex;

    constructor() {
        string memory data = vm.readFile(
            string(
                abi.encodePacked(
                    vm.projectRoot(),
                    "/src/proposals/mips/mips.json"
                )
            )
        );

        bytes memory parsedJson = vm.parseJson(data);

        ProposalFields[] memory jsonProposals = abi.decode(
            parsedJson,
            (ProposalFields[])
        );

        for (uint256 i = 0; i < jsonProposals.length; i++) {
            addProposal(jsonProposals[i]);
        }
    }

    function addProposal(ProposalFields memory proposal) public {
        uint256 index = proposals.length;

        proposals.push();

        proposals[index].envPath = proposal.envPath;
        proposals[index].governor = proposal.governor;
        proposals[index].id = proposal.id;
        proposals[index].path = proposal.path;
        proposals[index].proposalType = proposal.proposalType;

        proposalIdToIndex[proposal.id] = index;
        proposalPathToIndex[proposal.path] = index;
    }

    function getProposalById(
        uint256 id
    ) public view returns (string memory path, string memory envPath) {
        ProposalFields memory proposal = proposals[proposalIdToIndex[id]];
        return (proposal.path, proposal.envPath);
    }

    function getProposalByPath(
        string memory path
    ) public view returns (uint256 proposalId, string memory envPath) {
        ProposalFields memory proposal = proposals[proposalPathToIndex[path]];
        return (proposal.id, proposal.envPath);
    }

    function getAllProposalsInDevelopment()
        public
        view
        returns (ProposalFields[] memory _proposals)
    {
        // filter proposals with id == 0;
        uint256 count = 0;
        for (uint256 i = 0; i < proposals.length; i++) {
            if (proposals[i].id == 0) {
                count++;
            }
        }

        _proposals = new ProposalFields[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < proposals.length; i++) {
            if (proposals[i].id == 0) {
                _proposals[index] = proposals[i];
                index++;
            }
        }
    }

    function filterByGovernor(
        string memory governor
    ) public view returns (ProposalFields[] memory _proposals) {
        uint256 count = 0;
        for (uint256 i = 0; i < proposals.length; i++) {
            if (
                bytes32(bytes(proposals[i].governor)) ==
                bytes32(bytes(governor))
            ) {
                count++;
            }
        }

        _proposals = new ProposalFields[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < proposals.length; i++) {
            if (
                bytes32(bytes(proposals[i].governor)) ==
                bytes32(bytes(governor))
            ) {
                _proposals[index] = proposals[i];
                index++;
            }
        }
    }

    function filterByGovernorAndProposalType(
        string memory governor,
        string memory proposalType
    ) public view returns (ProposalFields[] memory _proposals) {
        uint256 count = 0;
        for (uint256 i = 0; i < proposals.length; i++) {
            if (
                bytes32(bytes(proposals[i].governor)) ==
                bytes32(bytes(governor)) &&
                bytes32(bytes(proposals[i].proposalType)) ==
                bytes32(bytes(proposalType))
            ) {
                count++;
            }
        }

        _proposals = new ProposalFields[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < proposals.length; i++) {
            if (
                bytes32(bytes(proposals[i].governor)) ==
                bytes32(bytes(governor)) &&
                bytes32(bytes(proposals[i].proposalType)) ==
                bytes32(bytes(proposalType))
            ) {
                _proposals[index] = proposals[i];
                index++;
            }
        }
    }

    // function to execute shell file to set env variables
    function executeShellFile(string memory shellPath) public {
        if (bytes32(bytes(shellPath)) != bytes32("")) {
            string[] memory inputs = new string[](1);
            inputs[0] = string.concat("./", shellPath);

            string memory output = string(vm.ffi(inputs));
            string[] memory envs = output.split("\n");

            // call setEnv for each env variable
            // so we can later call vm.envString
            for (uint256 k = 0; k < envs.length; k++) {
                string memory key = envs[k].split("=")[0];
                string memory value = envs[k].split("=")[1];
                vm.setEnv(key, value);
            }
        }
    }

    function runProposal(
        Addresses addresses,
        string memory proposalPath
    ) public returns (Proposal proposal) {
        proposal = Proposal(deployCode(proposalPath));
        vm.makePersistent(address(proposal));

        vm.selectFork(proposal.primaryForkId());

        address deployer = address(proposal);
        proposal.initProposal(addresses);
        proposal.deploy(addresses, deployer);
        proposal.afterDeploy(addresses, deployer);
        proposal.preBuildMock(addresses);
        proposal.build(addresses);
        proposal.teardown(addresses, deployer);
        proposal.run(addresses, deployer);
        proposal.validate(addresses, deployer);
    }
}
