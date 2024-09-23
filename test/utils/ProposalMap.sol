// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script, stdJson} from "@forge-std/Script.sol";

import {String} from "@protocol/utils/String.sol";
import {Proposal} from "@proposals/Proposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract ProposalMap is Script {
    using String for string;
    using stdJson for string;

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
                keccak256(abi.encodePacked(proposals[i].governor)) ==
                keccak256(abi.encodePacked(governor))
            ) {
                count++;
            }
        }

        _proposals = new ProposalFields[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < proposals.length; i++) {
            if (
                keccak256(abi.encodePacked(proposals[i].governor)) ==
                keccak256(abi.encodePacked(governor))
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
                keccak256(abi.encodePacked(proposals[i].governor)) ==
                keccak256(abi.encodePacked(governor)) &&
                keccak256(abi.encodePacked(proposals[i].proposalType)) ==
                keccak256(abi.encodePacked(proposalType))
            ) {
                count++;
            }
        }

        _proposals = new ProposalFields[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < proposals.length; i++) {
            if (
                keccak256(abi.encodePacked(proposals[i].governor)) ==
                keccak256(abi.encodePacked(governor)) &&
                keccak256(abi.encodePacked(proposals[i].proposalType)) ==
                keccak256(abi.encodePacked(proposalType))
            ) {
                _proposals[index] = proposals[i];
                index++;
            }
        }
    }

    // function to execute shell file to set env variables
    function setEnv(string memory shellPath) public {
        if (bytes32(bytes(shellPath)) != bytes32("")) {
            string[] memory inputs = new string[](1);
            inputs[0] = string.concat("./", shellPath);

            string memory output = string(vm.ffi(inputs));
            string[] memory envs = split(output, "\n");

            // call setEnv for each env variable
            // so we can later call vm.envString
            for (uint256 k = 0; k < envs.length; k++) {
                string memory key = split(envs[k], "=")[0];
                string memory value = split(envs[k], "=")[1];
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

    /// had to copy the function below because forge script is not working with
    /// this library, it's revert without any error message
    /// script failed: <empty revert data>
    /// the same function works in forge test

    /// @notice returns an array of strings split by the delimiter
    /// @param str the string to split
    /// @param delimiter the delimiter to split the string by
    function split(
        string memory str,
        bytes1 delimiter
    ) private pure returns (string[] memory) {
        // Check if the input string is empty
        if (bytes(str).length == 0) {
            return new string[](0);
        }

        uint256 stringCount = countWords(str, delimiter);

        string[] memory splitStrings = new string[](stringCount);
        bytes memory strBytes = bytes(str);
        uint256 startIndex = 0;
        uint256 splitIndex = 0;

        uint256 i = 0;

        while (i < strBytes.length) {
            if (strBytes[i] == delimiter) {
                splitStrings[splitIndex] = new string(i - startIndex);

                for (uint256 j = startIndex; j < i; j++) {
                    bytes(splitStrings[splitIndex])[j - startIndex] = strBytes[
                        j
                    ];
                }

                while (i < strBytes.length && strBytes[i] == delimiter) {
                    i++;
                }

                splitIndex++;
                startIndex = i;
            }
            i++;
        }

        /// handle final word

        while (i < strBytes.length && strBytes[i] == delimiter) {
            i++;
            startIndex++;
        }

        /// handle the last word
        splitStrings[splitIndex] = new string(strBytes.length - startIndex);

        for (
            uint256 j = startIndex;
            j < strBytes.length && strBytes[j] != delimiter;
            j++
        ) {
            bytes(splitStrings[splitIndex])[j - startIndex] = strBytes[j];
        }

        return splitStrings;
    }

    function countWords(
        string memory str,
        bytes1 delimiter
    ) private pure returns (uint256) {
        bytes memory strBytes = bytes(str);
        uint256 ctr = 0;

        for (uint256 i = 0; i < strBytes.length; i++) {
            if (
                /// bounds check on i + 1, want to prevent revert on trying to access index that isn't allocated
                (strBytes[i] != delimiter && i + 1 == strBytes.length) ||
                (strBytes[i] != delimiter && strBytes[i + 1] == delimiter)
            ) {
                ctr++;
            }
        }

        return (ctr);
    }
}
