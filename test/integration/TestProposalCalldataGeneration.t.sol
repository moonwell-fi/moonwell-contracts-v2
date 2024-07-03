pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {console} from "@forge-std/console.sol";

import {ForkID} from "@utils/Enums.sol";
import {Proposal} from "@proposals/Proposal.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {GovernanceProposal} from "@proposals/proposalTypes/GovernanceProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MultichainGovernor, IMultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {IArtemisGovernor as MoonwellArtemisGovernor} from "@protocol/interfaces/IArtemisGovernor.sol";

contract TestProposalCalldataGeneration is Test {
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

        vm.selectFork(uint256(ActionType.Moonbeam));

        governor = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
        );

        artemisGovernor = MoonwellArtemisGovernor(
            addresses.getAddress("ARTEMIS_GOVERNOR")
        );
    }

    function testProposalToolingCalldataGeneration() public {
        // find hybrid proposals matches
        {
            string[] memory inputs = new string[](2);
            inputs[0] = "bin/get-proposals-by-type.sh";
            inputs[1] = "HybridProposal";

            string memory output = string(vm.ffi(inputs));

            // create array splitting the output string
            string[] memory proposalsPath = vm.split(output, "\n");

            for (uint256 i = proposalsPath.length; i > 0; i--) {
                address proposal = deployCode(proposalsPath[i - 1]);
                if (proposal == address(0)) {
                    continue;
                }

                vm.makePersistent(proposal);

                HybridProposal proposalContract = HybridProposal(proposal);
                uint256 proposalId = proposalContract.onchainProposalId();

                // is id is not set it means the proposal is not onchain yet
                if (proposalId == 0) {
                    continue;
                }

                vm.selectFork(uint256(proposalContract.primaryForkId()));

                proposalContract.build(addresses);

                // get proposal actions
                (
                    address[] memory targets,
                    uint256[] memory values,
                    bytes[] memory calldatas
                ) = proposalContract.getTargetsPayloadsValues(addresses);

                bytes32 hash = keccak256(
                    abi.encode(targets, values, calldatas)
                );

                address[] memory onchainTargets = new address[](targets.length);
                uint256[] memory onchainValues = new uint256[](values.length);
                bytes[] memory onchainCalldatas = new bytes[](calldatas.length);

                vm.selectFork(uint256(ActionType.Moonbeam));

                (onchainTargets, onchainValues, onchainCalldatas) = governor
                    .getProposalData(proposalId);

                bytes32 onchainHash = keccak256(
                    abi.encode(onchainTargets, onchainValues, onchainCalldatas)
                );

                if (hash != onchainHash) {
                    (
                        onchainTargets,
                        onchainValues,
                        ,
                        onchainCalldatas
                    ) = MoonwellArtemisGovernor(artemisGovernor).getActions(
                        proposalId
                    );

                    onchainHash = keccak256(
                        abi.encode(
                            onchainTargets,
                            onchainValues,
                            onchainCalldatas
                        )
                    );
                }

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

        {
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

                GovernanceProposal proposalContract = GovernanceProposal(
                    proposal
                );

                uint256 proposalId = proposalContract.onchainProposalId();

                // is id is not set it means the proposal is not onchain yet
                if (proposalId == 0) {
                    continue;
                }

                vm.selectFork(uint256(proposalContract.primaryForkId()));
                proposalContract.build(addresses);

                vm.selectFork(uint256(ActionType.Moonbeam));

                // get proposal actions
                (
                    address[] memory targets,
                    uint256[] memory values,
                    ,
                    bytes[] memory calldatas
                ) = proposalContract._getActions();

                bytes32 hash = keccak256(
                    abi.encode(targets, values, calldatas)
                );

                (
                    address[] memory onchainTargets,
                    uint256[] memory onchainValues,
                    ,
                    bytes[] memory onchainCalldatas
                ) = MoonwellArtemisGovernor(artemisGovernor).getActions(
                        proposalId
                    );

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
}
