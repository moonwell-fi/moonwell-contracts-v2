// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {console} from "@forge-std/console.sol";

import {ProposalMap} from "@test/utils/ProposalMap.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {GovernanceProposal} from "@proposals/proposalTypes/GovernanceProposal.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {IArtemisGovernor as MoonwellArtemisGovernor} from "@protocol/interfaces/IArtemisGovernor.sol";
import {MultichainGovernor, IMultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";

contract TestProposalCalldataGeneration is ProposalMap {
    Addresses public addresses;

    MultichainGovernor public governor;
    MoonwellArtemisGovernor public artemisGovernor;

    mapping(uint256 proposalId => bytes32 hash) public proposalHashes;
    mapping(uint256 proposalId => bytes32 hash) public artemisProposalHashes;

    function setUp() public {
        vm.createFork(vm.envString("MOONBEAM_RPC_URL"));
        vm.createFork(vm.envString("BASE_RPC_URL"));
        vm.createFork(vm.envString("OP_RPC_URL"));

        addresses = new Addresses();

        vm.makePersistent(address(this));
        vm.makePersistent(address(addresses));

        vm.selectFork(MOONBEAM_FORK_ID);

        governor = MultichainGovernor(
            payable(addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"))
        );

        artemisGovernor = MoonwellArtemisGovernor(
            addresses.getAddress("ARTEMIS_GOVERNOR")
        );
    }

    function testProposalToolingCalldataGeneration() public {
        for (uint256 i = proposals.length; i > 0; i--) {
            string memory proposalPath = proposals[i - 1].path;

            Proposal proposal = Proposal(deployCode(proposalPath));
            vm.makePersistent(address(proposal));

            vm.selectFork(proposal.primaryForkId());

            proposal.build(addresses);

            (
                address[] memory targets,
                uint256[] memory values,
                bytes[] memory calldatas
            ) = proposalContract.getTargetsPayloadsValues(addresses);
            bytes32 hash = keccak256(abi.encode(targets, values, calldatas));

            (
                address[] memory onchainTargets,
                uint256[] memory onchainValues,
                bytes[] memory onchainCalldatas
            ) = governor.getProposalData(proposals[i - 1].id);

            bytes32 onchainHash = keccak256(
                abi.encode(onchainTargets, onchainValues, onchainCalldatas)
            );

            assertEq(hash, onchainHash, "Hashes do not match");
            console.log(
                "Found onchain calldata for proposal: ",
                proposal.name()
            );
        }
    }

    function testProposalToolingArtemisGovernorCalldataMatch() public {
        string[] memory inputs = new string[](2);
        inputs[0] = "bin/get-proposals-by-type.sh";
        inputs[1] = "GovernanceProposal";

        string memory output = string(vm.ffi(inputs));

        // create array splitting the output string
        string[] memory proposalsPath = vm.split(output, "\n");

        for (uint256 i = proposalsPath.length; i > 0; i--) {
            address proposal = deployCode(proposalsPath[i - 1]);
            if (proposal == address(0)) {
                continue;
            }

            vm.makePersistent(proposal);

            GovernanceProposal proposalContract = GovernanceProposal(proposal);

            uint256 proposalId = proposalContract.onchainProposalId();

            // is id is not set it means the proposal is not onchain yet
            if (proposalId == 0) {
                continue;
            }

            vm.selectFork(uint256(proposalContract.primaryForkId()));
            proposalContract.build(addresses);

            vm.selectFork(MOONBEAM_FORK_ID);

            // get proposal actions
            (
                address[] memory targets,
                uint256[] memory values,
                ,
                bytes[] memory calldatas
            ) = proposalContract._getActions();

            bytes32 hash = keccak256(abi.encode(targets, values, calldatas));

            vm.selectFork(MOONBEAM_FORK_ID);

            (
                address[] memory onchainTargets,
                uint256[] memory onchainValues,
                ,
                bytes[] memory onchainCalldatas
            ) = MoonwellArtemisGovernor(artemisGovernor).getActions(proposalId);

            bytes32 onchainHash = keccak256(
                abi.encode(onchainTargets, onchainValues, onchainCalldatas)
            );

            assertEq(
                hash,
                onchainHash,
                string(
                    abi.encodePacked(
                        "Hashes do not match for proposal: ",
                        proposalContract.name()
                    )
                )
            );
            console.log(
                "Found onchain calldata for proposal: ",
                proposalContract.name()
            );
        }
    }
}
