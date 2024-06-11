pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {console} from "@forge-std/console.sol";

import {IMultichainGovernor, MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {ProposalChecker} from "@proposals/proposalTypes/ProposalChecker.sol";
import {String} from "@utils/String.sol";
import {Bytes} from "@utils/Bytes.sol";
import {Address} from "@utils/Address.sol";
import {MIPProposal as Proposal} from "@proposals/MIPProposal.s.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Implementation} from "@test/mock/wormhole/Implementation.sol";

contract LiveProposalsIntegrationTest is Test, ChainIds, ProposalChecker {
    using String for string;
    using Bytes for bytes;
    using Address for address;

    /// @notice addresses contract
    Addresses addresses;

    /// @notice fork ID for moonbeam
    uint256 public moonbeamForkId =
        vm.createFork(vm.envString("MOONBEAM_RPC_URL"));

    /// @notice fork ID for base
    uint256 public baseForkId = vm.createFork(vm.envString("BASE_RPC_URL"));

    /// @notice Multichain Governor address
    address governor;

    /// @notice allows asserting wormhole core correctly emits data to temporal governor
    event LogMessagePublished(
        address indexed sender,
        uint64 sequence,
        uint32 nonce,
        bytes payload,
        uint8 consistencyLevel
    );

    function setUp() public {
        addresses = new Addresses();
        vm.makePersistent(address(addresses));

        vm.selectFork(moonbeamForkId);
        governor = addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY");
    }

    function testLatestBaseProposal() public {
        address deployer = address(this);

        string[] memory inputs = new string[](1);
        inputs[0] = "./get-latest-base-proposal.sh";

        string memory output = string(vm.ffi(inputs));

        Proposal proposal = Proposal(deployCode(output));
        vm.makePersistent(address(proposal));

        proposal.setForkIds(baseForkId, moonbeamForkId);

        vm.selectFork(proposal.primaryForkId());

        proposal.deploy(addresses, deployer);
        proposal.afterDeploy(addresses, deployer);
        proposal.afterDeploySetup(addresses);
        proposal.teardown(addresses, deployer);
        proposal.build(addresses);

        // only runs the proposal if the proposal has not been executed yet
        if (!proposal.checkOnChainCalldata(governor)) {
            proposal.run(addresses, deployer);
            proposal.validate(addresses, deployer);
        }
    }

    function testLatestMoonbeamProposal() public {
        address deployer = address(this);

        string[] memory inputs = new string[](1);
        inputs[0] = "./get-latest-moonbeam-proposal.sh";

        string memory output = string(vm.ffi(inputs));

        Proposal proposal = Proposal(deployCode(output));
        vm.makePersistent(address(proposal));

        proposal.setForkIds(baseForkId, moonbeamForkId);

        vm.selectFork(proposal.primaryForkId());

        proposal.deploy(addresses, deployer);
        proposal.afterDeploy(addresses, deployer);
        proposal.afterDeploySetup(addresses);
        proposal.teardown(addresses, deployer);
        proposal.build(addresses);

        // only runs the proposal if the proposal has not been executed yet
        if (!proposal.checkOnChainCalldata(governor)) {
            proposal.run(addresses, deployer);
            proposal.validate(addresses, deployer);
        }
    }

    function testActiveProposals() public {
        vm.selectFork(moonbeamForkId);

        MultichainGovernor governorContract = MultichainGovernor(governor);

        uint256[] memory proposalIds = governorContract.liveProposals();

        for (uint256 i = 0; i < proposalIds.length; i++) {
            /// always need to select moonbeamForkId before executing a
            /// proposal as end of loop could switch to base for execution
            vm.selectFork(moonbeamForkId);

            uint256 proposalId = proposalIds[i];
            (
                address[] memory targets,
                ,
                bytes[] memory calldatas
            ) = governorContract.getProposalData(proposalId);

            checkMoonbeamActions(targets, addresses);
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

            // Check if there is any action on Base
            address wormholeCore = block.chainid == moonBeamChainId
                ? addresses.getAddress("WORMHOLE_CORE_MOONBEAM")
                : addresses.getAddress("WORMHOLE_CORE_MOONBASE");

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

                /// event LogMessagePublished(address indexed sender, uint64 sequence, uint32 nonce, bytes payload, uint8 consistencyLevel)
                emit LogMessagePublished(
                    governor,
                    nextSequence,
                    0,
                    payload,
                    200
                );
            }
            governorContract.execute(proposalId);

            if (targets[lastIndex] == wormholeCore) {
                vm.selectFork(baseForkId);
                address expectedTemporalGov = addresses.getAddress(
                    "TEMPORAL_GOVERNOR"
                );

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

                    require(
                        temporalGovernorAddress == expectedTemporalGov,
                        "Temporal Governor address mismatch"
                    );

                    checkBaseActions(baseTargets, addresses);
                }

                bytes memory vaa = generateVAA(
                    uint32(block.timestamp),
                    uint16(chainIdToWormHoleId[block.chainid]),
                    governor.toBytes(),
                    payload
                );

                TemporalGovernor temporalGovernor = TemporalGovernor(
                    expectedTemporalGov
                );

                // Deploy the modified Wormhole Core implementation contract which
                // bypass the guardians signature check
                Implementation core = new Implementation();
                address wormhole = block.chainid == baseChainId
                    ? addresses.getAddress("WORMHOLE_CORE_BASE")
                    : addresses.getAddress("WORMHOLE_CORE_SEPOLIA_BASE");

                /// Set the wormhole core address to have the
                /// runtime bytecode of the mock core
                vm.etch(wormhole, address(core).code);

                temporalGovernor.queueProposal(vaa);

                vm.warp(block.timestamp + temporalGovernor.proposalDelay());

                temporalGovernor.executeProposal(vaa);
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
