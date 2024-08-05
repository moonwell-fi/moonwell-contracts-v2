// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import "@protocol/utils/ChainIds.sol";

import {console} from "@forge-std/console.sol";
import {Bytes} from "@utils/Bytes.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {String} from "@utils/String.sol";
import {Address} from "@utils/Address.sol";
import {Proposal} from "@proposals/Proposal.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {Implementation} from "@test/mock/wormhole/Implementation.sol";
import {ProposalChecker} from "@proposals/proposalTypes/ProposalChecker.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {IMultichainGovernor, MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {ChainIds, MOONBEAM_FORK_ID, MOONBEAM_CHAIN_ID, BASE_CHAIN_ID, BASE_FORK_ID} from "@utils/ChainIds.sol";

contract LiveProposalsIntegrationTest is Test, ProposalChecker {
    using String for string;
    using Bytes for bytes;
    using Address for *;
    using ChainIds for uint256;

    /// @notice addresses contract
    Addresses addresses;

    /// @notice Multichain Governor address
    MultichainGovernor governor;

    /// @notice allows asserting wormhole core correctly emits data to temporal governor
    event LogMessagePublished(
        address indexed sender,
        uint64 sequence,
        uint32 nonce,
        bytes payload,
        uint8 consistencyLevel
    );

    function setUp() public {
        MOONBEAM_FORK_ID.createForksAndSelect();

        addresses = new Addresses();
        vm.makePersistent(address(addresses));

        address governorAddress = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );

        governor = MultichainGovernor(payable(governorAddress));
    }

    function testActiveProposals() public {
        vm.selectFork(MOONBEAM_FORK_ID);

        uint256[] memory proposalIds = governor.liveProposals();

        string[] memory inputs = new string[](1);
        inputs[0] = "bin/get-latest-proposals.sh";

        string memory output = string(vm.ffi(inputs));

        // create array splitting the output string
        string[] memory proposalsPath = output.split("\n");

        for (uint256 i = 0; i < proposalIds.length; i++) {
            /// always need to select MOONBEAM_FORK_ID before executing a
            /// proposal as end of loop could switch to base for execution
            vm.selectFork(MOONBEAM_FORK_ID);

            uint256 proposalId = proposalIds[i];
            (address[] memory targets, , bytes[] memory calldatas) = governor
                .getProposalData(proposalId);

            addresses.addRestriction(MOONBEAM_CHAIN_ID);

            checkMoonbeamActions(targets);
            {
                // Simulate proposals execution
                (
                    ,
                    uint256 voteSnapshotTimestamp,
                    uint256 votingStartTime,
                    ,
                    uint256 crossChainVoteCollectionEndTimestamp,
                    ,
                    ,
                    ,

                ) = governor.proposalInformation(proposalId);

                address well = addresses.getAddress("xWELL_PROXY");

                vm.warp(voteSnapshotTimestamp - 1);

                deal(well, address(this), governor.quorum());

                xWELL(well).delegate(address(this));

                vm.warp(votingStartTime);

                governor.castVote(proposalId, 0);
                vm.warp(crossChainVoteCollectionEndTimestamp + 1);
            }

            /// Check if there is any action on Base
            address wormholeCore = addresses.getAddress("WORMHOLE_CORE");
            addresses.removeRestriction();

            uint256 lastIndex = targets.length - 1;
            bytes memory payload;
            if (targets[lastIndex] == wormholeCore) {
                /// increments each time the Multichain Governor publishes a message
                uint64 nextSequence = IWormhole(wormholeCore).nextSequence(
                    address(governor)
                );

                // decode calldatas
                (, payload, ) = abi.decode(
                    calldatas[lastIndex].slice(
                        4,
                        calldatas[lastIndex].length - 4
                    ),
                    (uint32, bytes, uint8)
                );

                /// expect emitting of events to Wormhole Core on Moonbeam if Base actions exist
                vm.expectEmit(true, true, true, true, wormholeCore);

                /// event LogMessagePublished(address indexed sender, uint64 sequence, uint32 nonce, bytes payload, uint8 consistencyLevel)
                emit LogMessagePublished(
                    address(governor),
                    nextSequence,
                    0,
                    payload,
                    200
                );
            }

            uint256 totalValue = 0;
            {
                (, uint256[] memory values, ) = governor.getProposalData(
                    proposalId
                );
                for (uint256 j = 0; j < values.length; j++) {
                    totalValue += values[j];
                }
            }
            try governor.execute{value: totalValue}(proposalId) {} catch (
                bytes memory e
            ) {
                console.log("Error executing proposal", proposalId);
                console.log(string(e));

                // find match proposal
                for (uint256 j = 0; j < proposalsPath.length; j++) {
                    // check if proposal ends with .json

                    string memory solPath;
                    if (proposalsPath[j].endsWith(".sh")) {
                        // execute .sh file
                        inputs = new string[](1);
                        inputs[0] = proposalsPath[j];

                        // get the template path from the just setted TEMPLATE_PATH env
                        solPath = string(vm.envString("TEMPLATE_PATH"));
                    } else {
                        solPath = proposalsPath[j];
                    }

                    console.log("Proposal path", solPath);

                    Proposal proposal = Proposal(deployCode(solPath));
                    vm.makePersistent(address(proposal));

                    vm.selectFork(uint256(proposal.primaryForkId()));

                    // runs pre build mock and build
                    proposal.preBuildMock(addresses);
                    proposal.build(addresses);

                    // if proposal is the one that failed, run the proposal again
                    if (
                        proposal.getProposalId(addresses, address(governor)) ==
                        proposalId
                    ) {
                        vm.selectFork(MOONBEAM_FORK_ID);
                        governor.execute{value: totalValue}(proposalId);

                        vm.selectFork(uint256(proposal.primaryForkId()));
                        proposal.validate(addresses, address(proposal));
                        break;
                    }
                }
            }

            if (targets[lastIndex] == wormholeCore) {
                (
                    address temporalGovernorAddress,
                    address[] memory baseTargets,
                    ,

                ) = abi.decode(
                        payload,
                        (address, address[], uint256[], bytes[])
                    );

                vm.selectFork(BASE_FORK_ID);
                // check if the Temporal Governor address exist on the base chain
                if (address(temporalGovernorAddress).code.length == 0) {
                    // if not, checkout to Optimism fork id
                    vm.selectFork(OPTIMISM_FORK_ID);
                }

                address expectedTemporalGov = addresses.getAddress(
                    "TEMPORAL_GOVERNOR"
                );

                require(
                    temporalGovernorAddress == expectedTemporalGov,
                    "Temporal Governor address mismatch"
                );

                checkBaseOptimismActions(baseTargets);

                bytes memory vaa = generateVAA(
                    uint32(block.timestamp),
                    block.chainid.toMoonbeamWormholeChainId(),
                    address(governor).toBytes(),
                    payload
                );

                TemporalGovernor temporalGovernor = TemporalGovernor(
                    payable(expectedTemporalGov)
                );

                {
                    // Deploy the modified Wormhole Core implementation contract which
                    // bypass the guardians signature check
                    Implementation core = new Implementation();
                    address wormhole = addresses.getAddress(
                        "WORMHOLE_CORE",
                        block.chainid
                    );

                    /// Set the wormhole core address to have the
                    /// runtime bytecode of the mock core
                    vm.etch(wormhole, address(core).code);
                }

                temporalGovernor.queueProposal(vaa);

                vm.warp(block.timestamp + temporalGovernor.proposalDelay());

                try temporalGovernor.executeProposal(vaa) {} catch (
                    bytes memory e
                ) {
                    console.log("Error executing proposal", proposalId);
                    console.log(string(e));

                    // find match proposal
                    for (uint256 j = 0; j < proposalsPath.length; j++) {
                        Proposal proposal = Proposal(
                            deployCode(proposalsPath[j])
                        );
                        vm.makePersistent(address(proposal));

                        vm.selectFork(uint256(proposal.primaryForkId()));

                        // runs pre build mock and build
                        proposal.preBuildMock(addresses);
                        proposal.build(addresses);

                        // if proposal is the one that failed, run the temporal
                        // governor execution again
                        if (
                            proposal.getProposalId(
                                addresses,
                                address(governor)
                            ) == proposalId
                        ) {
                            // foundry selectFork resets warp, so we need to warp again
                            vm.warp(
                                block.timestamp +
                                    temporalGovernor.proposalDelay()
                            );

                            temporalGovernor.executeProposal(vaa);

                            // no need to select fork as we are already on base
                            proposal.validate(addresses, address(proposal));
                            break;
                        }
                    }
                }
            }
        }
    }

    /// @dev utility function to generate a Wormhole VAA payload excluding the guardians signature
    function generateVAA(
        uint32 timestamp,
        uint16 emitterChainId,
        bytes32 emitterAddress,
        bytes memory payload
    ) private pure returns (bytes memory encodedVM) {
        uint64 sequence = 200;
        uint8 version = 1;
        uint32 nonce = 0;
        uint8 consistencyLevel = 200;

        encodedVM = abi.encodePacked(
            version,
            timestamp,
            nonce,
            emitterChainId,
            emitterAddress,
            sequence,
            consistencyLevel,
            payload
        );
    }

    function getTargetsPayloadsValues(
        Addresses
    )
        public
        view
        override
        returns (address[] memory, uint256[] memory, bytes[] memory)
    {}
}
