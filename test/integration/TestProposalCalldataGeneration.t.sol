pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {console} from "@forge-std/console.sol";
import {ForkID} from "@utils/Enums.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
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

        vm.selectFork(uint256(ForkID.Moonbeam));

        governor = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
        );

        artemisGovernor = MoonwellArtemisGovernor(
            addresses.getAddress("ARTEMIS_GOVERNOR")
        );
    }

    function testProposalToolingCalldataGeneration() public {
        console.log(
            "----------------- SEARCHING HYBRID PROPOSALS -----------------"
        );

        // find hybrid proposals matches
        {
            string[] memory inputs = new string[](1);
            inputs[0] = "bin/get-hybrid-proposals.sh";

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

                uint256 proposalId = proposalContract.onchainProposalId();

                // is id is not set it means the proposal is not onchain yet
                if (proposalId == 0) {
                    continue;
                }

                address[] memory onchainTargets = new address[](targets.length);

                uint256[] memory onchainValues = new uint256[](values.length);
                bytes[] memory onchainCalldatas = new bytes[](calldatas.length);

                try
                    MultichainGovernor(governor).getProposalData(proposalId)
                returns (
                    address[] memory _targets,
                    uint256[] memory _values,
                    bytes[] memory _calldatas
                ) {
                    onchainTargets = _targets;
                    onchainValues = _values;
                    onchainCalldatas = _calldatas;
                } catch {
                    (
                        onchainTargets,
                        onchainValues,
                        ,
                        onchainCalldatas
                    ) = MoonwellArtemisGovernor(artemisGovernor).getActions(
                        proposalId
                    );
                }

                bytes32 onchainHash = keccak256(
                    abi.encode(onchainTargets, onchainValues, onchainCalldatas)
                );

                assertEq(hash, onchainHash, "Hashes do not match");

                vm.selectFork(uint256(ForkID.Moonbeam));
            }
        }

        console.log(
            "----------------- SEARCHING CROSS CHAIN PROPOSALS -----------------"
        );

        // find cross chain proposal matches
        {
            string[] memory inputs = new string[](1);
            inputs[0] = "bin/get-crosschain-proposals.sh";

            string memory output = string(vm.ffi(inputs));

            // create array splitting the output string
            string[] memory proposalsPath = vm.split(output, "\n");

            for (uint256 i = proposalsPath.length; i > 0; i--) {
                address proposal = deployCode(proposalsPath[i - 1]);
                if (proposal == address(0)) {
                    continue;
                }

                vm.makePersistent(proposal);

                CrossChainProposal proposalContract = CrossChainProposal(
                    proposal
                );
                vm.selectFork(uint256(proposalContract.primaryForkId()));
                proposalContract.build(addresses);

                address target = addresses.getAddress(
                    "WORMHOLE_CORE_MOONBEAM",
                    1284
                );

                bytes memory payload = proposalContract.getTemporalGovCalldata(
                    addresses.getAddress("TEMPORAL_GOVERNOR")
                );

                address[] memory targets = new address[](1);
                targets[0] = target;

                uint256[] memory values = new uint256[](1);
                values[0] = 0;

                bytes[] memory calldatas = new bytes[](1);
                calldatas[0] = payload;

                bytes32 hash = keccak256(
                    abi.encode(targets, values, calldatas)
                );

                uint256 proposalId = proposalContract.onchainProposalId();

                // is id is not set it means the proposal is not onchain yet
                if (proposalId == 0) {
                    continue;
                }

                address[] memory onchainTargets = new address[](targets.length);

                uint256[] memory onchainValues = new uint256[](values.length);
                bytes[] memory onchainCalldatas = new bytes[](calldatas.length);

                try
                    MultichainGovernor(governor).getProposalData(proposalId)
                returns (
                    address[] memory _targets,
                    uint256[] memory _values,
                    bytes[] memory _calldatas
                ) {
                    onchainTargets = _targets;
                    onchainValues = _values;
                    onchainCalldatas = _calldatas;
                } catch {
                    (
                        onchainTargets,
                        onchainValues,
                        ,
                        onchainCalldatas
                    ) = MoonwellArtemisGovernor(artemisGovernor).getActions(
                        proposalId
                    );
                }

                bytes32 onchainHash = keccak256(
                    abi.encode(onchainTargets, onchainValues, onchainCalldatas)
                );

                assertEq(hash, onchainHash, "Hashes do not match");

                vm.selectFork(uint256(ForkID.Moonbeam));
            }
        }

        console.log(
            "----------------- SEARCHING GOVERNANCE PROPOSALS -----------------"
        );

        {
            string[] memory inputs = new string[](1);
            inputs[0] = "bin/get-governance-proposals.sh";

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
                vm.selectFork(uint256(proposalContract.primaryForkId()));
                proposalContract.build(addresses);

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

                uint256 proposalId = proposalContract.onchainProposalId();

                // is id is not set it means the proposal is not onchain yet
                if (proposalId == 0) {
                    continue;
                }

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

                assertEq(hash, onchainHash, "Hashes do not match");

                vm.selectFork(uint256(ForkID.Moonbeam));
            }
        }
    }
}
