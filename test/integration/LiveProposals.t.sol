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
import {Networks} from "@proposals/utils/Networks.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {ProposalMap} from "@test/utils/ProposalMap.sol";
import {Implementation} from "@test/mock/wormhole/Implementation.sol";
import {ProposalChecker} from "@proposals/proposalTypes/ProposalChecker.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
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

    /// @notice proposals handler
    ProposalMap proposals;

    /// @notice Multichain Governor address
    MultichainGovernor governor;

    /// @notice list of live proposals
    uint256[] public proposalIds;

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

        proposals = new ProposalMap();
        vm.makePersistent(address(proposals));

        proposalIds = governor.liveProposals();
    }

    /// checks that all live proposals execute successfully
    function testExecutingLiveProposals() public {
        vm.selectFork(MOONBEAM_FORK_ID);
        addresses.addRestriction(MOONBEAM_CHAIN_ID);

        address well = addresses.getAddress("xWELL_PROXY");

        vm.warp(1000);

        deal(well, address(this), governor.quorum());
        xWELL(well).delegate(address(this));

        for (uint256 i = 0; i < proposalIds.length; i++) {
            (address[] memory targets, , ) = governor.getProposalData(
                proposalIds[i]
            );

            checkMoonbeamActions(targets);
            {
                // Simulate proposals execution
                (
                    ,
                    ,
                    uint256 votingStartTime,
                    ,
                    uint256 crossChainVoteCollectionEndTimestamp,
                    ,
                    ,
                    ,

                ) = governor.proposalInformation(proposalIds[i]);

                vm.warp(votingStartTime);

                governor.castVote(proposalIds[i], 0);

                vm.warp(crossChainVoteCollectionEndTimestamp + 1);
            }

            uint256 totalValue = 0;
            (, uint256[] memory values, ) = governor.getProposalData(
                proposalIds[i]
            );

            for (uint256 j = 0; j < values.length; j++) {
                totalValue += values[j];
            }

            governor.execute{value: totalValue}(proposalIds[i]);
        }

        addresses.removeRestriction();
    }

    function testExecutingLiveProposalsAcrossChains() public {
        vm.selectFork(MOONBEAM_FORK_ID);
        addresses.addRestriction(MOONBEAM_CHAIN_ID);

        /// ----------------------------------------------------------
        /// ---------------- Wormhole Relayer Etching ----------------
        /// ----------------------------------------------------------

        /// mock relayer so we can simulate bridging well
        WormholeRelayerAdapter wormholeRelayer = new WormholeRelayerAdapter();
        vm.makePersistent(address(wormholeRelayer));
        vm.label(address(wormholeRelayer), "MockWormholeRelayer");

        /// we need to set this so that the relayer mock knows that for the next sendPayloadToEvm
        /// call it must switch forks
        wormholeRelayer.setIsMultichainTest(true);
        wormholeRelayer.setSenderChainId(MOONBEAM_WORMHOLE_CHAIN_ID);

        // set mock as the wormholeRelayer address on bridge adapter
        WormholeBridgeAdapter wormholeBridgeAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        uint256 gasLimit = wormholeBridgeAdapter.gasLimit();

        // encode gasLimit and relayer address since is stored in a single slot
        // relayer is first due to how evm pack values into a single storage
        bytes32 encodedData = bytes32(
            (uint256(uint160(address(wormholeRelayer))) << 96) |
                uint256(gasLimit)
        );

        vm.selectFork(BASE_FORK_ID);

        /// stores the wormhole mock address in the wormholeRelayer variable
        vm.store(
            address(wormholeBridgeAdapter),
            bytes32(uint256(153)),
            encodedData
        );

        vm.selectFork(OPTIMISM_FORK_ID);

        /// stores the wormhole mock address in the wormholeRelayer variable
        vm.store(
            address(wormholeBridgeAdapter),
            bytes32(uint256(153)),
            encodedData
        );

        vm.selectFork(MOONBEAM_FORK_ID);

        /// stores the wormhole mock address in the wormholeRelayer variable
        vm.store(
            address(wormholeBridgeAdapter),
            bytes32(uint256(153)),
            encodedData
        );

        /// ----------------------------------------------------------
        /// ----------------------------------------------------------
        /// ----------------------------------------------------------

        address wormholeCore = addresses.getAddress("WORMHOLE_CORE");
        address well = addresses.getAddress("xWELL_PROXY");

        vm.warp(1000);

        deal(well, address(this), governor.quorum());
        xWELL(well).delegate(address(this));

        /// remove restriction so that stack is balanced
        addresses.removeRestriction();

        for (uint256 i = 0; i < proposalIds.length; i++) {
            /// switch back to the Moonbeam fork
            vm.selectFork(MOONBEAM_FORK_ID);

            /// add restriction for moonbeam actions
            addresses.addRestriction(MOONBEAM_CHAIN_ID);

            (
                address[] memory targets,
                uint256[] memory values,
                bytes[] memory calldatas
            ) = governor.getProposalData(proposalIds[i]);

            checkMoonbeamActions(targets);
            {
                // Simulate proposals execution
                (
                    ,
                    ,
                    uint256 votingStartTime,
                    ,
                    uint256 crossChainVoteCollectionEndTimestamp,
                    ,
                    ,
                    ,

                ) = governor.proposalInformation(proposalIds[i]);

                vm.warp(votingStartTime);

                governor.castVote(proposalIds[i], 0);

                vm.warp(crossChainVoteCollectionEndTimestamp + 1);
            }

            bytes memory payload;
            if (targets[targets.length - 1] == wormholeCore) {
                // decode temporal governor calldata
                (, payload, ) = abi.decode(
                    /// 1. strip off function selector
                    /// 2. decode the call to publishMessage payload
                    calldatas[targets.length - 1].slice(
                        4,
                        calldatas[targets.length - 1].length - 4
                    ),
                    (uint32, bytes, uint8)
                );

                uint64 nextSequence = IWormhole(wormholeCore).nextSequence(
                    address(governor)
                );

                /// increments each time the Multichain Governor publishes a message
                /// expect emitting of events to Wormhole Core on Moonbeam if Base actions exist
                vm.expectEmit(true, true, true, true, wormholeCore);

                emit LogMessagePublished(
                    address(governor),
                    nextSequence,
                    0,
                    payload,
                    200
                );
            }

            /// execution
            {
                uint256 totalValue = 0;

                for (uint256 j = 0; j < values.length; j++) {
                    totalValue += values[j];
                }

                governor.execute{value: totalValue}(proposalIds[i]);
            }

            /// remove restriction for moonbeam actions
            addresses.removeRestriction();

            {
                /// supports as many destination networks as needed
                uint256 j = targets.length;

                /// iterate over all targets to check if any of them is the wormhole core
                /// if the target is WormholeCore, run the Temporal Governor logic on the corresponding chain
                while (j != 0) {
                    if (targets[j - 1] == wormholeCore) {
                        console.log(
                            "Executing Temporal Governor for proposal %i: ",
                            proposalIds[i]
                        );

                        // decode temporal governor calldata
                        (, payload, ) = abi.decode(
                            /// 1. strip off function selector
                            /// 2. decode the call to publishMessage payload
                            calldatas[j - 1].slice(
                                4,
                                calldatas[j - 1].length - 4
                            ),
                            (uint32, bytes, uint8)
                        );

                        _execExtChain(payload);
                    }

                    j--;
                }
            }
        }
    }

    function _execExtChain(bytes memory payload) private {
        (
            address temporalGovernorAddress,
            address[] memory baseTargets,
            ,

        ) = abi.decode(payload, (address, address[], uint256[], bytes[]));

        vm.selectFork(BASE_FORK_ID);
        // check if the Temporal Governor address exist on the base chain
        if (address(temporalGovernorAddress).code.length == 0) {
            // if not, checkout to Optimism fork id
            vm.selectFork(OPTIMISM_FORK_ID);
        }

        address expectedTemporalGov = addresses.getAddress("TEMPORAL_GOVERNOR");

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

        try temporalGovernor.executeProposal(vaa) {} catch (bytes memory e) {
            console.log(
                string(
                    abi.encodePacked(
                        "Error executing proposal, error: ",
                        string(e)
                    )
                )
            );
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
