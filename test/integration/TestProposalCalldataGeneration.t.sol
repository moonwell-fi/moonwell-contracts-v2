pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import {console} from "@forge-std/console.sol";
import {ForkID} from "@utils/Enums.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {IProposal} from "@proposals/proposalTypes/IProposal.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MultichainGovernor, IMultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {IArtemisGovernor as MoonwellArtemisGovernor} from "@protocol/interfaces/IArtemisGovernor.sol";
import {String} from "@utils/String.sol";
import {Bytes} from "@utils/Bytes.sol";

contract TestProposalCalldataGeneration is Test {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using String for string;
    using Bytes for bytes32;

    Addresses public addresses;

    MultichainGovernor public governor;
    MoonwellArtemisGovernor public artemisGovernor;

    uint256 public governorProposalCount;
    uint256 public artemisProposalCount;

    mapping(uint256 proposalId => bytes32 hash) public proposalHashes;
    mapping(uint256 proposalId => bytes32 hash) public artemisProposalHashes;
    EnumerableSet.Bytes32Set notFoundPaths;

    function setUp() public {
        vm.createFork(vm.envString("MOONBEAM_RPC_URL"), 6389419);
        vm.createFork(vm.envString("BASE_RPC_URL"), 15841523);
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

                IProposal proposalContract = IProposal(proposal);
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
                    // notFoundPaths.add(proposalsPath[i - 1].toBytes32());
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
            proposalsPath[0] = "src/proposals/mips/mip-b13/mip-b13.sol";

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
                    // notFoundPaths.add(proposalsPath[i - 1].toBytes32());
                    console.log(
                        "Proposal not found on MultichainGovernor or ArtemisGovernor for ",
                        proposalContract.name()
                    );
                }

                vm.selectFork(uint256(ForkID.Moonbeam));
            }
        }
    }

    function testMoonbeamCalldataGeneration() public {
        string[] memory inputs = new string[](1);
        inputs[0] = "./get-mip-m-proposals.sh";

        string memory output = string(vm.ffi(inputs));

        // create array splitting the output string
        string[] memory proposalsPath = vm.split(output, "\n");

        for (uint256 i = proposalsPath.length; i > 0; i--) {
            address proposal = deployCode(proposalsPath[i - 1]);
            if (proposal == address(0)) {
                continue;
            }

            vm.makePersistent(proposal);

            Proposal proposalContract = Proposal(proposal);
            vm.selectFork(uint256(proposalContract.primaryForkId()));
            proposalContract.build(addresses);

            /// fetch proposal id on moonbeam
            vm.selectFork(uint256(ForkID.Moonbeam));

            uint256 proposalId;
            /// proposal id could be either for Multichain Governor or Artemis Governor
            try
                proposalContract.getProposalId(
                    addresses,
                    addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
                )
            returns (uint256 result) {
                proposalId = result;
            } catch {
                try
                    proposalContract.getProposalId(
                        addresses,
                        addresses.getAddress("ARTEMIS_GOVERNOR")
                    )
                returns (uint256 result) {
                    proposalId = result;
                } catch {}
            }

            if (proposalId == 0) {
                console.log(
                    "Proposal ID not found for ",
                    proposalContract.name()
                );
            } else {
                console.log(
                    "Found Proposal ID for %s, %d",
                    proposalContract.name(),
                    proposalId
                );
            }
        }
    }

    function testBaseCalldataGeneration() public {
        string[] memory inputs = new string[](1);
        inputs[0] = "./get-mip-b-proposals.sh";

        string memory output = string(vm.ffi(inputs));

        // create array splitting the output string
        string[] memory proposalsPath = vm.split(output, "\n");

        for (uint256 i = proposalsPath.length; i > 0; i--) {
            address proposal = deployCode(proposalsPath[i - 1]);

            if (proposal == address(0)) {
                revert(proposalsPath[i - 1]);
            }

            vm.makePersistent(proposal);

            Proposal proposalContract = Proposal(proposal);
            vm.selectFork(uint256(proposalContract.primaryForkId()));
            proposalContract.build(addresses);

            /// fetch proposal id on moonbeam
            vm.selectFork(uint256(ForkID.Moonbeam));

            uint256 proposalId;
            /// proposal id could be either for Multichain Governor or Artemis Governor
            bool isArtemisProposal = CrossChainProposal(proposal)
                .isArtemisProposal();
            if (isArtemisProposal) {
                uint256 onchainProposalId = proposalContract
                    .onchainProposalId();

                onchainProposalId = onchainProposalId == 0
                    ? 0
                    : onchainProposalId - 1;
                proposalId = proposalContract.getArtemisProposalId(
                    addresses,
                    addresses.getAddress("ARTEMIS_GOVERNOR"),
                    onchainProposalId
                );
            } else {
                proposalId = proposalContract.getProposalId(
                    addresses,
                    addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
                );
            }

            if (proposalId == 0) {
                console.log(
                    "Proposal ID not found for ",
                    proposalContract.name()
                );
            } else {
                console.log(
                    "Found Proposal ID for %s, %d",
                    proposalContract.name(),
                    proposalId
                );
            }
        }
    }

    function testMipB01() public {
        address proposal = deployCode("src/proposals/mips/mip-b01/mip-b01.sol");

        vm.makePersistent(proposal);

        Proposal proposalContract = Proposal(proposal);
        vm.selectFork(uint256(proposalContract.primaryForkId()));
        proposalContract.build(addresses);

        /// fetch proposal id on moonbeam
        vm.selectFork(uint256(ForkID.Moonbeam));

        uint256 proposalId;
        /// proposal id could be either for Multichain Governor or Artemis Governor

        try
            proposalContract.getArtemisProposalId(
                addresses,
                addresses.getAddress("ARTEMIS_GOVERNOR"),
                38
            )
        returns (uint256 result) {
            proposalId = result;
        } catch {
            console.log("Error fetching proposal id");
        }

        if (proposalId == 0) {
            console.log("Proposal ID not found for ", proposalContract.name());
        } else {
            console.log(
                "Found Proposal ID for %s, %d",
                proposalContract.name(),
                proposalId
            );
        }
    }

    function testMipB17() public {
        address proposal = deployCode("src/proposals/mips/mip-b17/mip-b17.sol");

        vm.makePersistent(proposal);

        Proposal proposalContract = Proposal(proposal);
        vm.selectFork(uint256(proposalContract.primaryForkId()));
        proposalContract.build(addresses);

        /// fetch proposal id on moonbeam
        vm.selectFork(uint256(ForkID.Moonbeam));

        uint256 proposalId;

        /// proposal id should be for Multichain Governor
        proposalId = proposalContract.getProposalId(
            addresses,
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
        );

        if (proposalId == 0) {
            console.log("Proposal ID not found for ", proposalContract.name());
        } else {
            console.log(
                "Found Proposal ID for %s, %d",
                proposalContract.name(),
                proposalId
            );
        }
    }
}