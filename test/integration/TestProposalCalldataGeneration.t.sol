pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ForkID} from "@utils/Enums.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract TestProposalCalldataGeneration is Test {
    Addresses public addresses;

    function setUp() public {
        vm.createFork(vm.envString("MOONBEAM_RPC_URL"));
        vm.createFork(vm.envString("BASE_RPC_URL"));
        vm.createFork(vm.envString("OP_RPC_URL"));

        addresses = new Addresses();

        vm.makePersistent(address(this));
        vm.makePersistent(address(addresses));
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
}
