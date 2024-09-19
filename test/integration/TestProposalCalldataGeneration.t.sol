// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {console} from "@forge-std/console.sol";

import {ProposalMap} from "@test/utils/ProposalMap.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {GovernanceProposal} from "@proposals/proposalTypes/GovernanceProposal.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
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

    function testMultichainGovernorCalldataMatch() public {
        ProposalFields[]
            memory multichainGovernorProposals = filterByGovernorAndProposalType(
                "MultichainGovernor",
                "HybridProposal"
            );
        for (uint256 i = multichainGovernorProposals.length; i > 0; i--) {
            // exclude proposals that are not onchain yet
            if (multichainGovernorProposals[i - 1].id == 0) {
                continue;
            }

            executeShellFile(multichainGovernorProposals[i - 1].envPath);

            string memory proposalPath = multichainGovernorProposals[i - 1]
                .path;

            HybridProposal proposal = HybridProposal(deployCode(proposalPath));
            vm.makePersistent(address(proposal));

            vm.selectFork(proposal.primaryForkId());

            proposal.initProposal(addresses);
            proposal.build(addresses);

            (
                address[] memory targets,
                uint256[] memory values,
                bytes[] memory calldatas
            ) = proposal.getTargetsPayloadsValues(addresses);
            bytes32 hash = keccak256(abi.encode(targets, values, calldatas));

            vm.selectFork(MOONBEAM_FORK_ID);

            bytes32 onchainHash;
            {
                (
                    address[] memory onchainTargets,
                    uint256[] memory onchainValues,
                    bytes[] memory onchainCalldatas
                ) = governor.getProposalData(
                        multichainGovernorProposals[i - 1].id
                    );

                onchainHash = keccak256(
                    abi.encode(onchainTargets, onchainValues, onchainCalldatas)
                );
            }

            assertEq(
                hash,
                onchainHash,
                string(
                    abi.encodePacked(
                        "Hashes do not match for proposal ",
                        vm.toString(multichainGovernorProposals[i - 1].id)
                    )
                )
            );
            console.log(
                "Found onchain calldata for proposal: ",
                proposal.name()
            );
        }
    }

    function testArtemisGovernorCalldataMatchHybridProposal() public {
        ProposalFields[]
            memory artemisGovernorProposals = filterByGovernorAndProposalType(
                "ArtemisGovernor",
                "HybridProposal"
            );
        for (uint256 i = artemisGovernorProposals.length; i > 0; i--) {
            // exclude proposals that are not onchain yet
            if (artemisGovernorProposals[i - 1].id == 0) {
                continue;
            }

            executeShellFile(artemisGovernorProposals[i - 1].envPath);

            string memory proposalPath = artemisGovernorProposals[i - 1].path;

            HybridProposal proposal = HybridProposal(deployCode(proposalPath));
            vm.makePersistent(address(proposal));

            vm.selectFork(proposal.primaryForkId());

            proposal.initProposal(addresses);
            proposal.build(addresses);

            (
                address[] memory targets,
                uint256[] memory values,
                bytes[] memory calldatas
            ) = proposal.getTargetsPayloadsValues(addresses);
            bytes32 hash = keccak256(abi.encode(targets, values, calldatas));

            vm.selectFork(MOONBEAM_FORK_ID);

            bytes32 onchainHash;
            {
                (
                    address[] memory onchainTargets,
                    uint256[] memory onchainValues,
                    ,
                    bytes[] memory onchainCalldatas
                ) = artemisGovernor.getActions(
                        artemisGovernorProposals[i - 1].id
                    );

                onchainHash = keccak256(
                    abi.encode(onchainTargets, onchainValues, onchainCalldatas)
                );
            }

            assertEq(
                hash,
                onchainHash,
                string(
                    abi.encodePacked(
                        "Hashes do not match for proposal ",
                        vm.toString(artemisGovernorProposals[i - 1].id)
                    )
                )
            );
            console.log(
                "Found onchain calldata for proposal: ",
                proposal.name()
            );
        }
    }

    function testArtemisGovernorCalldataMatchGovernanceProposal() public {
        ProposalFields[]
            memory artemisGovernorProposals = filterByGovernorAndProposalType(
                "ArtemisGovernor",
                "GovernanceProposal"
            );
        for (uint256 i = artemisGovernorProposals.length; i > 0; i--) {
            // exclude proposals that are not onchain yet
            if (artemisGovernorProposals[i - 1].id == 0) {
                continue;
            }

            executeShellFile(artemisGovernorProposals[i - 1].envPath);

            string memory proposalPath = artemisGovernorProposals[i - 1].path;

            GovernanceProposal proposal = GovernanceProposal(
                deployCode(proposalPath)
            );
            vm.makePersistent(address(proposal));

            vm.selectFork(proposal.primaryForkId());

            proposal.initProposal(addresses);
            proposal.build(addresses);

            (
                address[] memory targets,
                uint256[] memory values,
                ,
                bytes[] memory calldatas
            ) = proposal._getActions();
            bytes32 hash = keccak256(abi.encode(targets, values, calldatas));

            vm.selectFork(MOONBEAM_FORK_ID);

            bytes32 onchainHash;
            {
                (
                    address[] memory onchainTargets,
                    uint256[] memory onchainValues,
                    ,
                    bytes[] memory onchainCalldatas
                ) = artemisGovernor.getActions(
                        artemisGovernorProposals[i - 1].id
                    );

                onchainHash = keccak256(
                    abi.encode(onchainTargets, onchainValues, onchainCalldatas)
                );
            }

            assertEq(
                hash,
                onchainHash,
                string(
                    abi.encodePacked(
                        "Hashes do not match for proposal ",
                        vm.toString(artemisGovernorProposals[i - 1].id)
                    )
                )
            );
            console.log(
                "Found onchain calldata for proposal: ",
                proposal.name()
            );
        }
    }
}
