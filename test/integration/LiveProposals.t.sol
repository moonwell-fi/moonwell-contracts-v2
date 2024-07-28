// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import "@protocol/utils/ChainIds.sol";

import {Bytes} from "@utils/Bytes.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {String} from "@utils/String.sol";
import {Address} from "@utils/Address.sol";
import {Proposal} from "@proposals/Proposal.sol";
import {Networks} from "@proposals/utils/Networks.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {Implementation} from "@test/mock/wormhole/Implementation.sol";
import {ProposalChecker} from "@proposals/proposalTypes/ProposalChecker.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {IMultichainGovernor, MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {ChainIds, MOONBEAM_FORK_ID, MOONBEAM_CHAIN_ID, BASE_CHAIN_ID, BASE_FORK_ID} from "@utils/ChainIds.sol";

contract LiveProposalsIntegrationTest is Test, ProposalChecker, Networks {
    using String for string;
    using Bytes for bytes;
    using Address for *;
    using ChainIds for uint256;

    /// @notice addresses contract
    Addresses addresses;

    /// @notice Multichain Governor address
    address payable governor;

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

        governor = payable(addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"));
    }

    function testActiveProposals() public {
        vm.selectFork(MOONBEAM_FORK_ID);

        MultichainGovernor governorContract = MultichainGovernor(governor);

        uint256[] memory proposalIds = governorContract.liveProposals();

        string[] memory hybridProposalsPath = getProposalsByType(
            "HybridProposal"
        );
        string[] memory artemisProposalsPath = getProposalsByType(
            "GovernanceProposal"
        );

        for (uint256 i = 0; i < proposalIds.length; i++) {
            /// always need to select MOONBEAM_FORK_ID before executing a
            /// proposal as end of loop could switch to other chains for execution
            vm.selectFork(MOONBEAM_FORK_ID);

            uint256 proposalId = proposalIds[i];
            (
                address[] memory targets,
                ,
                bytes[] memory calldatas
            ) = governorContract.getProposalData(proposalId);

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

                ) = governorContract.proposalInformation(proposalId);

                address well = addresses.getAddress("xWELL_PROXY");

                vm.warp(voteSnapshotTimestamp - 1);

                deal(well, address(this), governorContract.quorum());

                xWELL(well).delegate(address(this));

                vm.warp(votingStartTime);

                governorContract.castVote(proposalId, 0);
                vm.warp(crossChainVoteCollectionEndTimestamp + 1);
            }

            /// Check if there is any action in non-Moonbeam chains
            address wormholeCore = addresses.getAddress("WORMHOLE_CORE");
            addresses.removeRestriction();

            uint256 lastIndex = targets.length - 1;
            bytes memory payload;
            if (targets[lastIndex] == wormholeCore) {
                /// increments each time the Multichain Governor publishes a message
                uint64 nextSequence = IWormhole(wormholeCore).nextSequence(
                    governor
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

                emit LogMessagePublished(
                    governor,
                    nextSequence,
                    0,
                    payload,
                    200
                );
            }

            try governorContract.execute(proposalId) {} catch (bytes memory e) {
                console.log("Error executing proposal", proposalId);
                console.log(string(e));

                bool found = false;

                // find match proposal
                for (uint256 j = 0; j < hybridProposalsPath.length; j++) {
                    found = runProposal(
                        hybridProposalsPath[j],
                        governor,
                        proposalId
                    );

                    if (found) {
                        break;
                    }
                }

                if (!found) {
                    for (uint256 j = 0; j < artemisProposalsPath.length; j++) {
                        found = runProposal(
                            artemisProposalsPath[j],
                            address(
                                payable(
                                    addresses.getAddress("ARTEMIS_GOVERNOR")
                                )
                            ),
                            proposalId
                        );

                        if (found) {
                            break;
                        }
                    }
                }

                assertTrue(
                    found,
                    string(abi.encodePacked("Proposal not found: ", proposalId))
                );
            }

            // execute the VAA on the correct chain
            if (targets[lastIndex] == wormholeCore) {
                TemporalGovernor temporalGovernor;
                {
                    // decode payload
                    (
                        address temporalGovernorAddress,
                        address[] memory baseTargets,
                        ,

                    ) = abi.decode(
                            payload,
                            (address, address[], uint256[], bytes[])
                        );

                    // figure out to which fork the temporal governor belongs
                    for (uint256 j = 0; j < networks.length; j++) {
                        vm.selectFork(networks[j].forkId);
                        // check if address has code
                        if (temporalGovernorAddress.code.length > 0) {
                            break;
                        }
                    }

                    address expectedTemporalGov = addresses.getAddress(
                        "TEMPORAL_GOVERNOR"
                    );

                    require(
                        temporalGovernorAddress == expectedTemporalGov,
                        "Temporal Governor address mismatch"
                    );

                    checkBaseOptimismActions(baseTargets);

                    temporalGovernor = TemporalGovernor(
                        payable(expectedTemporalGov)
                    );
                }

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

                bytes memory vaa = generateVAA(
                    uint32(block.timestamp),
                    block.chainid.toMoonbeamWormholeChainId(),
                    governor.toBytes(),
                    payload
                );

                temporalGovernor.queueProposal(vaa);

                vm.warp(block.timestamp + temporalGovernor.proposalDelay());

                try temporalGovernor.executeProposal(vaa) {} catch (
                    bytes memory e
                ) {
                    console.log("Error executing proposal", proposalId);
                    console.log(string(e));

                    bool found = false;
                    // find match proposal
                    for (uint256 j = 0; j < hybridProposalsPath.length; j++) {
                        found = runTemporalGovProposal(
                            temporalGovernor,
                            hybridProposalsPath[j],
                            governor,
                            vaa,
                            proposalId
                        );

                        if (found) {
                            break;
                        }
                    }

                    if (!found) {
                        for (
                            uint256 j = 0;
                            j < artemisProposalsPath.length;
                            j++
                        ) {
                            found = runTemporalGovProposal(
                                temporalGovernor,
                                artemisProposalsPath[j],
                                addresses.getAddress("ARTEMIS_GOVERNOR"),
                                vaa,
                                proposalId
                            );

                            if (found) {
                                break;
                            }
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

    function runProposal(
        string memory path,
        address governorAddress,
        uint256 proposalId
    ) private returns (bool found) {
        Proposal proposal = Proposal(deployCode(path));
        vm.makePersistent(address(proposal));

        vm.selectFork(uint256(proposal.primaryForkId()));

        // runs pre build mock and build
        proposal.preBuildMock(addresses);
        proposal.build(addresses);

        // if proposal is the one that failed, run the proposal again
        if (proposal.getProposalId(addresses, governorAddress) == proposalId) {
            vm.selectFork(MOONBEAM_FORK_ID);
            MultichainGovernor governorContract = MultichainGovernor(governor);

            governorContract.execute(proposalId);

            vm.selectFork(uint256(proposal.primaryForkId()));
            proposal.validate(addresses, address(proposal));

            found = true;
        }
    }

    function runTemporalGovProposal(
        TemporalGovernor temporalGovernor,
        string memory path,
        address governorAddress,
        bytes memory vaa,
        uint256 proposalId
    ) private returns (bool found) {
        Proposal proposal = Proposal(deployCode(path));
        vm.makePersistent(address(proposal));

        vm.selectFork(uint256(proposal.primaryForkId()));

        // runs pre build mock and build
        proposal.preBuildMock(addresses);
        proposal.build(addresses);

        // if proposal is the one that failed, run the temporal
        // governor execution again
        if (proposal.getProposalId(addresses, governorAddress) == proposalId) {
            // foundry selectFork resets warp, so we need to warp again
            vm.warp(block.timestamp + temporalGovernor.proposalDelay());

            temporalGovernor.executeProposal(vaa);

            // no need to select fork as we are already on base
            proposal.validate(addresses, address(proposal));

            found = true;
        }
    }

    function getProposalsByType(
        string memory proposalType
    ) private returns (string[] memory) {
        string[] memory inputs = new string[](2);
        inputs[0] = "bin/get-proposals-by-type.sh";
        inputs[1] = proposalType;

        string memory output = string(vm.ffi(inputs));

        // create array splitting the output string
        return output.split("\n");
    }
}
