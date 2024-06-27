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
import {String} from "@utils/String.sol";
import {Bytes} from "@utils/Bytes.sol";

contract TestProposalCalldataGeneration is Test {
    using String for string;
    using Bytes for bytes32;

    Addresses public addresses;

    MultichainGovernor public governor;
    MoonwellArtemisGovernor public artemisGovernor;

    uint256 public governorProposalCount;
    uint256 public artemisProposalCount;

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

        governorProposalCount = governor.proposalCount();

        artemisGovernor = MoonwellArtemisGovernor(
            addresses.getAddress("ARTEMIS_GOVERNOR")
        );
        artemisProposalCount = artemisGovernor.proposalCount();
    }

    function testMultichainGovernorCalldataGeneration() public {
        {
            uint256 proposalId = governorProposalCount;

            // first save all the proposals actions
            while (proposalId > 0) {
                (
                    address[] memory targets,
                    uint256[] memory values,
                    bytes[] memory calldatas
                ) = MultichainGovernor(governor).getProposalData(proposalId);

                bytes32 hash = keccak256(
                    abi.encode(targets, values, calldatas)
                );

                proposalHashes[proposalId] = hash;

                // console.log("==================");
                proposalId--;
            }
        }

        {
            uint256 proposalId = artemisProposalCount;

            // first save all the proposals actions
            while (proposalId > 0) {
                (
                    address[] memory targets,
                    uint256[] memory values,
                    ,
                    bytes[] memory calldatas
                ) = MoonwellArtemisGovernor(artemisGovernor).getActions(
                        proposalId
                    );

                bytes32 hash = keccak256(
                    abi.encode(targets, values, calldatas)
                );

                artemisProposalHashes[proposalId] = hash;

                proposalId--;
            }
        }

        // find hybrid proposals matches
        {
            string[] memory inputs = new string[](1);
            inputs[0] = "./get-hybrid-proposals.sh";

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

                uint256 proposalId = governorProposalCount;

                bool found = false;

                // see if the hash of the proposal actions is the same as one of the
                // proposals fetched from the Multichain Governor
                while (proposalId > 0) {
                    if (proposalHashes[proposalId] == hash) {
                        console.log(
                            "Proposal ID found for %s, %d",
                            proposalContract.name(),
                            proposalId
                        );

                        // delete from the proposalHashes mapping
                        delete proposalHashes[proposalId];

                        found = true;
                        break;
                    }
                    proposalId--;
                }

                proposalId = artemisProposalCount;

                // see if the hash of the proposal actions is the same as one of
                // the proposals fetched from the Artemis Governor

                while (proposalId > 0 && found == false) {
                    if (artemisProposalHashes[proposalId] == hash) {
                        console.log(
                            "Proposal ID found for %s, %d",
                            proposalContract.name(),
                            proposalId
                        );

                        // delete from the proposalHashes mapping
                        delete artemisProposalHashes[proposalId];
                        found = true;
                        break;
                    }
                    proposalId--;
                }

                if (found == false) {
                    console.log(
                        "Proposal not found on MultichainGovernor or ArtemisGovernor for ",
                        proposalContract.name()
                    );
                }

                vm.selectFork(uint256(ForkID.Moonbeam));
            }
        }

        console.log(
            "----------------- SEARCHING CROSS CHAIN PROPOSALS -----------------"
        );

        // find cross chain proposal matches
        {
            string[] memory inputs = new string[](1);
            inputs[0] = "./get-crosschain-proposals.sh";

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

                uint256 proposalId = governorProposalCount;

                bool found = false;

                // see if the hash of the proposal actions is the same as one of the
                // proposals fetched from the MultichainGovernor
                while (proposalId > 0) {
                    if (proposalHashes[proposalId] == hash) {
                        console.log(
                            "Proposal ID found for %s, %d",
                            proposalContract.name(),
                            proposalId
                        );

                        // delete from the proposalHashes mapping
                        delete proposalHashes[proposalId];

                        found = true;

                        break;
                    }
                    proposalId--;
                }

                proposalId = artemisProposalCount;

                // see if the hash of the proposal actions is the same as one of
                // the proposals fetched from the Artemis Governor

                while (proposalId > 0 && found == false) {
                    if (artemisProposalHashes[proposalId] == hash) {
                        console.log(
                            "Proposal ID found for %s, %d",
                            proposalContract.name(),
                            proposalId
                        );

                        // delete from the proposalHashes mapping
                        delete artemisProposalHashes[proposalId];

                        found = true;
                        break;
                    }
                    proposalId--;
                }

                if (found == false) {
                    console.log(
                        "Proposal not found on MultichainGovernor or ArtemisGovernor for ",
                        proposalContract.name()
                    );
                }

                vm.selectFork(uint256(ForkID.Moonbeam));
            }
        }

        console.log(
            "----------------- SEARCHING GOVERNANCE PROPOSALS -----------------"
        );

        // find cross chain proposal matches
        {
            string[] memory inputs = new string[](1);
            inputs[0] = "./get-governance-proposals.sh";

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

                uint256 proposalId = artemisProposalCount;

                bool found = false;

                // see if the hash of the proposal actions is the same as one of
                // the proposals fetched from the Artemis Governor

                while (proposalId > 0 && found == false) {
                    if (artemisProposalHashes[proposalId] == hash) {
                        console.log(
                            "Proposal ID found for %s, %d",
                            proposalContract.name(),
                            proposalId
                        );

                        // delete from the proposalHashes mapping
                        delete artemisProposalHashes[proposalId];

                        found = true;
                        break;
                    }
                    proposalId--;
                }

                if (found == false) {
                    console.log(
                        "Proposal not found on ArtemisGovernor for ",
                        proposalContract.name()
                    );
                }

                vm.selectFork(uint256(ForkID.Moonbeam));
            }
        }
    }

    function testMipB16() public {
        {
            uint256 proposalId = 70;

            (
                address[] memory targets,
                uint256[] memory values,
                ,
                bytes[] memory calldatas
            ) = MoonwellArtemisGovernor(artemisGovernor).getActions(proposalId);

            for (uint256 i = 0; i < targets.length; i++) {
                console.log("Targets: %s", targets[i]);
                console.log("Values: %s", values[i]);
                console.logBytes(calldatas[i]);
            }

            bytes32 hash = keccak256(abi.encode(targets, values, calldatas));

            artemisProposalHashes[proposalId] = hash;
            console.log("hash");
            console.logBytes32(hash);
            console.log("=-======================");
        }

        address proposal = deployCode("src/proposals/mips/mip-m16/mip-m16.sol");

        vm.makePersistent(proposal);

        GovernanceProposal proposalContract = GovernanceProposal(proposal);
        vm.selectFork(uint256(proposalContract.primaryForkId()));
        proposalContract.build(addresses);

        // get proposal actions
        (
            address[] memory targets,
            uint256[] memory values,
            ,
            bytes[] memory calldatas
        ) = proposalContract._getActions();

        for (uint256 i = 0; i < targets.length; i++) {
            console.log("Targets: %s", targets[i]);
            console.log("Values: %s", values[i]);
            console.logBytes(calldatas[i]);
        }

        bytes32 hash = keccak256(abi.encode(targets, values, calldatas));

        console.log("hash");
        console.logBytes32(hash);

        uint256 proposalId = 70;

        bool found = false;

        // see if the hash of the proposal actions is the same as one of
        // the proposals fetched from the Artemis Governor

        if (artemisProposalHashes[proposalId] == hash) {
            console.log(
                "Proposal ID found for %s, %d",
                proposalContract.name(),
                proposalId
            );

            // delete from the proposalHashes mapping
            delete artemisProposalHashes[proposalId];

            found = true;
        }
    }
}
