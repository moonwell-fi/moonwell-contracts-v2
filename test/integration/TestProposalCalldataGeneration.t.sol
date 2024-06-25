pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {console} from "@forge-std/console.sol";
import {ForkID} from "@utils/Enums.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MultichainGovernor, IMultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";

contract TestProposalCalldataGeneration is Test {
    Addresses public addresses;

    MultichainGovernor public governor;
    mapping(uint256 proposalId => bytes32 hash) public proposalHashes;

    struct ProposalAction {
        /// address to call
        address target;
        /// value to send
        uint256 value;
        /// calldata to pass to the target
        bytes data;
    }

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
    }

    function testMultichainGovernorCalldataGeneration() public {
        {
            uint256 proposalId = governor.proposalCount();

            // first save all the proposals actions
            while (proposalId > 0) {
                (
                    address[] memory targets,
                    uint256[] memory values,
                    bytes[] memory calldatas
                ) = MultichainGovernor(governor).getProposalData(proposalId);

                console.log("Proposal ID: %d", proposalId);

                for (uint256 i = 0; i < targets.length; i++) {
                    console.log("Target: %s", targets[i]);
                    console.log("Value: %d", values[i]);
                    console.log("Calldata:");
                    console.logBytes(calldatas[i]);
                }

                bytes32 hash = keccak256(
                    abi.encode(targets, values, calldatas)
                );

                proposalHashes[proposalId] = hash;

                console.logBytes32(hash);

                console.log("==================");
                proposalId--;
            }
        }

        {
            uint256 proposalCount = governor.proposalCount();

            string[] memory inputs = new string[](1);
            inputs[0] = "./get-mip-proposals.sh";

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
                proposalContract.preBuildMock(addresses);
                proposalContract.build(addresses);

                // get proposal actions
                (
                    address[] memory targets,
                    uint256[] memory values,
                    bytes[] memory calldatas,
                    ,

                ) = proposalContract.getProposalActionSteps();

                for (uint256 i = 0; i < targets.length; i++) {
                    console.log("Target: %s", targets[i]);
                    console.log("Value: %d", values[i]);
                    console.log("Calldata:");
                    console.logBytes(calldatas[i]);
                }

                bytes32 hash = keccak256(
                    abi.encode(targets, values, calldatas)
                );
                console.logBytes32(hash);

                uint256 proposalId = proposalCount;

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
                        break;
                    }
                    proposalId--;
                }

                // if proposalId is 0, then the proposal was not found
                if (proposalId == 0) {
                    console.log(
                        "Proposal ID not found for ",
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
